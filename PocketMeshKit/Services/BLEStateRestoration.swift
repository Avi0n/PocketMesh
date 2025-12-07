@preconcurrency import CoreBluetooth
import Foundation

// MARK: - BLE State Restoration Delegate

/// Protocol for receiving BLE state restoration events.
public protocol BLEStateRestorationDelegate: AnyObject, Sendable {
    /// Called when BLE connection is restored after app termination.
    func bleStateRestoration(_ restoration: BLEStateRestoration, didRestoreConnection deviceID: UUID) async

    /// Called when restoration detects a previously connected device that needs reconnection.
    func bleStateRestoration(_ restoration: BLEStateRestoration, shouldReconnectTo deviceID: UUID) async -> Bool

    /// Called when the connection is lost unexpectedly.
    func bleStateRestoration(_ restoration: BLEStateRestoration, didLoseConnection deviceID: UUID, error: Error?) async

    /// Called when background BLE processing is available.
    func bleStateRestorationDidBecomeAvailable(_ restoration: BLEStateRestoration) async
}

// MARK: - BLE State Restoration

/// Manages BLE state preservation and restoration for background operation.
/// This service coordinates with the main BLEService to:
/// - Preserve connection state before app termination
/// - Restore connections after app relaunch
/// - Handle background reconnection
/// - Manage connection loss events
@MainActor
@Observable
public final class BLEStateRestoration {

    // MARK: - Properties

    /// Whether state restoration is enabled
    public private(set) var isEnabled: Bool = true

    /// Whether we're currently restoring state
    public private(set) var isRestoring: Bool = false

    /// The last known connected device ID (persisted)
    public private(set) var lastConnectedDeviceID: UUID? {
        didSet {
            if let deviceID = lastConnectedDeviceID {
                UserDefaults.standard.set(deviceID.uuidString, forKey: userDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: userDefaultsKey)
            }
        }
    }

    /// Whether background BLE is currently active
    public private(set) var isBackgroundActive: Bool = false

    /// The last connection timestamp
    public private(set) var lastConnectionDate: Date?

    /// Delegate for state restoration events
    public weak var delegate: (any BLEStateRestorationDelegate)?

    // MARK: - Private Properties

    private let userDefaultsKey = "com.pocketmesh.ble.lastConnectedDevice"
    private var reconnectionAttempts: Int = 0
    private let maxReconnectionAttempts: Int = 3
    private let reconnectionDelay: TimeInterval = 2.0

    // MARK: - Initialization

    public init() {
        // Load last connected device from UserDefaults
        if let uuidString = UserDefaults.standard.string(forKey: userDefaultsKey),
           let uuid = UUID(uuidString: uuidString) {
            lastConnectedDeviceID = uuid
        }
    }

    // MARK: - Public Methods

    /// Enables state restoration with the given BLE service.
    public func enable() {
        isEnabled = true
    }

    /// Disables state restoration.
    public func disable() {
        isEnabled = false
        lastConnectedDeviceID = nil
    }

    /// Records a successful connection for state restoration.
    public func recordConnection(deviceID: UUID) {
        guard isEnabled else { return }

        lastConnectedDeviceID = deviceID
        lastConnectionDate = Date()
        reconnectionAttempts = 0
    }

    /// Records a disconnection and clears state if intentional.
    public func recordDisconnection(intentional: Bool) {
        if intentional {
            lastConnectedDeviceID = nil
            lastConnectionDate = nil
        }
        reconnectionAttempts = 0
    }

    /// Called when the app enters background.
    public func appDidEnterBackground() {
        isBackgroundActive = true
    }

    /// Called when the app enters foreground.
    public func appWillEnterForeground() {
        isBackgroundActive = false
    }

    /// Called by BLEService when state is restored from iOS.
    /// Returns the device ID if we should attempt reconnection.
    public func handleStateRestoration(restoredPeripheralIDs: [UUID]) async -> UUID? {
        guard isEnabled else { return nil }

        isRestoring = true
        defer { isRestoring = false }

        // Check if any restored peripheral matches our last connected device
        if let lastDevice = lastConnectedDeviceID,
           restoredPeripheralIDs.contains(lastDevice) {
            await delegate?.bleStateRestoration(self, didRestoreConnection: lastDevice)
            return lastDevice
        }

        // If we have a last connected device but it wasn't in the restored list,
        // ask delegate if we should attempt reconnection
        if let lastDevice = lastConnectedDeviceID {
            let shouldReconnect = await delegate?.bleStateRestoration(self, shouldReconnectTo: lastDevice) ?? false
            if shouldReconnect {
                return lastDevice
            }
        }

        return nil
    }

    /// Handles unexpected connection loss.
    public func handleConnectionLoss(deviceID: UUID, error: Error?) async {
        guard isEnabled else { return }

        await delegate?.bleStateRestoration(self, didLoseConnection: deviceID, error: error)

        // If this was the last connected device and we're in background, we may want to attempt reconnection
        if deviceID == lastConnectedDeviceID && isBackgroundActive {
            // Don't clear the device ID - iOS may reconnect automatically
            // or we may attempt manual reconnection
        }
    }

    /// Attempts to reconnect to the last connected device.
    /// Returns true if reconnection should be attempted.
    public func shouldAttemptReconnection() -> Bool {
        guard isEnabled else { return false }
        guard lastConnectedDeviceID != nil else { return false }
        guard reconnectionAttempts < maxReconnectionAttempts else { return false }

        reconnectionAttempts += 1
        return true
    }

    /// Gets the delay before the next reconnection attempt.
    public func getReconnectionDelay() -> TimeInterval {
        // Exponential backoff: 2s, 4s, 8s
        return reconnectionDelay * pow(2.0, Double(reconnectionAttempts - 1))
    }

    /// Resets reconnection attempt counter (call after successful connection).
    public func resetReconnectionAttempts() {
        reconnectionAttempts = 0
    }

    /// Called when background BLE becomes available.
    public func backgroundBLEDidBecomeAvailable() async {
        await delegate?.bleStateRestorationDidBecomeAvailable(self)
    }

    // MARK: - State Persistence

    /// Returns info about the last connection for display purposes.
    public func getLastConnectionInfo() -> (deviceID: UUID, date: Date)? {
        guard let deviceID = lastConnectedDeviceID,
              let date = lastConnectionDate else {
            return nil
        }
        return (deviceID, date)
    }

    /// Clears all persisted state.
    public func clearPersistedState() {
        lastConnectedDeviceID = nil
        lastConnectionDate = nil
        reconnectionAttempts = 0
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}

// MARK: - Background Task Support

public extension BLEStateRestoration {

    /// Identifier for background BLE processing task.
    static let backgroundTaskIdentifier = "com.pocketmesh.ble.background-refresh"

    /// Schedules background processing if available.
    func scheduleBackgroundProcessing() {
        // Note: Background app refresh must be enabled in capabilities
        // and registered in the app delegate or scene delegate

        // For iOS 13+, use BGTaskScheduler instead of deprecated methods
        // This is a placeholder - actual implementation depends on iOS version
        // and app architecture (UIKit vs SwiftUI lifecycle)
    }
}
