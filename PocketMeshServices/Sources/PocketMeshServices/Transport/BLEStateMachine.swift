// BLEStateMachine.swift
@preconcurrency import CoreBluetooth
import Foundation
import os

/// Manages BLE connections using an explicit state machine.
///
/// All CoreBluetooth operations are modeled as state transitions. Each state
/// owns its resources (continuations, timeouts), ensuring proper cleanup
/// on any transition.
public actor BLEStateMachine {

    // MARK: - Logging

    private let logger = Logger(subsystem: "com.pocketmesh", category: "BLEStateMachine")

    // MARK: - State

    private var phase: BLEPhase = .idle

    /// Expose current phase for testing
    public var currentPhase: BLEPhase { phase }

    // MARK: - CoreBluetooth

    private nonisolated(unsafe) var centralManager: CBCentralManager!
    private let delegateHandler: BLEDelegateHandler

    // MARK: - Configuration

    private let stateRestorationID = "com.pocketmesh.ble.central"
    private let connectionTimeout: TimeInterval
    private let serviceDiscoveryTimeout: TimeInterval
    private let writeTimeout: TimeInterval

    // MARK: - UUIDs

    private let nordicUARTServiceUUID = CBUUID(string: BLEServiceUUID.nordicUART)
    private let txCharacteristicUUID = CBUUID(string: BLEServiceUUID.txCharacteristic)
    private let rxCharacteristicUUID = CBUUID(string: BLEServiceUUID.rxCharacteristic)

    // MARK: - State Restoration

    private var pendingRestoredPeripheral: CBPeripheral?

    /// Pending write continuation (only one write at a time)
    private var pendingWriteContinuation: CheckedContinuation<Void, Error>?

    /// Queue of tasks waiting to write (serializes concurrent sends)
    private var writeWaiters: [CheckedContinuation<Void, Never>] = []

    // MARK: - Callbacks

    private var onDisconnection: (@Sendable (UUID, Error?) -> Void)?
    private var onReconnection: (@Sendable (UUID, AsyncStream<Data>) -> Void)?
    private var onBluetoothStateChange: (@Sendable (CBManagerState) -> Void)?
    private var onBluetoothPoweredOn: (@Sendable () -> Void)?

    // MARK: - Initialization

    /// Creates a new BLE state machine.
    ///
    /// - Parameters:
    ///   - connectionTimeout: Timeout for initial connection (default 10s)
    ///   - serviceDiscoveryTimeout: Timeout for service/characteristic discovery (default 40s for pairing dialog)
    ///   - writeTimeout: Timeout for write operations (default 5s)
    public init(
        connectionTimeout: TimeInterval = 10.0,
        serviceDiscoveryTimeout: TimeInterval = 40.0,
        writeTimeout: TimeInterval = 5.0
    ) {
        self.connectionTimeout = connectionTimeout
        self.serviceDiscoveryTimeout = serviceDiscoveryTimeout
        self.writeTimeout = writeTimeout
        self.delegateHandler = BLEDelegateHandler()

        // Initialize CBCentralManager after actor init
        Task { await self.initializeCentralManager() }
    }

    private func initializeCentralManager() {
        let options: [String: Any] = [
            CBCentralManagerOptionRestoreIdentifierKey: stateRestorationID,
            CBCentralManagerOptionShowPowerAlertKey: true
        ]
        self.centralManager = CBCentralManager(
            delegate: delegateHandler,
            queue: .main,
            options: options
        )
        delegateHandler.stateMachine = self
    }

    // MARK: - Public API

    /// Whether the state machine is currently connected to a device
    public var isConnected: Bool {
        if case .connected = phase { return true }
        return false
    }

    /// Whether the state machine is currently handling iOS auto-reconnect
    public var isAutoReconnecting: Bool {
        if case .autoReconnecting = phase { return true }
        return false
    }

    /// UUID of the currently connected device, or nil if not connected
    public var connectedDeviceID: UUID? {
        phase.deviceID
    }

    /// Current Bluetooth hardware state
    public nonisolated var bluetoothState: CBManagerState {
        centralManager?.state ?? .unknown
    }

    // MARK: - Event Handler Registration

    /// Sets a handler for disconnection events
    public func setDisconnectionHandler(_ handler: @escaping @Sendable (UUID, Error?) -> Void) {
        onDisconnection = handler
    }

    /// Sets a handler for reconnection events.
    /// The handler receives the device ID and the data stream for receiving data.
    public func setReconnectionHandler(_ handler: @escaping @Sendable (UUID, AsyncStream<Data>) -> Void) {
        onReconnection = handler
    }

    /// Sets a handler for Bluetooth state changes
    public func setBluetoothStateChangeHandler(_ handler: @escaping @Sendable (CBManagerState) -> Void) {
        onBluetoothStateChange = handler
    }

    /// Sets a handler called when Bluetooth powers on
    public func setBluetoothPoweredOnHandler(_ handler: @escaping @Sendable () -> Void) {
        onBluetoothPoweredOn = handler
    }

    /// Waits for Bluetooth to be powered on.
    ///
    /// - Throws: `BLEError.bluetoothUnavailable` if Bluetooth is not supported
    ///           `BLEError.bluetoothUnauthorized` if access is denied
    ///           `BLEError.bluetoothPoweredOff` if Bluetooth is off and doesn't turn on
    public func waitForPoweredOn() async throws {
        // Already powered on
        if centralManager.state == .poweredOn { return }

        // Unsupported is permanent
        if centralManager.state == .unsupported {
            throw BLEError.bluetoothUnavailable
        }

        // Wait for state change
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            guard case .idle = phase else {
                continuation.resume(throwing: BLEError.connectionFailed("Already in operation"))
                return
            }
            phase = .waitingForBluetooth(continuation: continuation)
        }
    }

    /// Connects to a BLE device and returns a data stream.
    ///
    /// - Parameter deviceID: UUID of the device to connect to
    /// - Returns: AsyncStream of data received from the device
    /// - Throws: BLEError if connection fails
    public func connect(to deviceID: UUID) async throws -> AsyncStream<Data> {
        logger.info("Connect requested for device: \(deviceID)")

        // Ensure we're in idle state
        guard case .idle = phase else {
            throw BLEError.connectionFailed("Already in operation: \(phase.name)")
        }

        // Wait for Bluetooth
        try await waitForPoweredOn()

        // Retrieve peripheral
        let peripherals = centralManager.retrievePeripherals(withIdentifiers: [deviceID])
        guard let peripheral = peripherals.first else {
            throw BLEError.deviceNotFound
        }

        // Connect with timeout
        try await connectToPeripheral(peripheral)

        // Discover services
        try await discoverServices(on: peripheral)

        // Create data stream and transition to connected
        let (stream, continuation) = AsyncStream.makeStream(of: Data.self)

        guard case .subscribingToNotifications(_, let tx, let rx, _) = phase else {
            throw BLEError.connectionFailed("Unexpected state after service discovery")
        }

        transition(to: .connected(
            peripheral: peripheral,
            tx: tx,
            rx: rx,
            dataContinuation: continuation
        ))

        logger.info("Connection complete for device: \(deviceID)")
        return stream
    }

    /// Sends data to the connected device.
    ///
    /// This method serializes concurrent calls - if a write is already in progress,
    /// subsequent calls will wait until the previous write completes.
    ///
    /// - Parameter data: Data to send
    /// - Throws: BLEError if not connected or write fails
    public func send(_ data: Data) async throws {
        guard case .connected(let peripheral, let tx, _, _) = phase else {
            throw BLEError.notConnected
        }

        guard peripheral.state == .connected else {
            throw BLEError.notConnected
        }

        // Wait for any pending write to complete (serializes concurrent sends)
        if pendingWriteContinuation != nil {
            await withCheckedContinuation { (waiter: CheckedContinuation<Void, Never>) in
                writeWaiters.append(waiter)
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pendingWriteContinuation = continuation
            peripheral.writeValue(data, for: tx, type: .withResponse)

            // Timeout for write
            Task {
                try? await Task.sleep(for: .seconds(writeTimeout))
                if let pending = self.pendingWriteContinuation {
                    self.pendingWriteContinuation = nil
                    pending.resume(throwing: BLEError.operationTimeout)
                    // Resume next waiter
                    resumeNextWriteWaiter()
                }
            }
        }
    }

    /// Resumes the next task waiting to write, if any.
    private func resumeNextWriteWaiter() {
        if !writeWaiters.isEmpty {
            let waiter = writeWaiters.removeFirst()
            waiter.resume()
        }
    }

    /// Disconnects from the current device.
    public func disconnect() async {
        logger.info("Disconnect requested")

        // Cancel pending write
        if let pending = pendingWriteContinuation {
            pendingWriteContinuation = nil
            pending.resume(throwing: BLEError.notConnected)
        }

        // Resume all write waiters (they'll fail on the .connected check)
        while !writeWaiters.isEmpty {
            writeWaiters.removeFirst().resume()
        }

        // Get peripheral before cancelling
        let peripheral = phase.peripheral

        // Cancel current operation
        cancelCurrentOperation(with: BLEError.notConnected)

        // Disconnect peripheral if connected
        if let peripheral, peripheral.state == .connected || peripheral.state == .connecting {
            phase = .disconnecting(peripheral: peripheral)
            centralManager.cancelPeripheralConnection(peripheral)

            // Wait briefly for disconnection to complete
            try? await Task.sleep(for: .milliseconds(100))
        }

        transition(to: .idle)
        logger.info("Disconnect complete")
    }

    /// Switches to a different device.
    ///
    /// Disconnects from current device (if any) and connects to the new one.
    ///
    /// - Parameter deviceID: UUID of the new device to connect to
    /// - Returns: AsyncStream of data from the new device
    /// - Throws: BLEError if connection fails
    public func switchDevice(to deviceID: UUID) async throws -> AsyncStream<Data> {
        logger.info("Switch device requested: \(deviceID)")

        // Disconnect current device
        await disconnect()

        // Connect to new device
        return try await connect(to: deviceID)
    }

    private func connectToPeripheral(_ peripheral: CBPeripheral) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Create timeout task
            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(connectionTimeout))
                await self.handleConnectionTimeout(for: peripheral)
            }

            phase = .connecting(
                peripheral: peripheral,
                continuation: continuation,
                timeoutTask: timeoutTask
            )

            let options: [String: Any] = [
                CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
                CBConnectPeripheralOptionNotifyOnNotificationKey: true,
                CBConnectPeripheralOptionEnableAutoReconnect: true
            ]
            centralManager.connect(peripheral, options: options)
        }
    }

    private func handleConnectionTimeout(for peripheral: CBPeripheral) {
        guard case .connecting(let expected, let continuation, _) = phase,
              expected.identifier == peripheral.identifier else {
            return  // No longer connecting to this peripheral
        }

        logger.warning("Connection timeout for \(peripheral.identifier)")
        centralManager.cancelPeripheralConnection(peripheral)
        transition(to: .idle)
        continuation.resume(throwing: BLEError.connectionTimeout)
    }
}

// MARK: - Delegate Handler

/// Bridges CoreBluetooth delegate callbacks to the actor.
///
/// This class is necessary because actors cannot directly conform to
/// Objective-C delegate protocols. All callbacks dispatch to the actor.
final class BLEDelegateHandler: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {

    weak var stateMachine: BLEStateMachine?

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard let sm = stateMachine else { return }
        Task { await sm.handleCentralManagerDidUpdateState(central.state) }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard let sm = stateMachine else { return }
        // Extract peripheral synchronously before crossing actor boundary
        guard let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
              let peripheral = peripherals.first else {
            return
        }
        Task { await sm.handleWillRestoreState(peripheral) }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        guard let sm = stateMachine else { return }
        Task { await sm.handleDidConnect(peripheral) }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        guard let sm = stateMachine else { return }
        Task { await sm.handleDidFailToConnect(peripheral, error: error) }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        timestamp: CFAbsoluteTime,
        isReconnecting: Bool,
        error: Error?
    ) {
        guard let sm = stateMachine else { return }
        Task { await sm.handleDidDisconnect(peripheral, isReconnecting: isReconnecting, error: error) }
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let sm = stateMachine else { return }
        Task { await sm.handleDidDiscoverServices(peripheral, error: error) }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let sm = stateMachine else { return }
        Task { await sm.handleDidDiscoverCharacteristics(peripheral, service: service, error: error) }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        guard let sm = stateMachine else { return }
        Task { await sm.handleDidUpdateNotificationState(peripheral, characteristic: characteristic, error: error) }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let sm = stateMachine else { return }
        Task { await sm.handleDidUpdateValue(peripheral, characteristic: characteristic, error: error) }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let sm = stateMachine else { return }
        Task { await sm.handleDidWriteValue(peripheral, characteristic: characteristic, error: error) }
    }
}

// MARK: - Internal Callback Handlers (stubs for now)

extension BLEStateMachine {

    func handleCentralManagerDidUpdateState(_ state: CBManagerState) {
        logger.debug("Central manager state: \(String(describing: state))")
        onBluetoothStateChange?(state)

        switch state {
        case .poweredOn:
            // Resume waiting continuation if any
            if case .waitingForBluetooth(let continuation) = phase {
                transition(to: .idle)
                continuation.resume()
            }

            // Handle state restoration
            if let peripheral = pendingRestoredPeripheral {
                pendingRestoredPeripheral = nil
                handleRestoredPeripheral(peripheral)
            }

            // Notify handler for power-on events
            onBluetoothPoweredOn?()

        case .poweredOff:
            // Cancel any operation and notify
            let deviceID = phase.deviceID
            cancelCurrentOperation(with: BLEError.bluetoothPoweredOff)
            if let deviceID {
                onDisconnection?(deviceID, nil)
            }

        case .unauthorized:
            if case .waitingForBluetooth(let continuation) = phase {
                transition(to: .idle)
                continuation.resume(throwing: BLEError.bluetoothUnauthorized)
            }

        case .unsupported:
            if case .waitingForBluetooth(let continuation) = phase {
                transition(to: .idle)
                continuation.resume(throwing: BLEError.bluetoothUnavailable)
            }

        default:
            break
        }
    }

    private func handleRestoredPeripheral(_ peripheral: CBPeripheral) {
        logger.info("Processing restored peripheral: \(peripheral.identifier), state: \(peripheral.state.rawValue)")

        peripheral.delegate = delegateHandler

        if peripheral.state == .connected {
            // Already connected, just need to rediscover services
            phase = .autoReconnecting(peripheral: peripheral, tx: nil, rx: nil)
            peripheral.discoverServices([nordicUARTServiceUUID])
        } else if peripheral.state == .connecting {
            // Connection in progress, wait for didConnect
            phase = .autoReconnecting(peripheral: peripheral, tx: nil, rx: nil)
        } else {
            // Not connected, try to reconnect
            let options: [String: Any] = [
                CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
                CBConnectPeripheralOptionEnableAutoReconnect: true
            ]
            phase = .autoReconnecting(peripheral: peripheral, tx: nil, rx: nil)
            centralManager.connect(peripheral, options: options)
        }
    }

    func handleWillRestoreState(_ peripheral: CBPeripheral) {
        logger.info("State restoration callback received")
        logger.info("State restoration: found peripheral \(peripheral.identifier)")
        pendingRestoredPeripheral = peripheral
    }

    func handleDidConnect(_ peripheral: CBPeripheral) {
        logger.info("Did connect: \(peripheral.identifier)")

        // Handle auto-reconnect
        if case .autoReconnecting(let expected, _, _) = phase,
           peripheral.identifier == expected.identifier {
            logger.info("Auto-reconnect: peripheral connected, discovering services")
            peripheral.delegate = delegateHandler
            peripheral.discoverServices([nordicUARTServiceUUID])
            return
        }

        // Normal connection flow
        guard case .connecting(let expected, let continuation, let timeoutTask) = phase,
              expected.identifier == peripheral.identifier else {
            logger.warning("Unexpected didConnect for \(peripheral.identifier)")
            cancelUnexpectedPeripheral(peripheral)
            return
        }

        timeoutTask.cancel()

        phase = .discoveringServices(
            peripheral: peripheral,
            continuation: continuation
        )

        peripheral.delegate = delegateHandler
        peripheral.discoverServices([nordicUARTServiceUUID])
    }

    func handleDidFailToConnect(_ peripheral: CBPeripheral, error: Error?) {
        logger.warning("Did fail to connect: \(peripheral.identifier), error: \(error?.localizedDescription ?? "nil")")

        guard case .connecting(let expected, let continuation, let timeoutTask) = phase,
              expected.identifier == peripheral.identifier else {
            return  // Not our peripheral
        }

        timeoutTask.cancel()
        transition(to: .idle)
        continuation.resume(throwing: BLEError.connectionFailed(error?.localizedDescription ?? "Unknown error"))
    }

    func handleDidDisconnect(_ peripheral: CBPeripheral, isReconnecting: Bool, error: Error?) {
        logger.info("Did disconnect: \(peripheral.identifier), isReconnecting: \(isReconnecting)")

        let deviceID = peripheral.identifier

        // If iOS is auto-reconnecting, track that
        if isReconnecting {
            logger.info("iOS auto-reconnecting to \(deviceID)")

            // Clean up current state but preserve peripheral for reconnection
            if case .connected(_, _, _, let dataContinuation) = phase {
                dataContinuation.finish()
            }

            phase = .autoReconnecting(peripheral: peripheral, tx: nil, rx: nil)
            return
        }

        // Full disconnection
        switch phase {
        case .disconnecting:
            // Expected disconnection, transition handled by disconnect()
            break

        case .connected, .autoReconnecting:
            // Unexpected disconnection
            cancelCurrentOperation(with: BLEError.notConnected)
            onDisconnection?(deviceID, error)

        default:
            // Disconnection during connection attempt
            cancelCurrentOperation(with: BLEError.connectionFailed("Disconnected during setup"))
        }
    }

    func handleDidDiscoverServices(_ peripheral: CBPeripheral, error: Error?) {
        logger.debug("Did discover services for \(peripheral.identifier)")

        // Handle auto-reconnect
        if case .autoReconnecting(let expected, _, _) = phase,
           peripheral.identifier == expected.identifier {
            if let error {
                logger.warning("Auto-reconnect service discovery failed: \(error.localizedDescription)")
                transition(to: .idle)
                onDisconnection?(expected.identifier, error)
                return
            }

            guard let service = peripheral.services?.first(where: { $0.uuid == nordicUARTServiceUUID }) else {
                logger.warning("Auto-reconnect: service not found")
                transition(to: .idle)
                onDisconnection?(expected.identifier, nil)
                return
            }

            peripheral.discoverCharacteristics([txCharacteristicUUID, rxCharacteristicUUID], for: service)
            return
        }

        // Normal flow
        guard case .discoveringServices(let expected, let continuation) = phase,
              expected.identifier == peripheral.identifier else {
            logger.warning("Unexpected didDiscoverServices")
            return
        }

        if let error {
            transition(to: .idle)
            continuation.resume(throwing: BLEError.connectionFailed(error.localizedDescription))
            return
        }

        guard let service = peripheral.services?.first(where: { $0.uuid == nordicUARTServiceUUID }) else {
            transition(to: .idle)
            continuation.resume(throwing: BLEError.characteristicNotFound)
            return
        }

        phase = .discoveringCharacteristics(
            peripheral: peripheral,
            service: service,
            continuation: continuation
        )

        peripheral.discoverCharacteristics([txCharacteristicUUID, rxCharacteristicUUID], for: service)
    }

    func handleDidDiscoverCharacteristics(_ peripheral: CBPeripheral, service: CBService, error: Error?) {
        logger.debug("Did discover characteristics for \(peripheral.identifier)")

        // Handle auto-reconnect
        if case .autoReconnecting(let expected, _, _) = phase,
           peripheral.identifier == expected.identifier {
            if let error {
                logger.warning("Auto-reconnect characteristic discovery failed: \(error.localizedDescription)")
                transition(to: .idle)
                onDisconnection?(expected.identifier, error)
                return
            }

            guard let characteristics = service.characteristics,
                  let tx = characteristics.first(where: { $0.uuid == txCharacteristicUUID }),
                  let rx = characteristics.first(where: { $0.uuid == rxCharacteristicUUID }) else {
                logger.warning("Auto-reconnect: characteristics not found")
                transition(to: .idle)
                onDisconnection?(expected.identifier, nil)
                return
            }

            // Store tx/rx in phase for use when notification subscription completes
            phase = .autoReconnecting(peripheral: peripheral, tx: tx, rx: rx)

            // Subscribe to notifications to complete reconnection
            peripheral.setNotifyValue(true, for: rx)
            return
        }

        // Normal flow
        guard case .discoveringCharacteristics(let expected, let expectedService, let continuation) = phase,
              expected.identifier == peripheral.identifier,
              expectedService.uuid == service.uuid else {
            logger.warning("Unexpected didDiscoverCharacteristics")
            return
        }

        if let error {
            transition(to: .idle)
            continuation.resume(throwing: BLEError.connectionFailed(error.localizedDescription))
            return
        }

        guard let characteristics = service.characteristics,
              let tx = characteristics.first(where: { $0.uuid == txCharacteristicUUID }),
              let rx = characteristics.first(where: { $0.uuid == rxCharacteristicUUID }) else {
            transition(to: .idle)
            continuation.resume(throwing: BLEError.characteristicNotFound)
            return
        }

        phase = .subscribingToNotifications(
            peripheral: peripheral,
            tx: tx,
            rx: rx,
            continuation: continuation
        )

        peripheral.setNotifyValue(true, for: rx)
    }

    func handleDidUpdateNotificationState(_ peripheral: CBPeripheral, characteristic: CBCharacteristic, error: Error?) {
        logger.debug("Did update notification state for \(peripheral.identifier)")

        guard case .subscribingToNotifications(let expected, _, _, let continuation) = phase,
              expected.identifier == peripheral.identifier,
              characteristic.uuid == rxCharacteristicUUID else {
            // Could be auto-reconnect scenario - handle separately
            handleReconnectionNotificationState(peripheral, characteristic: characteristic, error: error)
            return
        }

        if let error {
            transition(to: .idle)
            continuation.resume(throwing: BLEError.connectionFailed(error.localizedDescription))
            return
        }

        // Success! Resume continuation - connect() will complete the transition
        continuation.resume()
    }

    private func handleReconnectionNotificationState(_ peripheral: CBPeripheral, characteristic: CBCharacteristic, error: Error?) {
        // Handle auto-reconnect notification subscription completion
        guard case .autoReconnecting(let expected, let tx, let rx) = phase,
              peripheral.identifier == expected.identifier else {
            return
        }

        if let error {
            logger.warning("Auto-reconnect notification subscription failed: \(error.localizedDescription)")
            transition(to: .idle)
            onDisconnection?(peripheral.identifier, error)
            return
        }

        guard let tx, let rx else {
            logger.error("Auto-reconnect: tx/rx characteristics missing from phase")
            transition(to: .idle)
            onDisconnection?(peripheral.identifier, nil)
            return
        }

        logger.info("Auto-reconnect notification subscription complete")

        // Create data stream and transition to connected
        let (stream, continuation) = AsyncStream.makeStream(of: Data.self)

        transition(to: .connected(
            peripheral: peripheral,
            tx: tx,
            rx: rx,
            dataContinuation: continuation
        ))

        logger.info("iOS auto-reconnect complete for \(peripheral.identifier)")
        onReconnection?(peripheral.identifier, stream)
    }

    func handleDidUpdateValue(_ peripheral: CBPeripheral, characteristic: CBCharacteristic, error: Error?) {
        guard error == nil,
              let data = characteristic.value,
              !data.isEmpty else {
            return
        }

        guard case .connected(_, _, _, let dataContinuation) = phase else {
            return  // Not connected, ignore data
        }

        dataContinuation.yield(data)
    }

    func handleDidWriteValue(_ peripheral: CBPeripheral, characteristic: CBCharacteristic, error: Error?) {
        logger.debug("Did write value for \(peripheral.identifier)")

        guard let continuation = pendingWriteContinuation else {
            return  // No pending write
        }

        pendingWriteContinuation = nil

        if let error {
            continuation.resume(throwing: BLEError.writeError(error.localizedDescription))
        } else {
            continuation.resume()
        }

        // Resume next task waiting to write
        resumeNextWriteWaiter()
    }
}

// MARK: - State Transitions

extension BLEStateMachine {

    /// Transitions to a new phase, cleaning up the old phase's resources.
    ///
    /// - Parameter newPhase: The phase to transition to
    /// - Returns: The previous phase (for logging/debugging)
    @discardableResult
    private func transition(to newPhase: BLEPhase) -> BLEPhase {
        let oldPhase = phase
        logger.debug("Transition: \(oldPhase.name) → \(newPhase.name)")

        // Clean up old phase resources (except continuations - caller handles those)
        cleanupPhaseResources(oldPhase)

        phase = newPhase
        return oldPhase
    }

    /// Cleans up non-continuation resources owned by a phase.
    private func cleanupPhaseResources(_ phase: BLEPhase) {
        switch phase {
        case .connecting(_, _, let timeoutTask):
            timeoutTask.cancel()

        case .connected(_, _, _, let dataContinuation):
            dataContinuation.finish()

        default:
            break
        }
    }

    /// Cancels the current operation, resuming any pending continuation with an error.
    ///
    /// - Parameter error: The error to resume continuations with
    func cancelCurrentOperation(with error: Error) {
        switch phase {
        case .waitingForBluetooth(let continuation):
            continuation.resume(throwing: error)

        case .connecting(_, let continuation, let timeoutTask):
            timeoutTask.cancel()
            continuation.resume(throwing: error)

        case .discoveringServices(_, let continuation):
            continuation.resume(throwing: error)

        case .discoveringCharacteristics(_, _, let continuation):
            continuation.resume(throwing: error)

        case .subscribingToNotifications(_, _, _, let continuation):
            continuation.resume(throwing: error)

        case .connected(_, _, _, let dataContinuation):
            dataContinuation.finish()

        case .idle, .autoReconnecting, .disconnecting:
            break
        }

        transition(to: .idle)
    }

    /// Cancels connection to a peripheral if we're not expecting it.
    private func cancelUnexpectedPeripheral(_ peripheral: CBPeripheral) {
        logger.warning("Cancelling unexpected peripheral: \(peripheral.identifier)")
        centralManager.cancelPeripheralConnection(peripheral)
    }

    private func discoverServices(on peripheral: CBPeripheral) async throws {
        // The discovery flow is already initiated in handleDidConnect
        // We need to wait for the full chain: services -> characteristics -> notifications
        // The continuation is passed through each phase until notification subscription completes

        // Note: The continuation is already stored in phase from connectToPeripheral
        // handleDidConnect starts service discovery and passes continuation through phases
        // This method just needs to ensure we're in the right state when called

        // Wait for notification subscription to complete (signals full discovery done)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Store continuation for the discovery timeout
            // The actual discovery is driven by delegate callbacks
            guard case .discoveringServices(let p, _) = phase, p.identifier == peripheral.identifier else {
                // If not in expected state, the connect flow handles this
                continuation.resume()
                return
            }

            // Replace the continuation in the current phase
            phase = .discoveringServices(peripheral: peripheral, continuation: continuation)

            // Start timeout for entire discovery process
            Task {
                try? await Task.sleep(for: .seconds(serviceDiscoveryTimeout))
                self.handleServiceDiscoveryTimeout(for: peripheral)
            }
        }
    }

    private func handleServiceDiscoveryTimeout(for peripheral: CBPeripheral) {
        switch phase {
        case .discoveringServices(let p, let c),
             .discoveringCharacteristics(let p, _, let c),
             .subscribingToNotifications(let p, _, _, let c):
            guard p.identifier == peripheral.identifier else { return }
            logger.warning("Service discovery timeout for \(peripheral.identifier)")
            centralManager.cancelPeripheralConnection(peripheral)
            transition(to: .idle)
            c.resume(throwing: BLEError.connectionTimeout)
        default:
            break
        }
    }
}
