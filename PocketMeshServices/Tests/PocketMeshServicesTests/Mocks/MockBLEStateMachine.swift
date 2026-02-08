@preconcurrency import CoreBluetooth
import Foundation
@testable import PocketMeshServices

/// Mock BLE state machine for testing ConnectionManager.
/// Uses actor for thread-safe mutable state access.
public actor MockBLEStateMachine: BLEStateMachineProtocol {

    // MARK: - Stubs

    public var stubbedIsConnected: Bool = false
    public var stubbedIsAutoReconnecting: Bool = false
    public var stubbedConnectedDeviceID: UUID?
    public var stubbedCurrentPhaseName: String = "idle"
    public var stubbedCurrentPeripheralState: String?
    public var stubbedCentralManagerStateName: String = "poweredOn"
    public var stubbedIsDeviceConnectedToSystem: Bool = false

    // MARK: - Protocol Properties

    public var isConnected: Bool { stubbedIsConnected }
    public var isAutoReconnecting: Bool { stubbedIsAutoReconnecting }
    public var connectedDeviceID: UUID? { stubbedConnectedDeviceID }
    public var currentPhaseName: String { stubbedCurrentPhaseName }
    public var currentPeripheralState: String? { stubbedCurrentPeripheralState }
    public var centralManagerStateName: String { stubbedCentralManagerStateName }

    // MARK: - Recorded Invocations

    public private(set) var activateCallCount = 0
    public private(set) var isDeviceConnectedToSystemCalls: [UUID] = []

    // MARK: - Captured Handlers

    private var autoReconnectingHandler: (@Sendable (UUID) -> Void)?
    private var bluetoothPoweredOnHandler: (@Sendable () -> Void)?
    private var bluetoothStateChangeHandler: (@Sendable (CBManagerState) -> Void)?

    // MARK: - Initialization

    public init() {}

    // MARK: - Protocol Methods

    public func isDeviceConnectedToSystem(_ deviceID: UUID) -> Bool {
        isDeviceConnectedToSystemCalls.append(deviceID)
        return stubbedIsDeviceConnectedToSystem
    }

    public func activate() {
        activateCallCount += 1
    }

    public func setAutoReconnectingHandler(_ handler: @escaping @Sendable (UUID) -> Void) {
        autoReconnectingHandler = handler
    }

    public func setBluetoothPoweredOnHandler(_ handler: @escaping @Sendable () -> Void) {
        bluetoothPoweredOnHandler = handler
    }

    public func setBluetoothStateChangeHandler(_ handler: @escaping @Sendable (CBManagerState) -> Void) {
        bluetoothStateChangeHandler = handler
    }

    public func setWritePacingDelay(_ delay: TimeInterval) {
        // No-op for testing
    }

    public private(set) var shutdownCallCount = 0

    public func shutdown() {
        shutdownCallCount += 1
    }

    // MARK: - Test Helpers

    /// Resets all stubs and recorded invocations
    public func reset() {
        stubbedIsConnected = false
        stubbedIsAutoReconnecting = false
        stubbedConnectedDeviceID = nil
        stubbedCurrentPhaseName = "idle"
        stubbedCurrentPeripheralState = nil
        stubbedCentralManagerStateName = "poweredOn"
        stubbedIsDeviceConnectedToSystem = false
        activateCallCount = 0
        isDeviceConnectedToSystemCalls = []
        autoReconnectingHandler = nil
        bluetoothPoweredOnHandler = nil
        bluetoothStateChangeHandler = nil
    }

    /// Simulates auto-reconnecting event
    public func simulateAutoReconnecting(deviceID: UUID) {
        autoReconnectingHandler?(deviceID)
    }

    /// Simulates Bluetooth powered on event
    public func simulateBluetoothPoweredOn() {
        bluetoothPoweredOnHandler?()
    }

    /// Simulates a Bluetooth state change event
    public func simulateBluetoothStateChange(_ state: CBManagerState) {
        bluetoothStateChangeHandler?(state)
    }
}
