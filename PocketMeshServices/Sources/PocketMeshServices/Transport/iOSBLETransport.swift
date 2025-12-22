@preconcurrency import CoreBluetooth
import Foundation
import MeshCore
import os

/// iOS-specific BLE transport with full feature set for production use.
///
/// `iOSBLETransport` implements MeshCore's `MeshTransport` protocol with iOS-specific
/// features including:
///
/// - **State restoration**: Background app relaunch via CoreBluetooth restoration
/// - **Auto-reconnect**: iOS 17+ automatic reconnection handling
/// - **Pairing window**: Tolerant handling during iOS pairing dialog (~30s)
/// - **Send queue**: Serialized send operations (FIFO, one in flight)
/// - **AccessorySetupKit integration**: iOS 26+ requirement for state restoration
///
/// ## Usage
///
/// ```swift
/// // Basic usage
/// let transport = iOSBLETransport(deviceID: deviceUUID)
/// try await transport.connect()
///
/// // With AccessorySetupKit (required for iOS 26+ state restoration)
/// let accessoryService = AccessorySetupKitService()
/// let transport = iOSBLETransport(
///     deviceID: deviceUUID,
///     accessoryService: accessoryService
/// )
/// ```
///
/// ## iOS 26 State Restoration
///
/// Per Apple TN3115 (September 2025), starting in iOS 26, only apps using
/// AccessorySetupKit will be relaunched for Bluetooth state restoration events.
/// Pass an `AccessorySetupKitService` to ensure state restoration eligibility.
public actor iOSBLETransport: MeshTransport {

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.pocketmesh", category: "iOSBLETransport")

    /// The BLE delegate that handles CoreBluetooth callbacks
    private nonisolated let delegate: iOSBLEDelegate

    /// The device UUID to connect to (set via init or setDeviceID)
    private var deviceID: UUID?

    /// AccessorySetupKit service for iOS 26+ state restoration
    private weak var accessoryService: AccessorySetupKitService?

    private var _connectionState: BLEConnectionState = .disconnected {
        didSet {
            if oldValue != _connectionState {
                logger.debug("State: \(String(describing: oldValue)) → \(String(describing: self._connectionState))")
            }
        }
    }

    /// Current connection state
    public var connectionState: BLEConnectionState {
        _connectionState
    }

    /// MeshTransport conformance: Whether the transport is currently connected
    public var isConnected: Bool {
        _connectionState == .connected || _connectionState == .ready
    }

    /// UUID of the currently connected device
    public nonisolated var connectedDeviceID: UUID? {
        delegate.connectedPeripheralID
    }

    /// MeshTransport conformance: Async stream of received data.
    /// Returns the stream created during connect(). If accessed before
    /// connect() succeeds, returns an immediately-finishing empty stream.
    public var receivedData: AsyncStream<Data> {
        guard let stream = _receivedData else {
            // Return empty stream if not connected - will finish immediately
            return AsyncStream { $0.finish() }
        }
        return stream
    }

    /// Whether a send operation is currently in progress
    private var sendInProgress = false

    /// The data stream for the current connection session.
    /// Created fresh on each connect(), nil when disconnected.
    private var _receivedData: AsyncStream<Data>?

    /// Queue of callers waiting to send (FIFO)
    private var sendQueue: [CheckedContinuation<Void, Never>] = []

    /// Tracks whether we're in the initial pairing window where transient errors are expected
    private var inPairingWindow: Bool = false

    /// Timestamp when pairing window started (for timeout calculation)
    private var pairingWindowStart: Date?

    /// Duration of the pairing window - slightly longer than iOS's ~30s pairing dialog timeout
    private let pairingWindowDuration: TimeInterval = 35.0

    /// Stores the last pairing error for more specific error messages
    private var lastPairingError: Error?

    // Event handlers
    private var disconnectionHandler: (@Sendable (UUID, Error?) -> Void)?
    private var reconnectionHandler: (@Sendable (UUID) -> Void)?
    private var sendActivityHandler: (@Sendable (Bool) -> Void)?

    // Timeouts
    private let connectionTimeout: TimeInterval = 10.0
    private let initialSetupTimeout: TimeInterval = 40.0  // Past iOS's ~30s pairing dialog
    private let writeAcknowledgmentTimeout: TimeInterval = 5.0

    // MARK: - Initialization

    /// Creates an iOS BLE transport with a shared BLE delegate.
    ///
    /// Use this initializer to share a single `CBCentralManager` across connection attempts,
    /// avoiding state restoration race conditions.
    ///
    /// - Parameters:
    ///   - delegate: The shared BLE delegate that owns the `CBCentralManager`.
    ///   - accessoryService: Optional AccessorySetupKit service for iOS 26+ state restoration.
    public init(delegate: iOSBLEDelegate, accessoryService: AccessorySetupKitService? = nil) {
        self.delegate = delegate
        self.accessoryService = accessoryService
    }

    /// Creates an iOS BLE transport with its own BLE delegate.
    ///
    /// - Parameters:
    ///   - deviceID: Optional UUID of the device to connect to. Can be set later via `setDeviceID(_:)`.
    ///   - accessoryService: Optional AccessorySetupKit service for iOS 26+ state restoration.
    public init(deviceID: UUID? = nil, accessoryService: AccessorySetupKitService? = nil) {
        self.deviceID = deviceID
        self.accessoryService = accessoryService
        self.delegate = iOSBLEDelegate()
    }

    /// Set the device UUID to connect to
    public func setDeviceID(_ id: UUID) {
        deviceID = id
    }

    // MARK: - MeshTransport Protocol

    /// Connects to the configured device.
    ///
    /// Requires `deviceID` to be set via init or `setDeviceID(_:)`.
    ///
    /// - Throws: `BLEError` if connection fails.
    public func connect() async throws {
        guard let targetDeviceID = deviceID else {
            throw BLEError.deviceNotFound
        }

        let startTime = Date()
        logger.info("Connection attempt starting for device: \(targetDeviceID)")

        // Check if delegate already has this device connected
        if let existingID = delegate.connectedPeripheralID, existingID == targetDeviceID {
            logger.info("Already connected to \(targetDeviceID), skipping redundant connect()")
            _connectionState = .connected

            // Create fresh stream for this session
            _receivedData = delegate.createDataStream()

            // Still need to set up callbacks for this transport
            delegate.setTransportCallbacks(
                onDisconnection: { [weak self] deviceID, error in
                    guard let self else { return }
                    Task { await self.handleDisconnection(deviceID: deviceID, error: error) }
                },
                onReconnection: { [weak self] deviceID in
                    guard let self else { return }
                    Task { await self.handleReconnection(deviceID: deviceID) }
                },
                onStateChange: { [weak self] state in
                    guard let self else { return }
                    Task { await self.handleStateChange(state) }
                }
            )
            return
        }

        // Set up callbacks for this transport
        delegate.setTransportCallbacks(
            onDisconnection: { [weak self] deviceID, error in
                guard let self else { return }
                Task {
                    await self.handleDisconnection(deviceID: deviceID, error: error)
                }
            },
            onReconnection: { [weak self] deviceID in
                guard let self else { return }
                Task {
                    await self.handleReconnection(deviceID: deviceID)
                }
            },
            onStateChange: { [weak self] state in
                guard let self else { return }
                Task {
                    await self.handleStateChange(state)
                }
            }
        )

        // Wait for Bluetooth to be ready
        try await delegate.waitForPoweredOn()

        // Connect to the device
        _connectionState = .connecting
        do {
            try await delegate.connect(to: targetDeviceID, timeout: connectionTimeout, initialSetupTimeout: initialSetupTimeout)
            _connectionState = .connected

            // Create fresh stream for this session
            _receivedData = delegate.createDataStream()

            let elapsedMs = Int(Date().timeIntervalSince(startTime) * 1000)
            logger.info("Connection established in \(elapsedMs)ms")
        } catch {
            _connectionState = .disconnected
            throw error
        }
    }

    /// Disconnects from the device.
    public func disconnect() async {
        clearSendQueue()
        await delegate.disconnect()
        _receivedData = nil
        _connectionState = .disconnected
    }

    /// Sends data to the connected device.
    ///
    /// - Parameter data: The data to send.
    /// - Throws: `BLEError` if not connected or send fails.
    public func send(_ data: Data) async throws {
        // Serialize send operations - only one in flight at a time
        await acquireSendLock()
        defer { releaseSendLock() }

        guard isConnected else {
            throw BLEError.notConnected
        }

        try await delegate.send(data, timeout: writeAcknowledgmentTimeout)
    }

    // MARK: - Extended API (iOS-specific)

    /// Sets a handler for disconnection events
    public func setDisconnectionHandler(_ handler: @escaping @Sendable (UUID, Error?) -> Void) {
        disconnectionHandler = handler
    }

    /// Sets a handler for reconnection events (iOS auto-reconnect completion)
    public func setReconnectionHandler(_ handler: @escaping @Sendable (UUID) -> Void) {
        reconnectionHandler = handler
    }

    /// Set handler for send activity changes
    /// - Parameter handler: Called with `true` when BLE becomes busy, `false` when idle
    public func setSendActivityHandler(_ handler: (@Sendable (Bool) -> Void)?) {
        sendActivityHandler = handler
    }

    /// Enters pairing window mode for tolerating transient errors during iOS pairing
    public func enterPairingWindow() {
        inPairingWindow = true
        pairingWindowStart = Date()
    }

    /// Marks the connection as ready after device initialization
    public func markReady() {
        _connectionState = .ready
    }

    // MARK: - Send Queue Serialization

    private func acquireSendLock() async {
        if !sendInProgress {
            sendInProgress = true
            sendActivityHandler?(true)
            return
        }

        logger.debug("Send queued, waiting for previous operation (\(self.sendQueue.count + 1) waiting)")
        await withCheckedContinuation { continuation in
            sendQueue.append(continuation)
        }
    }

    private func releaseSendLock() {
        if let next = sendQueue.first {
            sendQueue.removeFirst()
            next.resume()
        } else {
            sendInProgress = false
            sendActivityHandler?(false)
        }
    }

    private func clearSendQueue() {
        while let queued = sendQueue.first {
            sendQueue.removeFirst()
            queued.resume()
        }
        sendInProgress = false
    }

    // MARK: - Callback Handlers

    private func handleDisconnection(deviceID: UUID, error: Error?) {
        _connectionState = .disconnected
        clearSendQueue()
        disconnectionHandler?(deviceID, error)
    }

    private func handleReconnection(deviceID: UUID) {
        _connectionState = .connected
        reconnectionHandler?(deviceID)
    }

    private func handleStateChange(_ state: BLEConnectionState) {
        _connectionState = state
    }
}

// MARK: - BLE Delegate

/// Manages CoreBluetooth operations for BLE transport.
///
/// This class owns the `CBCentralManager` and handles all CoreBluetooth delegate callbacks.
/// For proper state restoration handling, create a single instance and share it across
/// connection attempts.
///
/// @unchecked Sendable: CBCentralManagerDelegate requires NSObject. All mutable state protected by continuationLock.
public final class iOSBLEDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {

    private let logger = Logger(subsystem: "com.pocketmesh", category: "iOSBLEDelegate")

    // CoreBluetooth
    // Initialized after super.init() so self can be passed as delegate.
    // Safe: assigned exactly once, read-only after init, class is @unchecked Sendable.
    nonisolated(unsafe) var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private var txCharacteristic: CBCharacteristic?
    private var rxCharacteristic: CBCharacteristic?

    // State restoration
    private let stateRestorationID = "com.pocketmesh.ble.central"

    // Service/Characteristic UUIDs
    private let nordicUARTServiceUUID = CBUUID(string: BLEServiceUUID.nordicUART)
    private let txCharacteristicUUID = CBUUID(string: BLEServiceUUID.txCharacteristic)
    private let rxCharacteristicUUID = CBUUID(string: BLEServiceUUID.rxCharacteristic)

    // Data streaming
    /// Active continuation for yielding received BLE data.
    /// Nil when no connection session is active.
    private var dataContinuation: AsyncStream<Data>.Continuation?

    // Continuation state (thread-safe)
    private let continuationLock = OSAllocatedUnfairLock<ContinuationState>(initialState: ContinuationState())

    private struct ContinuationState {
        var bluetoothReady: CheckedContinuation<Void, Error>?
        var connection: CheckedContinuation<Void, Error>?
        var notification: CheckedContinuation<Void, Error>?
        var write: CheckedContinuation<Void, Error>?
    }

    // Reconnection state
    private var isAutoReconnecting = false
    private var needsResubscriptionAfterReconnect = false

    /// Set when willRestoreState finds a connected peripheral that needs service discovery after poweredOn
    private var pendingRestorationServiceDiscovery = false

    // Callbacks to transport actor
    private var onDisconnection: ((UUID, Error?) -> Void)?
    private var onReconnection: ((UUID) -> Void)?
    private var onStateChange: ((BLEConnectionState) -> Void)?
    private var onBluetoothPoweredOn: (() -> Void)?

    var connectedPeripheralID: UUID? {
        connectedPeripheral?.identifier
    }

    public override init() {
        super.init()

        // Create CBCentralManager with state restoration
        let options: [String: Any] = [
            CBCentralManagerOptionRestoreIdentifierKey: stateRestorationID,
            CBCentralManagerOptionShowPowerAlertKey: true
        ]
        self.centralManager = CBCentralManager(delegate: self, queue: .main, options: options)
    }

    /// Resets the delegate for a new connection attempt.
    ///
    /// Call this before reusing the delegate for a new transport instance.
    /// Clears transport callbacks while preserving the `CBCentralManager` and any restored peripheral.
    public func resetForNewConnection() {
        // Finish any existing stream to signal termination
        dataContinuation?.finish()
        dataContinuation = nil

        // Clear callbacks
        onDisconnection = nil
        onReconnection = nil
        onStateChange = nil
        onBluetoothPoweredOn = nil
        isAutoReconnecting = false
        needsResubscriptionAfterReconnect = false
        // Keep centralManager and connectedPeripheral for state restoration
    }

    /// Creates a fresh AsyncStream for a new connection session.
    ///
    /// This must be called at the start of each connection before iterating.
    /// Calling this will finish any previous stream, signaling termination
    /// to any lingering iterators.
    ///
    /// - Returns: A new AsyncStream that will receive BLE characteristic updates.
    public func createDataStream() -> AsyncStream<Data> {
        // Finish previous stream to signal termination to any old iterators
        dataContinuation?.finish()

        // Create fresh stream for this session
        let (stream, continuation) = AsyncStream.makeStream(of: Data.self)
        self.dataContinuation = continuation
        return stream
    }

    func setTransportCallbacks(
        onDisconnection: @escaping (UUID, Error?) -> Void,
        onReconnection: @escaping (UUID) -> Void,
        onStateChange: @escaping (BLEConnectionState) -> Void
    ) {
        self.onDisconnection = onDisconnection
        self.onReconnection = onReconnection
        self.onStateChange = onStateChange
    }

    /// Sets a handler called when Bluetooth powers on.
    /// Used by ConnectionManager to reconnect after Bluetooth power cycle.
    func setBluetoothPoweredOnHandler(_ handler: @escaping @Sendable () -> Void) {
        onBluetoothPoweredOn = handler
    }

    // MARK: - Public Methods

    func waitForPoweredOn() async throws {
        // If already powered on, return immediately
        if centralManager.state == .poweredOn { return }

        // Only .unsupported is truly permanent (hardware limitation)
        // All other states should wait for delegate callback
        if centralManager.state == .unsupported {
            throw BLEError.bluetoothUnavailable
        }

        // Wait for centralManagerDidUpdateState callback
        // The callback will resume with success (.poweredOn) or throw appropriate error
        try await withCheckedThrowingContinuation { continuation in
            continuationLock.withLock { $0.bluetoothReady = continuation }
        }
    }

    func connect(to deviceID: UUID, timeout: TimeInterval, initialSetupTimeout: TimeInterval) async throws {
        let peripherals = centralManager.retrievePeripherals(withIdentifiers: [deviceID])
        guard let peripheral = peripherals.first else {
            throw BLEError.deviceNotFound
        }

        // Connect with timeout
        try await withThrowingTimeout(seconds: timeout) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.continuationLock.withLock { $0.connection = continuation }
                let options = self.connectionOptions()
                self.centralManager.connect(peripheral, options: options)
            }
        }

        // Subscribe to notifications with timeout
        guard let rx = rxCharacteristic else {
            throw BLEError.characteristicNotFound
        }

        try await withThrowingTimeout(seconds: initialSetupTimeout) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.continuationLock.withLock { $0.notification = continuation }
                peripheral.setNotifyValue(true, for: rx)
            }
        }

        // Stabilization delay
        try await Task.sleep(for: .milliseconds(150))
    }

    func disconnect() async {
        if let peripheral = connectedPeripheral {
            if peripheral.state == .connected, let rx = rxCharacteristic {
                peripheral.setNotifyValue(false, for: rx)
            }
            centralManager.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        txCharacteristic = nil
        rxCharacteristic = nil

        // Clear any pending continuations
        continuationLock.withLock { state in
            state.connection?.resume(throwing: BLEError.notConnected)
            state.connection = nil
            state.notification?.resume(throwing: BLEError.notConnected)
            state.notification = nil
            state.write?.resume(throwing: BLEError.notConnected)
            state.write = nil
        }

        // Finish the data stream to signal termination to consumers
        dataContinuation?.finish()
        dataContinuation = nil

        // Allow Bluetooth stack to process
        try? await Task.sleep(for: .milliseconds(50))
    }

    func send(_ data: Data, timeout: TimeInterval) async throws {
        guard let peripheral = connectedPeripheral,
              let tx = txCharacteristic,
              peripheral.state == .connected else {
            throw BLEError.notConnected
        }

        try await withThrowingTimeout(seconds: timeout) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                self.continuationLock.withLock { $0.write = continuation }
                peripheral.writeValue(data, for: tx, type: .withResponse)
            }
        }
    }

    // MARK: - Private Helpers

    private func connectionOptions() -> [String: Any] {
        var options: [String: Any] = [
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
            CBConnectPeripheralOptionNotifyOnNotificationKey: true
        ]
        options[CBConnectPeripheralOptionEnableAutoReconnect] = true
        return options
    }

    private func withThrowingTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw BLEError.connectionTimeout
            }

            guard let result = try await group.next() else {
                throw BLEError.connectionTimeout
            }
            group.cancelAll()
            return result
        }
    }

    // MARK: - CBCentralManagerDelegate

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        continuationLock.withLock { state in
            switch central.state {
            case .poweredOn:
                state.bluetoothReady?.resume()
                state.bluetoothReady = nil

                // Handle deferred service discovery from state restoration
                if pendingRestorationServiceDiscovery, let peripheral = connectedPeripheral {
                    pendingRestorationServiceDiscovery = false
                    logger.info("State restoration: discovering services after poweredOn")
                    onStateChange?(.connecting)
                    peripheral.discoverServices([nordicUARTServiceUUID])
                }
                // Handle reconnection after Bluetooth power cycle
                else if isAutoReconnecting, let peripheral = connectedPeripheral,
                        peripheral.state != .connected {
                    logger.info("Bluetooth powered on: re-initiating connection to \(peripheral.identifier)")
                    centralManager.connect(peripheral, options: connectionOptions())
                }
                // Notify ConnectionManager for power-cycle recovery
                else {
                    onBluetoothPoweredOn?()
                }
            case .poweredOff:
                // Don't throw immediately - this might be a transient state during XPC re-establishment
                // The connection timeout will handle truly-off Bluetooth
                logger.debug("Bluetooth state: poweredOff (waiting for potential recovery)")
                onStateChange?(.disconnected)
            case .unauthorized:
                // Don't throw immediately - user might grant permission when prompted
                logger.debug("Bluetooth state: unauthorized (waiting for potential authorization)")
            case .unsupported:
                // Only .unsupported is truly permanent - no hardware support
                state.bluetoothReady?.resume(throwing: BLEError.bluetoothUnavailable)
                state.bluetoothReady = nil
            default:
                break
            }
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        peripheral.delegate = self
        peripheral.discoverServices([nordicUARTServiceUUID])
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        continuationLock.withLock { state in
            state.connection?.resume(throwing: BLEError.connectionFailed(error?.localizedDescription ?? "Unknown error"))
            state.connection = nil
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        timestamp: CFAbsoluteTime,
        isReconnecting: Bool,
        error: Error?
    ) {
        if isReconnecting {
            logger.info("System auto-reconnecting")
            isAutoReconnecting = true
            needsResubscriptionAfterReconnect = true
            onStateChange?(.connecting)
            txCharacteristic = nil
            rxCharacteristic = nil
            return
        }

        handleFullDisconnection(peripheral: peripheral, error: error)
    }

    private func handleFullDisconnection(peripheral: CBPeripheral, error: Error?) {
        let deviceID = peripheral.identifier
        isAutoReconnecting = false
        needsResubscriptionAfterReconnect = false

        connectedPeripheral = nil
        txCharacteristic = nil
        rxCharacteristic = nil

        continuationLock.withLock { state in
            state.connection?.resume(throwing: BLEError.connectionFailed("Disconnected"))
            state.connection = nil
            state.notification?.resume(throwing: BLEError.connectionFailed("Disconnected"))
            state.notification = nil
        }

        onDisconnection?(deviceID, error)
    }

    public func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let peripheral = peripherals.first {
            logger.info("State restoration: restoring peripheral")
            connectedPeripheral = peripheral
            peripheral.delegate = self
            needsResubscriptionAfterReconnect = true

            if peripheral.state == .connected {
                // Don't call discoverServices here - CBCentralManager may not be poweredOn yet.
                // Set flag to trigger service discovery after poweredOn state is reached.
                pendingRestorationServiceDiscovery = true
                logger.debug("State restoration: deferring service discovery until poweredOn")
            }
        }
    }

    // MARK: - CBPeripheralDelegate

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil,
              let service = peripheral.services?.first(where: { $0.uuid == nordicUARTServiceUUID }) else {
            continuationLock.withLock { state in
                state.connection?.resume(throwing: BLEError.characteristicNotFound)
                state.connection = nil
            }
            return
        }

        peripheral.discoverCharacteristics([txCharacteristicUUID, rxCharacteristicUUID], for: service)
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard error == nil else {
            continuationLock.withLock { state in
                state.connection?.resume(throwing: BLEError.characteristicNotFound)
                state.connection = nil
            }
            return
        }

        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case txCharacteristicUUID:
                txCharacteristic = characteristic
            case rxCharacteristicUUID:
                rxCharacteristic = characteristic
            default:
                break
            }
        }

        guard txCharacteristic != nil && rxCharacteristic != nil else {
            // Resume continuation with error to prevent caller from waiting indefinitely
            continuationLock.withLock { state in
                state.connection?.resume(throwing: BLEError.characteristicNotFound)
                state.connection = nil
            }
            return
        }

        let isReconnection = needsResubscriptionAfterReconnect
        needsResubscriptionAfterReconnect = false

        if isReconnection {
            // Re-subscribe to notifications after reconnection
            if let rx = rxCharacteristic {
                peripheral.setNotifyValue(true, for: rx)
            }
        } else {
            // Initial connection - resume the connection continuation
            continuationLock.withLock { state in
                state.connection?.resume()
                state.connection = nil
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard error == nil, let data = characteristic.value, !data.isEmpty else { return }
        dataContinuation?.yield(data)
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        continuationLock.withLock { state in
            if let error {
                state.write?.resume(throwing: BLEError.writeError(error.localizedDescription))
            } else {
                state.write?.resume()
            }
            state.write = nil
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == rxCharacteristicUUID else { return }

        // Check if this is a reconnection scenario
        if isAutoReconnecting {
            isAutoReconnecting = false
            if error == nil {
                logger.info("Auto-reconnection complete")
                if let id = peripheral.identifier as UUID? {
                    onReconnection?(id)
                }
            }
            return
        }

        // Initial subscription
        continuationLock.withLock { state in
            if let error {
                state.notification?.resume(throwing: BLEError.characteristicNotFound)
            } else {
                state.notification?.resume()
            }
            state.notification = nil
        }
    }
}
