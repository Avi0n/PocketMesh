@preconcurrency import CoreBluetooth
import Foundation
import MeshCore
import os

/// iOS BLE transport using the BLEStateMachine.
///
/// This is a thin wrapper around `BLEStateMachine` that conforms to `MeshTransport`.
/// The state machine handles all CoreBluetooth complexity including:
///
/// - **State restoration**: Background app relaunch via CoreBluetooth restoration
/// - **Auto-reconnect**: iOS 17+ automatic reconnection handling
/// - **Proper cleanup**: Continuation and resource management on all transitions
/// - **Device switching**: Switch between devices without full disconnect/reconnect
///
/// ## Usage
///
/// ```swift
/// // Basic usage with shared state machine
/// let stateMachine = BLEStateMachine()
/// let transport = iOSBLETransport(stateMachine: stateMachine)
/// await transport.setDeviceID(deviceUUID)
/// try await transport.connect()
///
/// // Switch to a different device
/// try await transport.switchDevice(to: otherDeviceUUID)
/// ```
public actor iOSBLETransport: MeshTransport {

    private let logger = Logger(subsystem: "com.pocketmesh", category: "iOSBLETransport")

    private let stateMachine: BLEStateMachine
    private var deviceID: UUID?
    private var dataStream: AsyncStream<Data>?

    // MARK: - Initialization

    /// Creates an iOS BLE transport with an optional shared state machine.
    ///
    /// - Parameter stateMachine: The BLE state machine to use. If nil, creates a new one.
    public init(stateMachine: BLEStateMachine? = nil) {
        self.stateMachine = stateMachine ?? BLEStateMachine()
    }

    // MARK: - Configuration

    /// Sets the device UUID to connect to.
    ///
    /// - Parameter id: The UUID of the BLE device.
    public func setDeviceID(_ id: UUID) {
        deviceID = id
    }

    /// Sets a handler for disconnection events.
    ///
    /// - Parameter handler: Called when the device disconnects, with the device ID and optional error.
    public func setDisconnectionHandler(_ handler: @escaping @Sendable (UUID, Error?) -> Void) async {
        await stateMachine.setDisconnectionHandler(handler)
    }

    /// Sets a handler for reconnection events.
    ///
    /// When iOS auto-reconnect completes, the transport captures the data stream
    /// and then calls your handler. The `receivedData` property will be ready
    /// when your handler is called.
    ///
    /// - Parameter handler: Called when iOS auto-reconnect completes successfully.
    public func setReconnectionHandler(_ handler: @escaping @Sendable (UUID) -> Void) async {
        await stateMachine.setReconnectionHandler { [weak self] deviceID, stream in
            Task {
                // First capture the stream for this transport
                await self?.setDataStream(stream)
                // Then call user's handler (stream is now ready)
                handler(deviceID)
            }
        }
    }

    /// Sets the data stream (used internally for reconnection)
    private func setDataStream(_ stream: AsyncStream<Data>) {
        self.dataStream = stream
    }

    // MARK: - MeshTransport Protocol

    /// Whether the transport is currently connected to a device.
    public var isConnected: Bool {
        get async { await stateMachine.isConnected }
    }

    /// Async stream of data received from the connected device.
    ///
    /// Returns an empty stream if not connected.
    public var receivedData: AsyncStream<Data> {
        dataStream ?? AsyncStream { $0.finish() }
    }

    /// Connects to the configured device.
    ///
    /// This method is idempotent: if already connected to the same device,
    /// it returns without error. Use ``switchDevice(to:)`` to change devices.
    ///
    /// - Throws: `BLEError.deviceNotFound` if no device ID is set.
    /// - Throws: `BLEError.connectionFailed` if connected to a different device.
    /// - Throws: `BLEError` for connection failures.
    public func connect() async throws {
        let connectedID = await stateMachine.connectedDeviceID
        let effectiveDeviceID = self.deviceID ?? connectedID

        guard let deviceID = effectiveDeviceID else {
            throw BLEError.deviceNotFound
        }

        // Already connected - check if it's the same device
        if await stateMachine.isConnected {
            if connectedID == deviceID {
                logger.debug("Already connected to device: \(deviceID)")
                return
            } else {
                throw BLEError.connectionFailed("Already connected to different device: \(connectedID?.uuidString ?? "unknown"). Use switchDevice() instead.")
            }
        }

        logger.info("Connecting to device: \(deviceID)")
        dataStream = try await stateMachine.connect(to: deviceID)
    }

    /// Disconnects from the current device.
    public func disconnect() async {
        logger.info("Disconnecting")
        await stateMachine.disconnect()
        dataStream = nil
    }

    /// Sends data to the connected device.
    ///
    /// - Parameter data: The data to send.
    /// - Throws: `BLEError.notConnected` if not connected.
    /// - Throws: `BLEError.writeError` if the write fails.
    public func send(_ data: Data) async throws {
        try await stateMachine.send(data)
    }

    // MARK: - Extended API

    /// UUID of the currently connected device, or nil if not connected.
    public var connectedDeviceID: UUID? {
        get async { await stateMachine.connectedDeviceID }
    }

    /// Switches to a different device.
    ///
    /// Disconnects from the current device (if any) and connects to the new one.
    /// More efficient than separate disconnect/connect calls.
    ///
    /// - Parameter deviceID: UUID of the new device to connect to.
    /// - Throws: `BLEError` if connection fails.
    public func switchDevice(to deviceID: UUID) async throws {
        logger.info("Switching to device: \(deviceID)")
        self.deviceID = deviceID
        dataStream = try await stateMachine.switchDevice(to: deviceID)
    }
}
