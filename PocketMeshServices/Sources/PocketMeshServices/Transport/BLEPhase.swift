// BLEPhase.swift
@preconcurrency import CoreBluetooth
import Foundation

/// Represents the complete BLE connection lifecycle as explicit states.
/// Each state owns exactly the resources it needs.
///
/// This enum is marked @unchecked Sendable because it contains non-Sendable
/// CoreBluetooth types (CBPeripheral, CBService, CBCharacteristic). The
/// BLEStateMachine actor ensures these are only accessed from appropriate contexts.
public enum BLEPhase: @unchecked Sendable {

    /// Initial state, no operations in progress
    case idle

    /// Waiting for CBCentralManager to reach .poweredOn
    case waitingForBluetooth(
        continuation: CheckedContinuation<Void, Error>
    )

    /// Actively connecting to a peripheral
    case connecting(
        peripheral: CBPeripheral,
        continuation: CheckedContinuation<Void, Error>,
        timeoutTask: Task<Void, Never>
    )

    /// Connected, discovering services
    case discoveringServices(
        peripheral: CBPeripheral,
        continuation: CheckedContinuation<Void, Error>
    )

    /// Services found, discovering characteristics
    case discoveringCharacteristics(
        peripheral: CBPeripheral,
        service: CBService,
        continuation: CheckedContinuation<Void, Error>
    )

    /// Characteristics found, subscribing to notifications
    case subscribingToNotifications(
        peripheral: CBPeripheral,
        tx: CBCharacteristic,
        rx: CBCharacteristic,
        continuation: CheckedContinuation<Void, Error>
    )

    /// Fully connected and ready for communication
    case connected(
        peripheral: CBPeripheral,
        tx: CBCharacteristic,
        rx: CBCharacteristic,
        dataContinuation: AsyncStream<Data>.Continuation
    )

    /// iOS auto-reconnect in progress
    case autoReconnecting(
        peripheralID: UUID
    )

    /// Intentionally disconnecting
    case disconnecting(
        peripheral: CBPeripheral
    )

    // MARK: - Computed Properties

    /// Human-readable name for logging
    public var name: String {
        switch self {
        case .idle: "idle"
        case .waitingForBluetooth: "waitingForBluetooth"
        case .connecting: "connecting"
        case .discoveringServices: "discoveringServices"
        case .discoveringCharacteristics: "discoveringCharacteristics"
        case .subscribingToNotifications: "subscribingToNotifications"
        case .connected: "connected"
        case .autoReconnecting: "autoReconnecting"
        case .disconnecting: "disconnecting"
        }
    }

    /// Whether this phase represents an active operation (not idle)
    public var isActive: Bool {
        if case .idle = self { return false }
        return true
    }

    /// The peripheral associated with this phase, if any
    public var peripheral: CBPeripheral? {
        switch self {
        case .connecting(let p, _, _),
             .discoveringServices(let p, _),
             .discoveringCharacteristics(let p, _, _),
             .subscribingToNotifications(let p, _, _, _),
             .connected(let p, _, _, _),
             .disconnecting(let p):
            return p
        case .idle, .waitingForBluetooth, .autoReconnecting:
            return nil
        }
    }

    /// The device ID associated with this phase, if any
    public var deviceID: UUID? {
        switch self {
        case .autoReconnecting(let id):
            return id
        default:
            return peripheral?.identifier
        }
    }

    /// Check if transition to another phase is valid (for testing)
    public func canTransition(to other: BLEPhase) -> Bool {
        // For now, all transitions are valid - the state machine enforces logic
        return true
    }
}
