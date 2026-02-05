// BLEStateMachine.swift
@preconcurrency import CoreBluetooth
import Dispatch
import Foundation
import os

/// Manages BLE connections using an explicit state machine.
///
/// All CoreBluetooth operations are modeled as state transitions. Each state
/// owns its resources (continuations, timeouts), ensuring proper cleanup
/// on any transition.
public actor BLEStateMachine: BLEStateMachineProtocol {

    // MARK: - Logging

    private let logger = PersistentLogger(subsystem: "com.pocketmesh", category: "BLEStateMachine")
    private let instanceID = String(UUID().uuidString.prefix(8))
    private var lastCentralState: CBManagerState?

    private nonisolated var processContext: String {
        let processName = ProcessInfo.processInfo.processName
        let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
        return "process: \(processName), bundle: \(bundleID)"
    }

    /// Converts CBPeripheralState to readable string for diagnostics
    private nonisolated func peripheralStateString(_ state: CBPeripheralState) -> String {
        switch state {
        case .disconnected: return "disconnected"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .disconnecting: return "disconnecting"
        @unknown default: return "unknown(\(state.rawValue))"
        }
    }

    // MARK: - State

    private var phase: BLEPhase = .idle

    /// Tracks when the current phase started (for timing diagnostics)
    private var phaseStartTime: Date = Date()

    /// Expose current phase for testing
    public var currentPhase: BLEPhase { phase }

    // MARK: - CoreBluetooth

    /// The central manager instance.
    ///
    /// Marked `nonisolated(unsafe)` because:
    /// 1. CBCentralManager is not Sendable
    /// 2. We need nonisolated access from `bluetoothState` property
    /// 3. The manager is only mutated once during initialization
    /// 4. All other access is from the actor's isolated context
    /// 5. The `bluetoothState` property returns `.unknown` during the brief
    ///    initialization window before the manager is assigned
    private nonisolated(unsafe) var centralManager: CBCentralManager!
    private let delegateHandler: BLEDelegateHandler

    // MARK: - Configuration

    private let stateRestorationID = "com.pocketmesh.ble.central"
    private let connectionTimeout: TimeInterval
    private let serviceDiscoveryTimeout: TimeInterval
    private let autoReconnectDiscoveryTimeout: TimeInterval
    private let writeTimeout: TimeInterval

    /// Delay between write operations for ESP32 compatibility (0 = no pacing)
    private var writePacingDelay: TimeInterval = 0

    /// Tracks consecutive queued writes for diagnostic logging
    private var consecutiveQueuedWrites = 0
    private let queuePressureThreshold = 3

    // MARK: - UUIDs

    private let nordicUARTServiceUUID = CBUUID(string: BLEServiceUUID.nordicUART)
    private let txCharacteristicUUID = CBUUID(string: BLEServiceUUID.txCharacteristic)
    private let rxCharacteristicUUID = CBUUID(string: BLEServiceUUID.rxCharacteristic)

    /// Pending write continuation (only one write at a time)
    private var pendingWriteContinuation: CheckedContinuation<Void, Error>?

    /// Queue of tasks waiting to write (serializes concurrent sends)
    private var writeWaiters: [CheckedContinuation<Void, Never>] = []

    /// Tracks the current write timeout task so it can be cancelled when write completes
    private var writeTimeoutTask: Task<Void, Never>?

    /// Tracks the service discovery timeout task so it can be cancelled on success
    private var serviceDiscoveryTimeoutTask: Task<Void, Never>?

    /// Tracks the auto-reconnect discovery timeout task so it can be cancelled on success
    private var autoReconnectDiscoveryTimeoutTask: Task<Void, Never>?

    /// Tracks whether CBCentralManager has been created
    private var isActivated = false

    // MARK: - Callbacks

    private var onDisconnection: (@Sendable (UUID, Error?) -> Void)?
    private var onReconnection: (@Sendable (UUID, AsyncStream<Data>) -> Void)?
    private var onBluetoothStateChange: (@Sendable (CBManagerState) -> Void)?
    private var onBluetoothPoweredOn: (@Sendable () -> Void)?
    /// Called when entering iOS auto-reconnecting phase.
    /// The device has disconnected but iOS will attempt automatic reconnection.
    /// Note: The MeshCore session is invalid at this point and will be rebuilt upon successful reconnection.
    private var onAutoReconnecting: (@Sendable (UUID) -> Void)?

    // MARK: - Initialization

    /// Creates a new BLE state machine.
    ///
    /// - Parameters:
    ///   - connectionTimeout: Timeout for initial connection (default 10s)
    ///   - serviceDiscoveryTimeout: Timeout for service/characteristic discovery (default 40s for pairing dialog)
    ///   - autoReconnectDiscoveryTimeout: Timeout for auto-reconnect discovery (default 15s, shorter since no pairing expected)
    ///   - writeTimeout: Timeout for write operations (default 5s)
    ///   - writePacingDelay: Delay between write operations for ESP32 compatibility (default 0 = no pacing)
    public init(
        connectionTimeout: TimeInterval = 10.0,
        serviceDiscoveryTimeout: TimeInterval = 40.0,
        autoReconnectDiscoveryTimeout: TimeInterval = 15.0,
        writeTimeout: TimeInterval = 5.0,
        writePacingDelay: TimeInterval = 0
    ) {
        self.connectionTimeout = connectionTimeout
        self.serviceDiscoveryTimeout = serviceDiscoveryTimeout
        self.autoReconnectDiscoveryTimeout = autoReconnectDiscoveryTimeout
        self.writeTimeout = writeTimeout
        self.writePacingDelay = writePacingDelay
        self.delegateHandler = BLEDelegateHandler()
    }

    /// Sets the write pacing delay for ESP32 compatibility.
    /// - Parameter delay: Delay in seconds between write operations (0 = no pacing)
    public func setWritePacingDelay(_ delay: TimeInterval) {
        writePacingDelay = delay
    }

    /// Activates the BLE state machine, creating the CBCentralManager.
    /// Call once during app initialization. Safe to call multiple times.
    public func activate() {
        guard !isActivated else { return }
        isActivated = true
        logger.info("[BLE] Activating state machine, instance: \(instanceID), \(processContext)")
        initializeCentralManager()
    }

    private let centralQueue = DispatchQueue(label: "com.pocketmesh.ble.central")

    private func initializeCentralManager() {
        // Set stateMachine reference BEFORE creating CBCentralManager.
        // iOS calls willRestoreState during or immediately after CBCentralManager.init(),
        // and the delegate handler needs the stateMachine reference to process it.
        delegateHandler.stateMachine = self

        logger.info("[BLE] Initializing central manager, instance: \(instanceID), \(processContext)")
        let options: [String: Any] = [
            CBCentralManagerOptionRestoreIdentifierKey: stateRestorationID,
            CBCentralManagerOptionShowPowerAlertKey: true
        ]
        self.centralManager = CBCentralManager(
            delegate: delegateHandler,
            queue: centralQueue,
            options: options
        )
    }

    // MARK: - Public API

    /// Whether the state machine is currently connected to a device
    public var isConnected: Bool {
        if case .connected = phase { return true }
        return false
    }

    /// Whether the state machine is currently handling iOS auto-reconnect or state restoration
    public var isAutoReconnecting: Bool {
        switch phase {
        case .autoReconnecting, .restoringState:
            return true
        default:
            return false
        }
    }

    /// UUID of the currently connected device, or nil if not connected
    public var connectedDeviceID: UUID? {
        phase.deviceID
    }

    /// Current Bluetooth hardware state
    public nonisolated var bluetoothState: CBManagerState {
        centralManager?.state ?? .unknown
    }

    /// Current phase name for diagnostic logging
    public var currentPhaseName: String {
        phase.name
    }

    /// Current peripheral state for diagnostic logging (nil if no peripheral)
    public var currentPeripheralState: String? {
        guard let peripheral = phase.peripheral else { return nil }
        return peripheralStateString(peripheral.state)
    }

    /// Current CBCentralManager state name for diagnostic logging
    public var centralManagerStateName: String {
        guard let manager = centralManager else { return "notActivated" }
        switch manager.state {
        case .unknown: return "unknown"
        case .resetting: return "resetting"
        case .unsupported: return "unsupported"
        case .unauthorized: return "unauthorized"
        case .poweredOff: return "poweredOff"
        case .poweredOn: return "poweredOn"
        @unknown default: return "unknown(\(manager.state.rawValue))"
        }
    }

    /// Checks if a device is connected to the system (possibly by another app).
    /// Call this BEFORE attempting connection when in `.idle` phase.
    /// - Parameter deviceID: The UUID of the device to check
    /// - Returns: `true` if the device is connected to the system
    public func isDeviceConnectedToSystem(_ deviceID: UUID) -> Bool {
        activate()
        let connectedPeripherals = centralManager.retrieveConnectedPeripherals(
            withServices: [nordicUARTServiceUUID]
        )
        return connectedPeripherals.contains { $0.identifier == deviceID }
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

    /// Sets a handler for auto-reconnecting events.
    /// Called when device disconnects but iOS is attempting automatic reconnection.
    public func setAutoReconnectingHandler(_ handler: @escaping @Sendable (UUID) -> Void) {
        onAutoReconnecting = handler
    }

    /// Waits for Bluetooth to be powered on.
    ///
    /// - Throws: `BLEError.bluetoothUnavailable` if Bluetooth is not supported
    ///           `BLEError.bluetoothUnauthorized` if access is denied
    ///           `BLEError.bluetoothPoweredOff` if Bluetooth is off and doesn't turn on
    public func waitForPoweredOn() async throws {
        activate()

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
            // Diagnostic: Log detailed state when connection is rejected
            let peripheralState = phase.peripheral.map { peripheralStateString($0.state) } ?? "none"
            let phaseDeviceID = phase.deviceID?.uuidString ?? "none"
            logger.warning(
                "Connect rejected - phase: \(self.phase.name), peripheralState: \(peripheralState), phaseDeviceID: \(phaseDeviceID), requestedDeviceID: \(deviceID)"
            )
            throw BLEError.connectionFailed("Already in operation: \(phase.name)")
        }

        // Wait for Bluetooth
        try await waitForPoweredOn()

        // Retrieve peripheral
        let peripherals = centralManager.retrievePeripherals(withIdentifiers: [deviceID])
        guard let peripheral = peripherals.first else {
            throw BLEError.deviceNotFound
        }

        // Connect and discover services (continuation spans entire discovery chain)
        try await connectToPeripheral(peripheral)

        // Create data stream and transition to connected
        let (stream, continuation) = AsyncStream.makeStream(
            of: Data.self,
            bufferingPolicy: .bufferingOldest(512)
        )

        guard case .subscribingToNotifications(_, let tx, let rx, _) = phase else {
            throw BLEError.connectionFailed("Unexpected state after service discovery")
        }

        // Pass continuation to delegate handler for direct yielding (preserves ordering)
        delegateHandler.setDataContinuation(continuation)

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
            consecutiveQueuedWrites += 1
            let queueDepth = writeWaiters.count + 1
            if consecutiveQueuedWrites >= queuePressureThreshold {
                logger.warning("[BLE] Write queue pressure: depth=\(queueDepth), consecutive=\(consecutiveQueuedWrites)")
            } else {
                logger.debug("[BLE] Write queued, depth: \(queueDepth)")
            }
            await withCheckedContinuation { (waiter: CheckedContinuation<Void, Never>) in
                writeWaiters.append(waiter)
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            pendingWriteContinuation = continuation
            peripheral.writeValue(data, for: tx, type: .withResponse)

            // Cancel any previous timeout task and create a new one
            writeTimeoutTask?.cancel()
            writeTimeoutTask = Task {
                try? await Task.sleep(for: .seconds(writeTimeout))
                guard !Task.isCancelled else { return }
                if let pending = self.pendingWriteContinuation {
                    self.pendingWriteContinuation = nil
                    self.consecutiveQueuedWrites = 0
                    pending.resume(throwing: BLEError.operationTimeout)
                    self.writeTimeoutTask = nil
                    self.resumeNextWriteWaiter()
                }
            }
        }
    }

    /// Resumes the next task waiting to write after applying pacing delay.
    /// - Parameter applyPacing: Whether to apply write pacing delay (default true)
    private func resumeNextWriteWaiter(applyPacing: Bool = true) {
        guard !writeWaiters.isEmpty else { return }

        let waiter = writeWaiters.removeFirst()

        if applyPacing && writePacingDelay > 0 {
            Task { [writePacingDelay] in
                try? await Task.sleep(for: .seconds(writePacingDelay))
                // Always resume the waiter, even if the state machine was deallocated.
                // The waiter will check connection state and fail appropriately.
                waiter.resume()
            }
        } else {
            waiter.resume()
        }
    }

    /// Disconnects from the current device.
    public func disconnect() async {
        logger.info("Disconnect requested")

        // Cancel write timeout task
        writeTimeoutTask?.cancel()
        writeTimeoutTask = nil

        // Reset queue tracking
        consecutiveQueuedWrites = 0

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
        let pState = peripheralStateString(peripheral.state)
        logger.info("[BLE] Connecting to peripheral: \(peripheral.identifier.uuidString.prefix(8)), currentState: \(pState), timeout: \(self.connectionTimeout)s, autoReconnect: enabled")

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

        let pState = peripheralStateString(peripheral.state)
        let elapsed = Date().timeIntervalSince(phaseStartTime)
        logger.warning("[BLE] Connection timeout: \(peripheral.identifier.uuidString.prefix(8)), peripheralState: \(pState), elapsed: \(String(format: "%.2f", elapsed))s")
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
///
/// For data reception (`didUpdateValueFor`), data is yielded directly to an AsyncStream
/// continuation rather than spawning Tasks. This preserves the ordering guaranteed by
/// the serial CBCentralManager queue, avoiding the race conditions that occur when
/// multiple unstructured Tasks compete for actor access with priority-based scheduling.
final class BLEDelegateHandler: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {

    weak var stateMachine: BLEStateMachine?

    private let logger = PersistentLogger(subsystem: "com.pocketmesh", category: "BLEDelegateHandler")

    /// Lock-protected continuation for yielding received data directly.
    /// Using OSAllocatedUnfairLock ensures thread-safe access from the CBCentralManager queue.
    private let dataContinuationLock = OSAllocatedUnfairLock<AsyncStream<Data>.Continuation?>(initialState: nil)

    /// Sets the data continuation for direct yielding from delegate callbacks.
    /// Call this when transitioning to connected state.
    func setDataContinuation(_ continuation: AsyncStream<Data>.Continuation?) {
        dataContinuationLock.withLock { $0 = continuation }
    }

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
        // Yield data directly to preserve ordering from the serial CBCentralManager queue.
        // Do NOT spawn a Task here - that breaks ordering guarantees.
        if let error {
            logger.warning("[BLE] didUpdateValueFor error: \(peripheral.identifier.uuidString.prefix(8)), char: \(characteristic.uuid.uuidString.prefix(8)), error: \(error.localizedDescription)")
            return
        }
        guard let data = characteristic.value, !data.isEmpty else {
            logger.debug("[BLE] didUpdateValueFor: empty data from \(peripheral.identifier.uuidString.prefix(8)), char: \(characteristic.uuid.uuidString.prefix(8))")
            return
        }
        _ = dataContinuationLock.withLock { $0?.yield(data) }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        guard let sm = stateMachine else { return }
        Task { await sm.handleDidWriteValue(peripheral, characteristic: characteristic, error: error) }
    }
}

// MARK: - Internal Callback Handlers (stubs for now)

extension BLEStateMachine {

    func handleCentralManagerDidUpdateState(_ state: CBManagerState) {
        let stateString: String
        switch state {
        case .unknown: stateString = "unknown"
        case .resetting: stateString = "resetting"
        case .unsupported: stateString = "unsupported"
        case .unauthorized: stateString = "unauthorized"
        case .poweredOff: stateString = "poweredOff"
        case .poweredOn: stateString = "poweredOn"
        @unknown default: stateString = "unknown(\(state.rawValue))"
        }
        if lastCentralState != state {
            lastCentralState = state
            logger.info(
                "[BLE] Central manager state changed: \(stateString), currentPhase: \(self.phase.name), instance: \(instanceID), \(processContext)"
            )
        }
        onBluetoothStateChange?(state)

        switch state {
        case .poweredOn:
            // Resume waiting continuation if any
            if case .waitingForBluetooth(let continuation) = phase {
                transition(to: .idle)
                continuation.resume()
            }

            // Handle state restoration from phase
            if case .restoringState(let peripheral) = phase {
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
            // Handle restoration failure
            if case .restoringState(let peripheral) = phase {
                transition(to: .idle)
                onDisconnection?(peripheral.identifier, nil)
            }

        case .unsupported:
            if case .waitingForBluetooth(let continuation) = phase {
                transition(to: .idle)
                continuation.resume(throwing: BLEError.bluetoothUnavailable)
            }
            // Handle restoration failure
            if case .restoringState(let peripheral) = phase {
                transition(to: .idle)
                onDisconnection?(peripheral.identifier, nil)
            }

        default:
            break
        }
    }

    private func handleRestoredPeripheral(_ peripheral: CBPeripheral) {
        let pState = peripheralStateString(peripheral.state)
        logger.info("[BLE] Processing restored peripheral: \(peripheral.identifier.uuidString.prefix(8)), state: \(pState)")

        peripheral.delegate = delegateHandler

        // Start timeout for auto-reconnect discovery
        autoReconnectDiscoveryTimeoutTask = Task {
            try? await Task.sleep(for: .seconds(autoReconnectDiscoveryTimeout))
            guard !Task.isCancelled else { return }
            await handleAutoReconnectDiscoveryTimeout(for: peripheral)
        }

        transition(to: .autoReconnecting(peripheral: peripheral, tx: nil, rx: nil))

        if peripheral.state == .connected {
            // Already connected, just need to rediscover services
            peripheral.discoverServices([nordicUARTServiceUUID])
        } else if peripheral.state == .connecting {
            // Connection in progress, wait for didConnect
        } else {
            // Not connected, try to reconnect
            let options: [String: Any] = [
                CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
                CBConnectPeripheralOptionEnableAutoReconnect: true
            ]
            centralManager.connect(peripheral, options: options)
        }
    }

    func handleWillRestoreState(_ peripheral: CBPeripheral) {
        let pState = peripheralStateString(peripheral.state)
        logger.info("[BLE] State restoration callback: \(peripheral.identifier.uuidString.prefix(8)), state: \(pState)")

        // If Bluetooth is already powered on, proceed directly to restoration.
        // This handles the edge case where .poweredOn Task runs before this Task.
        if centralManager.state == .poweredOn {
            handleRestoredPeripheral(peripheral)
        } else {
            transition(to: .restoringState(peripheral: peripheral))
        }
    }

    func handleDidConnect(_ peripheral: CBPeripheral) {
        let pState = peripheralStateString(peripheral.state)
        let elapsed = Date().timeIntervalSince(phaseStartTime)
        logger.info("[BLE] Did connect: \(peripheral.identifier.uuidString.prefix(8)), peripheralState: \(pState), phase: \(self.phase.name), elapsed: \(String(format: "%.2f", elapsed))s")

        // Handle auto-reconnect
        if case .autoReconnecting(let expected, _, _) = phase,
           peripheral.identifier == expected.identifier {
            logger.info("[BLE] Auto-reconnect: peripheral connected, discovering services")
            peripheral.delegate = delegateHandler
            peripheral.discoverServices([nordicUARTServiceUUID])

            // Cancel any existing timeout (e.g., from handleRestoredPeripheral) and restart
            autoReconnectDiscoveryTimeoutTask?.cancel()
            autoReconnectDiscoveryTimeoutTask = Task {
                try? await Task.sleep(for: .seconds(autoReconnectDiscoveryTimeout))
                guard !Task.isCancelled else { return }
                await handleAutoReconnectDiscoveryTimeout(for: peripheral)
            }
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

        // Arm discovery timeout before starting discovery so the callback
        // window between discoverServices() and timeout creation is closed.
        serviceDiscoveryTimeoutTask = Task {
            try? await Task.sleep(for: .seconds(serviceDiscoveryTimeout))
            guard !Task.isCancelled else { return }
            await handleServiceDiscoveryTimeout(for: peripheral)
        }

        transition(to: .discoveringServices(
            peripheral: peripheral,
            continuation: continuation
        ))

        peripheral.delegate = delegateHandler
        peripheral.discoverServices([nordicUARTServiceUUID])
    }

    func handleDidFailToConnect(_ peripheral: CBPeripheral, error: Error?) {
        let pState = peripheralStateString(peripheral.state)
        let elapsed = Date().timeIntervalSince(phaseStartTime)
        var errorInfo = "none"
        if let error = error as NSError? {
            errorInfo = "domain=\(error.domain), code=\(error.code), desc=\(error.localizedDescription)"
        }
        logger.warning(
            "[BLE] Did fail to connect: \(peripheral.identifier.uuidString.prefix(8)), peripheralState: \(pState), phase: \(self.phase.name), elapsed: \(String(format: "%.2f", elapsed))s, error: \(errorInfo)"
        )

        // Handle failure during auto-reconnect (iOS auto-reconnect gave up)
        if case .autoReconnecting(let expected, _, _) = phase,
           expected.identifier == peripheral.identifier {
            logger.warning("Auto-reconnect failed for \(peripheral.identifier) - transitioning to idle")
            transition(to: .idle)
            onDisconnection?(peripheral.identifier, error)
            return
        }

        guard case .connecting(let expected, let continuation, let timeoutTask) = phase,
              expected.identifier == peripheral.identifier else {
            logger.info("Ignoring didFailToConnect - not our peripheral or unexpected phase")
            return
        }

        timeoutTask.cancel()
        transition(to: .idle)
        continuation.resume(throwing: BLEError.connectionFailed(error?.localizedDescription ?? "Unknown error"))
    }

    func handleDidDisconnect(_ peripheral: CBPeripheral, isReconnecting: Bool, error: Error?) {
        let pState = peripheralStateString(peripheral.state)
        let elapsed = Date().timeIntervalSince(phaseStartTime)
        var errorInfo = "none"
        if let error = error as NSError? {
            errorInfo = "domain=\(error.domain), code=\(error.code), desc=\(error.localizedDescription)"
        }
        logger.info(
            "[BLE] Did disconnect: \(peripheral.identifier.uuidString.prefix(8)), peripheralState: \(pState), isReconnecting: \(isReconnecting), phase: \(self.phase.name), elapsed: \(String(format: "%.2f", elapsed))s, error: \(errorInfo)"
        )

        let deviceID = peripheral.identifier

        // If iOS is auto-reconnecting, track that
        if isReconnecting {
            logger.info("[BLE] iOS auto-reconnect started: \(deviceID.uuidString.prefix(8)), will attempt automatic reconnection")

            // Clean up current state but preserve peripheral for reconnection.
            // transition() handles dataContinuation cleanup when leaving .connected.
            transition(to: .autoReconnecting(peripheral: peripheral, tx: nil, rx: nil))

            // Notify handler so UI can show "connecting" state
            onAutoReconnecting?(deviceID)
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
        let serviceCount = peripheral.services?.count ?? 0
        let hasNordicUART = peripheral.services?.contains { $0.uuid == nordicUARTServiceUUID } ?? false
        logger.info("[BLE] Did discover services: \(peripheral.identifier.uuidString.prefix(8)), count: \(serviceCount), hasNordicUART: \(hasNordicUART), error: \(error?.localizedDescription ?? "none")")

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

        transition(to: .discoveringCharacteristics(
            peripheral: peripheral,
            service: service,
            continuation: continuation
        ))

        peripheral.discoverCharacteristics([txCharacteristicUUID, rxCharacteristicUUID], for: service)
    }

    func handleDidDiscoverCharacteristics(_ peripheral: CBPeripheral, service: CBService, error: Error?) {
        let characteristics = service.characteristics ?? []
        let hasTX = characteristics.contains { $0.uuid == txCharacteristicUUID }
        let hasRX = characteristics.contains { $0.uuid == rxCharacteristicUUID }
        logger.info("[BLE] Did discover characteristics: \(peripheral.identifier.uuidString.prefix(8)), count: \(characteristics.count), hasTX: \(hasTX), hasRX: \(hasRX), error: \(error?.localizedDescription ?? "none")")

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
            transition(to: .autoReconnecting(peripheral: peripheral, tx: tx, rx: rx))

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

        transition(to: .subscribingToNotifications(
            peripheral: peripheral,
            tx: tx,
            rx: rx,
            continuation: continuation
        ))

        peripheral.setNotifyValue(true, for: rx)
    }

    func handleDidUpdateNotificationState(_ peripheral: CBPeripheral, characteristic: CBCharacteristic, error: Error?) {
        logger.info("[BLE] Did update notification state: \(peripheral.identifier.uuidString.prefix(8)), isNotifying: \(characteristic.isNotifying), charUUID: \(characteristic.uuid.uuidString.prefix(8)), error: \(error?.localizedDescription ?? "none")")

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

        // Cancel the service discovery timeout since we completed successfully
        serviceDiscoveryTimeoutTask?.cancel()
        serviceDiscoveryTimeoutTask = nil

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

        // Cancel the auto-reconnect discovery timeout since we completed successfully
        autoReconnectDiscoveryTimeoutTask?.cancel()
        autoReconnectDiscoveryTimeoutTask = nil

        let elapsed = Date().timeIntervalSince(phaseStartTime)
        logger.info("[BLE] Auto-reconnect notification subscription complete, elapsed: \(String(format: "%.2f", elapsed))s")

        // Create data stream and transition to connected
        let (stream, continuation) = AsyncStream.makeStream(
            of: Data.self,
            bufferingPolicy: .bufferingOldest(512)
        )

        // Pass continuation to delegate handler for direct yielding (preserves ordering)
        delegateHandler.setDataContinuation(continuation)

        transition(to: .connected(
            peripheral: peripheral,
            tx: tx,
            rx: rx,
            dataContinuation: continuation
        ))

        logger.info("[BLE] iOS auto-reconnect complete: \(peripheral.identifier.uuidString.prefix(8))")
        onReconnection?(peripheral.identifier, stream)
    }

    func handleDidWriteValue(_ peripheral: CBPeripheral, characteristic: CBCharacteristic, error: Error?) {
        // Cancel the timeout task since write completed
        writeTimeoutTask?.cancel()
        writeTimeoutTask = nil

        // Reset queue tracking on successful completion
        consecutiveQueuedWrites = 0

        guard let continuation = pendingWriteContinuation else {
            return  // No pending write
        }

        pendingWriteContinuation = nil

        if let error {
            continuation.resume(throwing: BLEError.writeError(error.localizedDescription))
        } else {
            continuation.resume()
        }

        // Resume next task waiting to write (with pacing delay for ESP32 compatibility)
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
        let elapsed = Date().timeIntervalSince(phaseStartTime)
        let deviceID = oldPhase.deviceID?.uuidString.prefix(8) ?? "none"
        logger.info("[BLE] Transition: \(oldPhase.name) → \(newPhase.name), device: \(deviceID), elapsed: \(String(format: "%.2f", elapsed))s")

        // Clean up old phase resources (except continuations - caller handles those)
        cleanupPhaseResources(oldPhase, newPhase: newPhase)

        phase = newPhase
        phaseStartTime = Date()
        return oldPhase
    }

    /// Cleans up non-continuation resources owned by a phase.
    ///
    /// Timeout cancellation is phase-aware:
    /// - Discovery timeout is preserved when transitioning within the discovery chain
    /// - Auto-reconnect timeout is preserved when staying in auto-reconnect
    private func cleanupPhaseResources(_ oldPhase: BLEPhase, newPhase: BLEPhase) {
        // Only cancel discovery timeout when leaving the discovery chain
        if !newPhase.isDiscoveryChain {
            serviceDiscoveryTimeoutTask?.cancel()
            serviceDiscoveryTimeoutTask = nil
        }

        // Only cancel auto-reconnect timeout when leaving auto-reconnect
        if case .autoReconnecting = newPhase {
            // preserve
        } else {
            autoReconnectDiscoveryTimeoutTask?.cancel()
            autoReconnectDiscoveryTimeoutTask = nil
        }

        switch oldPhase {
        case .connecting(_, _, let timeoutTask):
            timeoutTask.cancel()

        case .connected(_, _, _, let dataContinuation):
            // Clear delegate handler's continuation first to stop data flow
            delegateHandler.setDataContinuation(nil)
            dataContinuation.finish()

        default:
            break
        }
    }

    /// Cancels the current operation, resuming any pending continuation with an error.
    ///
    /// - Parameter error: The error to resume continuations with
    func cancelCurrentOperation(with error: Error) {
        // Cancel any pending write operations
        writeTimeoutTask?.cancel()
        writeTimeoutTask = nil
        consecutiveQueuedWrites = 0

        if let pending = pendingWriteContinuation {
            pendingWriteContinuation = nil
            pending.resume(throwing: error)
        }

        // Resume all write waiters (they'll fail on the .connected check)
        while !writeWaiters.isEmpty {
            writeWaiters.removeFirst().resume()
        }

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

        case .idle, .autoReconnecting, .restoringState, .disconnecting:
            break
        }

        transition(to: .idle)
    }

    /// Cancels connection to a peripheral if we're not expecting it.
    private func cancelUnexpectedPeripheral(_ peripheral: CBPeripheral) {
        logger.warning("Cancelling unexpected peripheral: \(peripheral.identifier)")
        centralManager.cancelPeripheralConnection(peripheral)
    }

    private func handleServiceDiscoveryTimeout(for peripheral: CBPeripheral) {
        switch phase {
        case .discoveringServices(let p, let c),
             .discoveringCharacteristics(let p, _, let c),
             .subscribingToNotifications(let p, _, _, let c):
            guard p.identifier == peripheral.identifier else { return }
            let pState = peripheralStateString(peripheral.state)
            let elapsed = Date().timeIntervalSince(phaseStartTime)
            logger.warning("[BLE] Service discovery timeout: \(peripheral.identifier.uuidString.prefix(8)), phase: \(self.phase.name), peripheralState: \(pState), elapsed: \(String(format: "%.2f", elapsed))s")
            centralManager.cancelPeripheralConnection(peripheral)
            transition(to: .idle)
            c.resume(throwing: BLEError.connectionTimeout)
        default:
            break
        }
    }

    private func handleAutoReconnectDiscoveryTimeout(for peripheral: CBPeripheral) {
        guard case .autoReconnecting(let expected, _, _) = phase,
              expected.identifier == peripheral.identifier else {
            return
        }

        let pState = peripheralStateString(peripheral.state)
        let elapsed = Date().timeIntervalSince(phaseStartTime)
        logger.warning(
            "[BLE] Auto-reconnect discovery timeout: \(peripheral.identifier.uuidString.prefix(8)), peripheralState: \(pState), elapsed: \(String(format: "%.2f", elapsed))s"
        )

        centralManager.cancelPeripheralConnection(peripheral)
        transition(to: .idle)
        onDisconnection?(peripheral.identifier, BLEError.connectionTimeout)
    }
}
