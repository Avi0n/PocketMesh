#if canImport(UIKit)
import AccessorySetupKit
import CoreBluetooth
import UIKit
import os

/// Delegate protocol for accessory state changes
/// Must be @MainActor since implementations access main-actor-isolated state
@MainActor
public protocol AccessorySetupKitServiceDelegate: AnyObject {
    /// Called when an accessory is removed from Settings > Accessories
    func accessorySetupKitService(_ service: AccessorySetupKitService, didRemoveAccessoryWithID bluetoothID: UUID)

    /// Called when pairing fails (e.g., wrong PIN). The device should be cleaned up from local storage.
    func accessorySetupKitService(_ service: AccessorySetupKitService, didFailPairingForAccessoryWithID bluetoothID: UUID)
}

/// Manages AccessorySetupKit session for device discovery and pairing.
///
/// AccessorySetupKit is Apple's modern framework for Bluetooth accessory setup.
/// Starting with iOS 26, only apps using AccessorySetupKit will be relaunched
/// for Bluetooth state restoration events.
///
/// ## Usage
///
/// ```swift
/// let accessoryService = AccessorySetupKitService()
/// try await accessoryService.activateSession()
/// let deviceUUID = try await accessoryService.showPicker()
/// ```
@MainActor @Observable
public final class AccessorySetupKitService {
    private let logger = PersistentLogger(subsystem: "com.pocketmesh", category: "AccessorySetupKit")

    private var session: ASAccessorySession?

    /// Previously paired accessories available after session activation
    public private(set) var pairedAccessories: [ASAccessory] = []

    /// Whether the session is currently active
    public private(set) var isSessionActive = false

    /// Delegate for accessory state changes
    public weak var delegate: AccessorySetupKitServiceDelegate?

    /// Pending picker result continuation (for async/await bridge)
    private var pickerContinuation: CheckedContinuation<UUID, Error>?

    /// Pending activation continuation
    private var activationContinuation: CheckedContinuation<Void, Error>?

    /// Pending rename continuation
    private var renameContinuation: CheckedContinuation<Void, Error>?

    public init() {}

    // MARK: - Continuation Safety

    /// Safely resume the picker continuation exactly once
    /// Clears continuation BEFORE resuming to prevent double-resume race conditions
    private func resumePickerContinuation(with result: Result<UUID, Error>) {
        guard let continuation = pickerContinuation else { return }
        pickerContinuation = nil  // Clear BEFORE resuming
        switch result {
        case .success(let uuid):
            continuation.resume(returning: uuid)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    // MARK: - Discovery Descriptor

    private var discoveryDescriptor: ASDiscoveryDescriptor {
        let descriptor = ASDiscoveryDescriptor()
        descriptor.bluetoothServiceUUID = CBUUID(string: BLEServiceUUID.nordicUART)
        descriptor.bluetoothNameSubstring = "MeshCore-"
        return descriptor
    }

    // MARK: - Session Management

    /// Activate the AccessorySetupKit session
    /// Uses Apple's recommended closure pattern to avoid AsyncStream issues
    public func activateSession() async throws {
        guard session == nil else { return }

        let newSession = ASAccessorySession()
        session = newSession

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.activationContinuation = continuation

            newSession.activate(on: .main) { [weak self] event in
                guard let self else { return }
                self.handleEvent(event)

                // Resume activation continuation only once
                if event.eventType == .activated {
                    self.isSessionActive = true
                    self.pairedAccessories = newSession.accessories
                    self.logger.info("ASAccessorySession activated with \(self.pairedAccessories.count) accessories")
                    self.activationContinuation?.resume()
                    self.activationContinuation = nil
                } else if event.eventType == .invalidated {
                    self.activationContinuation?.resume(throwing: AccessorySetupKitError.sessionInvalidated)
                    self.activationContinuation = nil
                }
            }
        }
    }

    /// Handle incoming ASK events
    /// Called directly from session's event handler closure
    private func handleEvent(_ event: ASAccessoryEvent) {
        switch event.eventType {
        case .activated:
            // Handled in activateSession continuation
            break

        case .invalidated:
            logger.error("ASAccessorySession invalidated")
            isSessionActive = false
            pairedAccessories = []
            pickerContinuation?.resume(throwing: AccessorySetupKitError.sessionInvalidated)
            pickerContinuation = nil
            renameContinuation?.resume(throwing: AccessorySetupKitError.sessionInvalidated)
            renameContinuation = nil

        case .accessoryAdded:
            if let accessory = event.accessory {
                pairedAccessories = session?.accessories ?? []
                logger.info("Accessory added: \(accessory.displayName)")

                if let bluetoothID = accessory.bluetoothIdentifier {
                    resumePickerContinuation(with: .success(bluetoothID))
                } else {
                    resumePickerContinuation(with: .failure(AccessorySetupKitError.noBluetoothIdentifier))
                }
            }

        case .accessoryRemoved:
            if let accessory = event.accessory,
               let bluetoothID = accessory.bluetoothIdentifier {
                logger.info("Accessory removed: \(accessory.displayName)")
                pairedAccessories = session?.accessories ?? []
                // Notify delegate to clear stored state
                delegate?.accessorySetupKitService(self, didRemoveAccessoryWithID: bluetoothID)
            }

        case .accessoryChanged:
            pairedAccessories = session?.accessories ?? []
            logger.info("Accessory changed")
            // Resume rename continuation if pending (rename triggers accessoryChanged)
            if let continuation = renameContinuation {
                renameContinuation = nil
                continuation.resume()
            }

        case .pickerDidPresent:
            logger.info("Picker presented")

        case .pickerDidDismiss:
            logger.info("Picker dismissed")
            // If we still have a pending continuation, user cancelled
            resumePickerContinuation(with: .failure(AccessorySetupKitError.pickerDismissed))

        case .pickerSetupBridging:
            logger.info("Picker bridging...")

        case .pickerSetupPairing:
            logger.info("User entering PIN...")

        case .pickerSetupFailed:
            if let error = event.error {
                logger.error("Pairing failed: \(error.localizedDescription)")

                // Clean up failed accessory so it can appear in picker again
                if let accessory = event.accessory,
                   let bluetoothID = accessory.bluetoothIdentifier {
                    logger.info("Cleaning up failed pairing for \(accessory.displayName)")

                    // Remove from ASK if it's in pairedAccessories
                    if pairedAccessories.contains(where: { $0.bluetoothIdentifier == bluetoothID }) {
                        Task {
                            do {
                                try await self.removeAccessory(accessory)
                                self.logger.info("Removed failed accessory from ASK")
                            } catch {
                                self.logger.warning("Failed to remove accessory from ASK: \(error.localizedDescription)")
                            }
                        }
                    }

                    // Notify delegate to clean up SwiftData
                    delegate?.accessorySetupKitService(self, didFailPairingForAccessoryWithID: bluetoothID)
                }

                resumePickerContinuation(with: .failure(AccessorySetupKitError.pairingFailed(error.localizedDescription)))
            }

        case .pickerSetupRename:
            logger.info("Picker rename step")

        case .migrationComplete:
            logger.info("Migration complete")

        case .unknown:
            // Explicit handling per Apple sample code
            logger.info("Received unknown event type")

        @unknown default:
            // Reserve for future event types
            logger.warning("Received future event type: \(String(describing: event.eventType))")
        }
    }

    /// Show the accessory picker for new device pairing
    /// - Returns: The Bluetooth identifier (UUID) for the paired device
    public func showPicker() async throws -> UUID {
        guard let session else {
            throw AccessorySetupKitError.sessionNotActive
        }

        guard pickerContinuation == nil else {
            throw AccessorySetupKitError.pickerAlreadyActive
        }

        // Configure picker display settings (iOS 26+ only)
        if #available(iOS 26.0, *) {
            if session.pickerDisplaySettings == nil {
                session.pickerDisplaySettings = ASPickerDisplaySettings()
            }
        }

        // Create picker display item with properly-sized image (180x120 as per Apple docs)
        let displayItem = ASPickerDisplayItem(
            name: "MeshCore Device",
            productImage: createGenericProductImage(),
            descriptor: discoveryDescriptor
        )

        return try await withCheckedThrowingContinuation { continuation in
            self.pickerContinuation = continuation

            session.showPicker(for: [displayItem]) { [weak self] error in
                guard let self else { return }

                Task { @MainActor in
                    if let error = error as? ASError {
                        self.logger.error("Picker error: \(error.localizedDescription)")

                        switch error.code {
                        case .pickerRestricted:
                            self.resumePickerContinuation(with: .failure(AccessorySetupKitError.pickerRestricted))
                        case .pickerAlreadyActive:
                            self.resumePickerContinuation(with: .failure(AccessorySetupKitError.pickerAlreadyActive))
                        case .userCancelled:
                            // User explicitly cancelled (error code 700) - not an error condition
                            // Will be handled by pickerDidDismiss event
                            return
                        case .discoveryTimeout:
                            self.resumePickerContinuation(with: .failure(AccessorySetupKitError.discoveryTimeout))
                        case .connectionFailed:
                            self.resumePickerContinuation(with: .failure(AccessorySetupKitError.connectionFailed))
                        default:
                            self.logger.error("Unexpected picker error code: \(error.code.rawValue)")
                        }
                    } else if let error {
                        self.logger.error("Picker error: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Remove an accessory from the system
    /// Note: iOS 26 shows a confirmation dialog to the user
    public func removeAccessory(_ accessory: ASAccessory) async throws {
        guard let session else {
            throw AccessorySetupKitError.sessionNotActive
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            session.removeAccessory(accessory) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        pairedAccessories = session.accessories
    }

    /// Shows the system rename sheet for an accessory
    /// - Parameter accessory: The accessory to rename
    /// Note: ASK's renameAccessory callback may not fire on success, only on error.
    /// We handle success via the .accessoryChanged event instead.
    public func renameAccessory(_ accessory: ASAccessory) async throws {
        guard let session else {
            throw AccessorySetupKitError.sessionNotActive
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.renameContinuation = continuation

            session.renameAccessory(accessory) { [weak self] error in
                guard let self else { return }
                Task { @MainActor in
                    // Only handle errors here - success is handled via .accessoryChanged event
                    if let error {
                        self.renameContinuation = nil
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }

    /// Find a paired accessory by its Bluetooth identifier
    public func accessory(for bluetoothID: UUID) -> ASAccessory? {
        pairedAccessories.first { $0.bluetoothIdentifier == bluetoothID }
    }

    /// Invalidate the session
    public func invalidateSession() {
        pickerContinuation?.resume(throwing: AccessorySetupKitError.sessionInvalidated)
        pickerContinuation = nil
        activationContinuation?.resume(throwing: AccessorySetupKitError.sessionInvalidated)
        activationContinuation = nil
        renameContinuation?.resume(throwing: AccessorySetupKitError.sessionInvalidated)
        renameContinuation = nil
        session?.invalidate()
        session = nil
        isSessionActive = false
        pairedAccessories = []
    }

    // MARK: - Private Helpers

    /// Creates a generic product image for the ASK picker
    /// Per Apple docs: Container size should be 180x120 points with transparent background
    /// Padding added for visual balance in picker carousel (per WWDC24 guidance)
    /// Note: Device type (T1000e, T-Deck, Heltec, etc.) cannot be determined
    /// until after connection via CMD_DEVICE_QUERY.
    ///
    /// Alternative: Could use `.withRenderingMode(.alwaysTemplate)` with `.label` color
    /// for better automatic dark mode adaptation, but explicit blue tint is acceptable.
    private func createGenericProductImage() -> UIImage {
        let size = CGSize(width: 180, height: 120)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            // Transparent background (required for light/dark mode)
            UIColor.clear.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            // Draw centered SF Symbol with padding for visual balance
            // Smaller point size (50 vs 60) creates breathing room in carousel
            let config = UIImage.SymbolConfiguration(pointSize: 50, weight: .regular)
            guard let symbol = UIImage(systemName: "antenna.radiowaves.left.and.right", withConfiguration: config)?
                .withTintColor(.systemBlue, renderingMode: .alwaysOriginal) else { return }

            let symbolSize = symbol.size
            let origin = CGPoint(
                x: (size.width - symbolSize.width) / 2,
                y: (size.height - symbolSize.height) / 2
            )
            symbol.draw(at: origin)
        }
    }
}

// MARK: - Errors

public enum AccessorySetupKitError: LocalizedError {
    case sessionNotActive
    case sessionInvalidated
    case pickerDismissed
    case pickerRestricted
    case pickerAlreadyActive
    case pairingFailed(String)
    case noBluetoothIdentifier
    case discoveryTimeout
    case connectionFailed

    public var errorDescription: String? {
        switch self {
        case .sessionNotActive:
            return "Bluetooth is not ready. Please ensure Bluetooth is enabled and try again."
        case .sessionInvalidated:
            return "Bluetooth session ended unexpectedly. Please restart the app."
        case .pickerDismissed:
            return "Device selection was cancelled."
        case .pickerRestricted:
            return "Cannot show device picker. Please check that Bluetooth is enabled and the app has permission."
        case .pickerAlreadyActive:
            return "Device picker is already showing."
        case .pairingFailed(let reason):
            return "Pairing failed: \(reason)"
        case .noBluetoothIdentifier:
            return "Selected device does not support Bluetooth connection."
        case .discoveryTimeout:
            return "No devices found. Make sure your device is powered on and nearby."
        case .connectionFailed:
            return "Could not connect to the device. Please try again."
        }
    }
}

#else
// macOS stubs for compilation
import Foundation

public struct ASAccessory {
    public var bluetoothIdentifier: UUID? { nil }
    public var displayName: String { "" }
}

@MainActor
public protocol AccessorySetupKitServiceDelegate: AnyObject {
    func accessorySetupKitService(_ service: AccessorySetupKitService, didRemoveAccessoryWithID bluetoothID: UUID)
    func accessorySetupKitService(_ service: AccessorySetupKitService, didFailPairingForAccessoryWithID bluetoothID: UUID)
}

@MainActor @Observable
public final class AccessorySetupKitService {
    public private(set) var pairedAccessories: [ASAccessory] = []
    public private(set) var isSessionActive = false
    public weak var delegate: AccessorySetupKitServiceDelegate?

    public init() {}

    public func activateSession() async throws {}
    public func showPicker() async throws -> UUID { throw AccessorySetupKitError.sessionNotActive }
    public func removeAccessory(_ accessory: ASAccessory) async throws {}
    public func renameAccessory(_ accessory: ASAccessory) async throws {}
    public func accessory(for bluetoothID: UUID) -> ASAccessory? { nil }
    public func invalidateSession() {}
}

public enum AccessorySetupKitError: LocalizedError {
    case sessionNotActive
    case sessionInvalidated
    case pickerDismissed
    case pickerRestricted
    case pickerAlreadyActive
    case pairingFailed(String)
    case noBluetoothIdentifier
    case discoveryTimeout
    case connectionFailed

    public var errorDescription: String? {
        switch self {
        case .sessionNotActive:
            return "Bluetooth is not ready. Please ensure Bluetooth is enabled and try again."
        case .sessionInvalidated:
            return "Bluetooth session ended unexpectedly. Please restart the app."
        case .pickerDismissed:
            return "Device selection was cancelled."
        case .pickerRestricted:
            return "Cannot show device picker. Please check that Bluetooth is enabled and the app has permission."
        case .pickerAlreadyActive:
            return "Device picker is already showing."
        case .pairingFailed(let reason):
            return "Pairing failed: \(reason)"
        case .noBluetoothIdentifier:
            return "Selected device does not support Bluetooth connection."
        case .discoveryTimeout:
            return "No devices found. Make sure your device is powered on and nearby."
        case .connectionFailed:
            return "Could not connect to the device. Please try again."
        }
    }
}
#endif
