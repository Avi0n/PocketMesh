// BLEStateMachineProtocol.swift

@preconcurrency import CoreBluetooth
import Foundation

/// Protocol for BLE state machine operations used by ConnectionManager.
/// Enables dependency injection for testing.
public protocol BLEStateMachineProtocol: Actor {

    // MARK: - State Properties

    /// Whether the state machine is currently connected to a device
    var isConnected: Bool { get }

    /// Whether the state machine is currently handling iOS auto-reconnect or state restoration
    var isAutoReconnecting: Bool { get }

    /// UUID of the currently connected device, or nil if not connected
    var connectedDeviceID: UUID? { get }

    /// Current phase name for diagnostic logging
    var currentPhaseName: String { get }

    /// Current peripheral state for diagnostic logging (nil if no peripheral)
    var currentPeripheralState: String? { get }

    /// Current CBCentralManager state name for diagnostic logging
    var centralManagerStateName: String { get }

    // MARK: - Methods

    /// Checks if a device is connected to the system (possibly by another app).
    /// - Parameter deviceID: The UUID of the device to check
    /// - Returns: `true` if the device is connected to the system
    func isDeviceConnectedToSystem(_ deviceID: UUID) -> Bool

    /// Activates the central manager if needed.
    func activate()

    /// Sets a handler for auto-reconnecting events.
    /// Called when device disconnects but iOS is attempting automatic reconnection.
    func setAutoReconnectingHandler(_ handler: @escaping @Sendable (UUID) -> Void)

    /// Sets a handler called when Bluetooth powers on
    func setBluetoothPoweredOnHandler(_ handler: @escaping @Sendable () -> Void)

    /// Sets a handler for Bluetooth state changes
    func setBluetoothStateChangeHandler(_ handler: @escaping @Sendable (CBManagerState) -> Void)

    /// Sets the delay between write operations for pacing.
    func setWritePacingDelay(_ delay: TimeInterval)

    /// Gracefully shuts down the state machine, resuming all pending operations.
    /// Call before dropping the last reference to the actor.
    func shutdown()
}
