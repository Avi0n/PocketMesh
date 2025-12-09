@preconcurrency import CoreBluetooth
import Foundation

// MARK: - BLE State Restoration Delegate

/// Protocol for receiving BLE state restoration events.
public protocol BLEStateRestorationDelegate: AnyObject, Sendable {
    /// Called when the connection is lost unexpectedly.
    func bleStateRestoration(_ restoration: BLEStateRestoration, didLoseConnection deviceID: UUID, error: Error?) async
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

    // MARK: - Initialization

    public init() {
        // Load last connected device from UserDefaults
        if let uuidString = UserDefaults.standard.string(forKey: userDefaultsKey),
           let uuid = UUID(uuidString: uuidString) {
            lastConnectedDeviceID = uuid
        }
    }

    // MARK: - Public Methods

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

    /// Resets reconnection attempt counter (call after successful connection).
    public func resetReconnectionAttempts() {
        reconnectionAttempts = 0
    }
}
