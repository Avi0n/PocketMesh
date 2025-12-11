@preconcurrency import CoreBluetooth
import Foundation

// MARK: - BLE Connection State

/// Connection state for BLE devices
public enum BLEConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    /// BLE connection established, characteristics discovered.
    /// Device initialization (initializeDevice) may still fail - caller should
    /// disconnect if initialization fails.
    case connected
    /// Device fully initialized and ready for communication.
    case ready
}

// MARK: - BLE Errors

/// Errors that can occur during BLE operations
public enum BLEError: Error, Sendable {
    case bluetoothUnavailable
    case bluetoothUnauthorized
    case bluetoothPoweredOff
    case deviceNotFound
    case connectionFailed(String)
    case connectionTimeout
    case notConnected
    case characteristicNotFound
    case writeError(String)
    case protocolError(ProtocolError)
    case invalidResponse
    case operationTimeout
    case authenticationFailed
    case authenticationRequired
    case pairingCancelled
    case pairingFailed(String)
}

// MARK: - BLEError LocalizedError Conformance

extension BLEError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .bluetoothUnavailable:
            return "Bluetooth is not available on this device."
        case .bluetoothUnauthorized:
            return "Bluetooth permission is required. Please enable it in Settings."
        case .bluetoothPoweredOff:
            return "Bluetooth is turned off. Please enable Bluetooth to connect."
        case .deviceNotFound:
            return "Device not found. Please make sure it's powered on and nearby."
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .connectionTimeout:
            return "Connection timed out. Please try again."
        case .notConnected:
            return "Not connected to a device."
        case .characteristicNotFound:
            return "Unable to communicate with device. Please try reconnecting."
        case .writeError(let message):
            return "Failed to send data: \(message)"
        case .protocolError(let error):
            return "Device communication error: \(error)"
        case .invalidResponse:
            return "Invalid response from device. Please try again."
        case .operationTimeout:
            return "Operation timed out. Please try again."
        case .authenticationFailed:
            return "Authentication failed. Please check your device's PIN."
        case .authenticationRequired:
            return "Authentication required. Please enter the device PIN when prompted."
        case .pairingCancelled:
            return "Bluetooth pairing was cancelled. Please try again."
        case .pairingFailed(let reason):
            return "Bluetooth pairing failed: \(reason)"
        }
    }
}

// MARK: - Pairing Failure Detection

/// CBATTError codes that indicate pairing/authentication failure
/// These errors mean pairing was cancelled, failed, or never completed
private let pairingFailureErrorCodes: Set<Int> = [
    5,   // insufficientAuthentication - pairing required but not completed
    8,   // insufficientAuthorization - authorization failed
    14,  // unlikelyError - peer removed pairing information
    15   // insufficientEncryption - encryption failed
]

/// Checks if an error indicates a BLE pairing failure
/// - Parameter error: The error from a BLE write/read operation
/// - Returns: true if this error indicates pairing failed or was cancelled
private func isPairingFailureError(_ error: Error) -> Bool {
    let nsError = error as NSError
    // CBATTErrorDomain errors indicate ATT-level failures
    guard nsError.domain == "CBATTErrorDomain" else { return false }
    return pairingFailureErrorCodes.contains(nsError.code)
}


// MARK: - BLE Service Protocol

/// Protocol for BLE transport (allows mock injection for testing)
public protocol BLETransport: Actor {
    var connectionState: BLEConnectionState { get async }
    var connectedDeviceID: UUID? { get async }

    func connect(to deviceID: UUID) async throws
    func disconnect() async
    func send(_ data: Data) async throws -> Data?
    func setResponseHandler(_ handler: @escaping @Sendable (Data) -> Void) async
}

// MARK: - BLE Service Actor

/// Actor-isolated BLE service for CoreBluetooth operations.
/// Handles connection and Nordic UART communication.
public actor BLEService: NSObject, BLETransport {

    // MARK: - Properties

    private var centralManager: CBCentralManager?
    private var connectedPeripheral: CBPeripheral?
    private var txCharacteristic: CBCharacteristic?
    private var rxCharacteristic: CBCharacteristic?

    private var _connectionState: BLEConnectionState = .disconnected {
        didSet {
            #if DEBUG
            if oldValue != _connectionState {
                print("[BLE] State: \(oldValue) → \(_connectionState)")
            }
            #endif
        }
    }
    public var connectionState: BLEConnectionState {
        _connectionState
    }

    public var connectedDeviceID: UUID? {
        connectedPeripheral?.identifier
    }

    // Response handling
    private var responseHandler: (@Sendable (Data) -> Void)?
    private var pendingResponse: CheckedContinuation<Data?, Never>?
    private var responseBuffer: Data = Data()
    /// Task for pending response timeout (cancelled when response arrives)
    private var responseTimeoutTask: Task<Void, Never>?

    /// Whether a send operation is currently in progress
    private var sendInProgress = false

    /// Queue of callers waiting to send (FIFO)
    private var sendQueue: [CheckedContinuation<Void, Never>] = []

    /// Tracks whether we're in the initial pairing window where transient errors are expected
    private var inPairingWindow: Bool = false

    /// Tracks whether we need to re-subscribe to RX after an isReconnecting disconnection
    private var needsResubscriptionAfterReconnect: Bool = false

    /// Tracks whether iOS is auto-reconnecting (isReconnecting=true from didDisconnectPeripheral)
    /// Used to prevent invalid state transitions and coordinate cleanup
    private var isAutoReconnecting: Bool = false

    /// Tracks whether a disconnect operation is currently in progress
    private var disconnectInProgress = false

    /// Continuation for callers waiting for disconnect to complete
    private var disconnectWaiters: [CheckedContinuation<Void, Never>] = []

    /// Timestamp when pairing window started (for timeout calculation)
    private var pairingWindowStart: Date?

    /// Duration of the pairing window - slightly longer than iOS's ~30s pairing dialog timeout
    private let pairingWindowDuration: TimeInterval = 35.0

    /// Stores the last pairing error for more specific error messages
    private var lastPairingError: Error?

    // Disconnection handling
    private var disconnectionHandler: (@Sendable (UUID, Error?) -> Void)?

    /// Reconnection completion callback - called when iOS auto-reconnect succeeds
    private var reconnectionHandler: (@Sendable (UUID) -> Void)?

    /// Callback when send activity state changes (busy/idle)
    private var sendActivityHandler: (@Sendable (Bool) -> Void)?

    // Connection handling
    private var connectionContinuation: CheckedContinuation<Void, Error>?
    private var bluetoothReadyContinuation: CheckedContinuation<Void, Never>?
    private var notificationContinuation: CheckedContinuation<Void, Error>?

    // State restoration
    private let stateRestorationID = "com.pocketmesh.ble.central"

    // Service/Characteristic UUIDs
    private let nordicUARTServiceUUID = CBUUID(string: BLEServiceUUID.nordicUART)
    private let txCharacteristicUUID = CBUUID(string: BLEServiceUUID.txCharacteristic)
    private let rxCharacteristicUUID = CBUUID(string: BLEServiceUUID.rxCharacteristic)

    // Timeouts
    private let connectionTimeout: TimeInterval = 10.0
    private let responseTimeout: TimeInterval = 5.0
    private let initialSetupTimeout: TimeInterval = 40.0  // Reduced from 60s - just past iOS's ~30s pairing dialog

    // MARK: - Initialization

    public override init() {
        super.init()
    }

    /// Initialize the central manager (must be called from main actor context)
    public func initialize() {
        guard centralManager == nil else { return }
        let options: [String: Any] = [
            CBCentralManagerOptionRestoreIdentifierKey: stateRestorationID,
            CBCentralManagerOptionShowPowerAlertKey: true
        ]
        centralManager = CBCentralManager(delegate: self, queue: nil, options: options)
    }

    /// Wait for Bluetooth to be powered on
    public func waitForBluetoothReady() async {
        guard let centralManager else { return }

        // Already ready
        if centralManager.state == .poweredOn { return }

        // Wait for state change
        await withCheckedContinuation { continuation in
            self.bluetoothReadyContinuation = continuation
        }
    }

    // MARK: - Connection

    public func connect(to deviceID: UUID) async throws {
        // Ensure Bluetooth is powered on before using centralManager
        await waitForBluetoothReady()

        // Wait for any pending disconnect to complete (prevents race conditions)
        await waitForDisconnectCompletion()

        guard let centralManager else {
            throw BLEError.bluetoothUnavailable
        }

        // Verify Bluetooth is actually powered on (required for retrievePeripherals)
        guard centralManager.state == .poweredOn else {
            switch centralManager.state {
            case .unauthorized:
                throw BLEError.bluetoothUnauthorized
            case .poweredOff:
                throw BLEError.bluetoothPoweredOff
            default:
                throw BLEError.bluetoothUnavailable
            }
        }

        // Find the peripheral
        let peripherals = centralManager.retrievePeripherals(withIdentifiers: [deviceID])
        guard let peripheral = peripherals.first else {
            throw BLEError.deviceNotFound
        }

        _connectionState = .connecting

        // Connect with timeout using race pattern
        do {
            try await withThrowingTimeout(seconds: connectionTimeout) {
                try await self.awaitConnection(to: peripheral)
            }
        } catch {
            handleConnectionFailure()
            throw error
        }
    }

    /// Initiates connection and waits for completion
    private func awaitConnection(to peripheral: CBPeripheral) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Use assumeIsolated to safely access actor state from continuation closure
            // This is safe because we're still executing on the actor's executor
            self.assumeIsolated { isolatedSelf in
                // Set continuation BEFORE calling connect to avoid race condition
                isolatedSelf.connectionContinuation = continuation

                // Now initiate connection - delegate may fire immediately
                let options = isolatedSelf.connectionOptions()
                isolatedSelf.centralManager?.connect(peripheral, options: options)
            }
        }
    }

    /// Subscribes to notifications and waits for confirmation
    /// This may trigger the iOS pairing dialog - we wait for subscription to complete
    private func awaitNotificationSubscription(for characteristic: CBCharacteristic) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.assumeIsolated { isolatedSelf in
                isolatedSelf.notificationContinuation = continuation
                isolatedSelf.connectedPeripheral?.setNotifyValue(true, for: characteristic)
            }
        }
    }

    /// Executes an async operation with a timeout
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

    private func handleConnectionFailure() {
        #if DEBUG
        print("[BLE] Connection failed: \(_connectionState) → disconnected")
        #endif

        // Clear all continuations to prevent double-resume from late callbacks
        connectionContinuation = nil
        cancelPendingNotificationContinuation()

        // Clear reconnection tracking
        isAutoReconnecting = false
        needsResubscriptionAfterReconnect = false

        _connectionState = .disconnected
        if let peripheral = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        txCharacteristic = nil
        rxCharacteristic = nil
        clearSendQueue()  // Prevents hangs if sends were queued during connection attempt
    }

    /// Returns connection options including iOS 17+ auto-reconnect
    private func connectionOptions() -> [String: Any] {
        var options: [String: Any] = [
            // Notify user when connection drops in background
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
            // Notify user when notifications arrive in background
            CBConnectPeripheralOptionNotifyOnNotificationKey: true
        ]

        // Add auto-reconnect (iOS 17+, but we target iOS 26 so always available)
        options[CBConnectPeripheralOptionEnableAutoReconnect] = true

        return options
    }

    public func disconnect() async {
        // Mark disconnect in progress
        disconnectInProgress = true
        defer {
            disconnectInProgress = false
            // Resume any callers waiting for disconnect to complete
            let waiters = disconnectWaiters
            disconnectWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }

        // Clean up all pending continuations to avoid leaks
        // This is critical when Bluetooth is toggled off during an active operation
        cancelPendingNotificationContinuation()
        resumePendingResponse(with: nil)
        clearSendQueue()

        // Clear reconnection tracking
        isAutoReconnecting = false
        needsResubscriptionAfterReconnect = false

        // Unsubscribe from characteristics before disconnecting
        // This ensures clean teardown and prevents undefined peripheral behavior
        if let peripheral = connectedPeripheral {
            // Only try to unsubscribe if peripheral is actually connected
            // Prevents API MISUSE warning when Bluetooth is toggled off
            if peripheral.state == .connected, let rx = rxCharacteristic {
                peripheral.setNotifyValue(false, for: rx)
            }
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        txCharacteristic = nil
        rxCharacteristic = nil
        _connectionState = .disconnected
        responseBuffer.removeAll()
    }

    /// Waits for any in-progress disconnect to complete
    /// Call this before starting a new connection to avoid race conditions
    public func waitForDisconnectCompletion() async {
        guard disconnectInProgress else { return }

        await withCheckedContinuation { continuation in
            disconnectWaiters.append(continuation)
        }
    }

    // MARK: - Send Queue Serialization

    /// Acquires exclusive access to the send operation.
    /// If a send is already in progress, suspends until it's our turn.
    private func acquireSendLock() async {
        if !sendInProgress {
            sendInProgress = true
            sendActivityHandler?(true)  // Notify: now busy
            return
        }

        // Another send is in progress - wait our turn
        #if DEBUG
        print("[BLE] Send queued, waiting for previous operation (\(sendQueue.count + 1) waiting)")
        #endif
        await withCheckedContinuation { continuation in
            sendQueue.append(continuation)
        }
    }

    /// Releases the send lock, resuming the next queued caller if any.
    private func releaseSendLock() {
        if let next = sendQueue.first {
            sendQueue.removeFirst()
            next.resume()
        } else {
            sendInProgress = false
            sendActivityHandler?(false)  // Notify: no longer busy
        }
    }

    /// Clears all queued send operations, unblocking waiting callers.
    /// Called on disconnect to prevent hangs.
    private func clearSendQueue() {
        while let queued = sendQueue.first {
            sendQueue.removeFirst()
            queued.resume()  // Unblocks waiters; they'll see disconnected state and throw
        }
        sendInProgress = false
    }

    // MARK: - Data Transfer

    public func send(_ data: Data) async throws -> Data? {
        try await send(data, timeout: responseTimeout, forPairing: false)
    }

    /// Internal send method with configurable timeout and pairing window handling
    private func send(_ data: Data, timeout: TimeInterval, forPairing: Bool) async throws -> Data? {
        // Serialize send operations - only one in flight at a time
        await acquireSendLock()
        defer { releaseSendLock() }  // CRITICAL: Ensures cleanup on ALL paths (timeout, error, success)

        guard let peripheral = connectedPeripheral,
              let txCharacteristic else {
            throw BLEError.notConnected
        }

        guard _connectionState == .connected || _connectionState == .ready else {
            throw BLEError.notConnected
        }

        // Verify peripheral is actually connected at CoreBluetooth level
        guard peripheral.state == .connected else {
            throw BLEError.notConnected
        }

        // Set pairing window if this is an initial pairing operation
        if forPairing {
            inPairingWindow = true
            pairingWindowStart = Date()
        }

        // Write data in chunks if needed (BLE MTU typically ~185-512 bytes)
        let mtu = peripheral.maximumWriteValueLength(for: .withResponse)
        let chunks = stride(from: 0, to: data.count, by: mtu).map {
            data.subdata(in: $0..<min($0 + mtu, data.count))
        }

        for chunk in chunks {
            peripheral.writeValue(chunk, for: txCharacteristic, type: .withResponse)
        }

        // Wait for response with timeout
        return await withCheckedContinuation { continuation in
            // Use assumeIsolated to safely access actor state from continuation closure
            // This avoids the race condition where Task { } delays setting pendingResponse
            self.assumeIsolated { isolatedSelf in
                isolatedSelf.pendingResponse = continuation

                // Set up timeout with effective duration (stored for cancellation)
                isolatedSelf.responseTimeoutTask = Task {
                    try? await Task.sleep(for: .seconds(timeout))
                    // Resume with nil on timeout
                    await isolatedSelf.resumePendingResponse(with: nil)
                }
            }
        }
    }

    public func setResponseHandler(_ handler: @escaping @Sendable (Data) -> Void) async {
        responseHandler = handler
    }

    /// Sets a handler for disconnection events
    public func setDisconnectionHandler(_ handler: @escaping @Sendable (UUID, Error?) -> Void) async {
        disconnectionHandler = handler
    }

    /// Sets a handler for reconnection events (iOS auto-reconnect completion)
    public func setReconnectionHandler(_ handler: @escaping @Sendable (UUID) -> Void) async {
        reconnectionHandler = handler
    }

    /// Set handler for send activity changes
    /// - Parameter handler: Called with `true` when BLE becomes busy, `false` when idle
    public func setSendActivityHandler(_ handler: (@Sendable (Bool) -> Void)?) async {
        sendActivityHandler = handler
    }

    // MARK: - Continuation Safety

    /// Resumes the pending response continuation safely.
    /// Must be called from actor-isolated context (all callers already hop via Task { await ... }).
    private func resumePendingResponse(with data: Data?) {
        guard let pending = pendingResponse else { return }
        pendingResponse = nil

        // Cancel the timeout task to avoid resource leak
        responseTimeoutTask?.cancel()
        responseTimeoutTask = nil

        // Exit pairing window but preserve error for diagnosis
        exitPairingWindow()
        pending.resume(returning: data)
    }

    /// Checks if we're still within the pairing window where transient errors are tolerated
    private func isWithinPairingWindow() -> Bool {
        guard inPairingWindow, let start = pairingWindowStart else { return false }
        return Date().timeIntervalSince(start) < pairingWindowDuration
    }

    /// Exits the pairing window (called when operation completes or pairing fails)
    private func exitPairingWindow() {
        inPairingWindow = false
        pairingWindowStart = nil
    }

    /// Cancels any pending notification continuation to prevent leaks
    /// Called before starting a new subscription or during unexpected disconnection
    /// Uses BLEError.connectionFailed so callers can handle it appropriately
    private func cancelPendingNotificationContinuation() {
        guard let continuation = notificationContinuation else { return }
        notificationContinuation = nil
        continuation.resume(throwing: BLEError.connectionFailed("Operation cancelled during reconnection"))
    }

    /// Returns a specific BLEError based on the last pairing error encountered
    private func getPairingError() -> BLEError {
        guard let error = lastPairingError else {
            return .pairingCancelled
        }

        let nsError = error as NSError
        switch nsError.code {
        case 5:  // insufficientAuthentication
            return .pairingCancelled
        case 14: // unlikelyError - peer removed pairing
            return .pairingFailed("Device pairing data mismatch. Please go to Settings > Bluetooth, find the device, and tap 'Forget This Device', then try again.")
        case 15: // insufficientEncryption
            return .pairingFailed("Encryption setup failed. Please try again.")
        case 8:  // insufficientAuthorization
            return .pairingFailed("Authorization failed. Please try again.")
        default:
            return .pairingCancelled
        }
    }

    // MARK: - Protocol Helpers

    /// Performs device initialization sequence (device query + app start)
    public func initializeDevice() async throws -> (DeviceInfo, SelfInfo) {
        guard _connectionState == .connected else {
            throw BLEError.notConnected
        }

        // Use longer timeout and ignore write errors for initial setup (pairing may occur)
        // iOS pairing dialog can cause temporary write failures that resolve after PIN entry
        let setupTimeout = initialSetupTimeout

        // Send device query
        let queryData = FrameCodec.encodeDeviceQuery(protocolVersion: 8)
        guard let queryResponse = try await send(queryData, timeout: setupTimeout, forPairing: true),
              queryResponse.first == ResponseCode.deviceInfo.rawValue else {
            // Get specific pairing error if available
            if lastPairingError != nil {
                let error = getPairingError()
                lastPairingError = nil  // Clear for next attempt
                throw error
            }
            throw BLEError.invalidResponse
        }
        let deviceInfo = try FrameCodec.decodeDeviceInfo(from: queryResponse)

        // Send app start (pairing should be complete by now, but keep the longer timeout)
        let appStartData = FrameCodec.encodeAppStart(appName: "PocketMesh")
        guard let selfResponse = try await send(appStartData, timeout: setupTimeout, forPairing: false),
              selfResponse.first == ResponseCode.selfInfo.rawValue else {
            throw BLEError.invalidResponse
        }
        let selfInfo = try FrameCodec.decodeSelfInfo(from: selfResponse)

        _connectionState = .ready
        return (deviceInfo, selfInfo)
    }

    /// Performs device initialization with retry logic for handling transient failures
    /// - Parameter maxRetries: Maximum number of retry attempts (default: 3)
    /// - Parameter initialDelay: Initial delay between retries in seconds (default: 0.5)
    /// - Returns: Tuple of DeviceInfo and SelfInfo on success
    public func initializeDeviceWithRetry(
        maxRetries: Int = 3,  // Increased from 2 - better handles device boot scenarios
        initialDelay: TimeInterval = 0.5  // Start with shorter delay, increase exponentially
    ) async throws -> (DeviceInfo, SelfInfo) {
        var lastError: Error = BLEError.invalidResponse

        for attempt in 1...maxRetries {
            // Support Swift's cooperative cancellation model
            try Task.checkCancellation()

            do {
                return try await initializeDevice()
            } catch BLEError.pairingCancelled {
                // Don't retry if pairing was explicitly cancelled
                throw BLEError.pairingCancelled
            } catch BLEError.pairingFailed(let reason) {
                // Don't retry pairing failures - they won't resolve with retries
                throw BLEError.pairingFailed(reason)
            } catch BLEError.invalidResponse {
                // Retry on invalid response - could be transient during reconnection
                lastError = BLEError.invalidResponse

                // Don't retry if we're no longer connected
                guard _connectionState == .connected || _connectionState == .ready else {
                    throw BLEError.invalidResponse
                }

                #if DEBUG
                print("[BLE] initializeDevice attempt \(attempt) failed with invalidResponse, retrying...")
                #endif

                if attempt < maxRetries {
                    try Task.checkCancellation()
                    // Exponential backoff: 0.5s, 1.0s, 2.0s (capped at 3s)
                    let delay = min(initialDelay * pow(2.0, Double(attempt - 1)), 3.0)
                    try await Task.sleep(for: .seconds(delay))
                }
            } catch {
                lastError = error

                // Don't retry if we're no longer connected
                guard _connectionState == .connected || _connectionState == .ready else {
                    throw error
                }

                #if DEBUG
                print("[BLE] initializeDevice attempt \(attempt) failed with \(error), retrying...")
                #endif

                if attempt < maxRetries {
                    try Task.checkCancellation()
                    // Exponential backoff for other errors too
                    let delay = min(initialDelay * pow(2.0, Double(attempt - 1)), 3.0)
                    try await Task.sleep(for: .seconds(delay))
                }
            }
        }

        throw lastError
    }


    // MARK: - Private Helpers

    private func handleReceivedData(_ data: Data) {
        guard !data.isEmpty else { return }

        // Check if this is a push notification (0x80+)
        if data[0] >= 0x80 {
            responseHandler?(data)
            return
        }

        // Otherwise, this is a response to a command
        resumePendingResponse(with: data)
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEService: CBCentralManagerDelegate {

    nonisolated public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task {
            await handleStateUpdate(central.state)
        }
    }

    private func handleStateUpdate(_ state: CBManagerState) {
        switch state {
        case .poweredOn:
            // Resume any waiting task - Bluetooth is ready
            bluetoothReadyContinuation?.resume()
            bluetoothReadyContinuation = nil
        case .poweredOff, .unauthorized, .unsupported:
            // Resume continuation so waiters don't hang indefinitely
            // They will check the state and throw appropriate errors
            bluetoothReadyContinuation?.resume()
            bluetoothReadyContinuation = nil
            clearSendQueue()  // Clear BEFORE async disconnect to prevent race condition (idempotent, safe to call twice)
            Task {
                await disconnect()
            }
        default:
            break
        }
    }

    nonisolated public func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        Task {
            await handleConnection(peripheral)
        }
    }

    private func handleConnection(_ peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        peripheral.delegate = self

        // Clear any stale data from previous session
        responseBuffer.removeAll()

        peripheral.discoverServices([nordicUARTServiceUUID])
    }

    nonisolated public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        Task {
            await handleConnectionError(error)
        }
    }

    private func handleConnectionError(_ error: Error?) {
        _connectionState = .disconnected
        connectionContinuation?.resume(throwing: BLEError.connectionFailed(error?.localizedDescription ?? "Unknown error"))
        connectionContinuation = nil
    }

    /// iOS 17+ delegate method that indicates whether the system is auto-reconnecting
    nonisolated public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        timestamp: CFAbsoluteTime,
        isReconnecting: Bool,
        error: Error?
    ) {
        Task {
            await handleDisconnectionWithReconnect(
                peripheral: peripheral,
                isReconnecting: isReconnecting,
                error: error
            )
        }
    }

    private func handleDisconnectionWithReconnect(
        peripheral: CBPeripheral,
        isReconnecting: Bool,
        error: Error?
    ) {
        // If system is auto-reconnecting, prepare for re-subscription
        if isReconnecting {
            #if DEBUG
            print("[BLE] System auto-reconnecting, preparing for re-subscription")
            #endif

            // Track that we're in auto-reconnection mode
            isAutoReconnecting = true

            // Cancel any pending notification continuation BEFORE clearing state
            // This prevents "leaked continuation" warnings when subscription is retried
            cancelPendingNotificationContinuation()

            // Cancel pending connection continuation if we were mid-connection
            // (This can happen if isReconnecting fires during initial connect)
            if let cc = connectionContinuation {
                connectionContinuation = nil
                cc.resume(throwing: BLEError.connectionFailed("Connection interrupted by system reconnection"))
            }

            // Clear response buffer - may contain stale data from previous session
            responseBuffer.removeAll()

            // Only transition to .connecting if not already there
            // (State restoration may have already set .connecting)
            if _connectionState != .connecting {
                _connectionState = .connecting
            }

            // Mark that we need to re-subscribe after reconnection
            // The RX subscription is invalidated on disconnect
            needsResubscriptionAfterReconnect = true

            // Clear characteristic references - they become invalid on disconnect
            // We'll get new ones after re-discovery
            txCharacteristic = nil
            rxCharacteristic = nil

            return
        }

        // Full disconnection - delegate to normal handler
        handleDisconnection(peripheral: peripheral, error: error)
    }

    private func handleDisconnection(peripheral: CBPeripheral, error: Error?) {
        let deviceID = peripheral.identifier

        // Clean up pairing window state
        exitPairingWindow()

        // Clear reconnection tracking
        isAutoReconnecting = false
        needsResubscriptionAfterReconnect = false

        // Clean up all pending continuations to avoid leaks
        // These callbacks will never be called for a disconnected device
        cancelPendingNotificationContinuation()
        resumePendingResponse(with: nil)
        clearSendQueue()

        connectedPeripheral = nil
        txCharacteristic = nil
        rxCharacteristic = nil
        _connectionState = .disconnected

        // Notify about disconnection
        disconnectionHandler?(deviceID, error)
    }

    nonisolated public func centralManager(
        _ central: CBCentralManager,
        willRestoreState dict: [String: Any]
    ) {
        // Handle state restoration for background BLE
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
           let peripheral = peripherals.first {
            Task {
                await handleRestoredPeripheral(peripheral)
            }
        }
    }

    private func handleRestoredPeripheral(_ peripheral: CBPeripheral) {
        connectedPeripheral = peripheral
        peripheral.delegate = self

        if peripheral.state == .connected {
            // Don't set .connected yet - peripheral.state may be stale
            // iOS may fire isReconnecting disconnect immediately after restoration
            // Stay in .connecting until characteristic discovery completes successfully
            _connectionState = .connecting

            #if DEBUG
            print("[BLE] State restoration: peripheral reports connected, starting service discovery")
            #endif

            // Re-discover services to get characteristics
            peripheral.discoverServices([nordicUARTServiceUUID])
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEService: CBPeripheralDelegate {

    nonisolated public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        guard error == nil,
              let service = peripheral.services?.first(where: { $0.uuid == CBUUID(string: BLEServiceUUID.nordicUART) }) else {
            Task {
                await handleConnectionError(error)
            }
            return
        }

        peripheral.discoverCharacteristics(
            [CBUUID(string: BLEServiceUUID.txCharacteristic), CBUUID(string: BLEServiceUUID.rxCharacteristic)],
            for: service
        )
    }

    nonisolated public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        Task {
            await handleCharacteristicDiscovery(service: service, error: error)
        }
    }

    private func handleCharacteristicDiscovery(service: CBService, error: Error?) async {
        guard error == nil else {
            // Only fail the connection if we're in initial connection
            if connectionContinuation != nil {
                connectionContinuation?.resume(throwing: BLEError.characteristicNotFound)
                connectionContinuation = nil
            }
            return
        }

        // Clear response buffer for fresh start (handles reconnection case)
        responseBuffer.removeAll()

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

        // Check if we have both characteristics
        guard txCharacteristic != nil && rxCharacteristic != nil else {
            // Not all characteristics found yet - wait for more discovery calls
            return
        }

        // Determine if this is initial connection or reconnection
        let isInitialConnection = connectionContinuation != nil
        let isReconnection = needsResubscriptionAfterReconnect

        #if DEBUG
        if isReconnection {
            print("[BLE] Reconnection: re-subscribing to notifications")
        }
        #endif

        // Clear reconnection flag
        needsResubscriptionAfterReconnect = false

        guard isInitialConnection || isReconnection else {
            // Neither initial connection nor reconnection - nothing to do
            return
        }

        // Subscribe to notifications - this triggers pairing dialog if needed
        // We must wait for the subscription to complete before marking connected
        if let rx = rxCharacteristic {
            do {
                // Cancel any pending notification continuation BEFORE starting new subscription
                // This prevents race conditions during reconnection where old and new
                // subscription attempts interleave
                cancelPendingNotificationContinuation()

                // Wait for notification subscription with timeout
                // This ensures pairing completes before we try to send data
                try await withThrowingTimeout(seconds: initialSetupTimeout) {
                    try await self.awaitNotificationSubscription(for: rx)
                }

                // Allow device firmware to stabilize after BLE reconnection
                // MeshCore radios need brief delay before UART is ready for commands
                try await Task.sleep(for: .milliseconds(150))

                #if DEBUG
                if isReconnection {
                    print("[BLE] Reconnection: stabilization complete, ready for initialization")
                }
                #endif
            } catch {
                if isInitialConnection {
                    connectionContinuation?.resume(throwing: error)
                    connectionContinuation = nil
                }
                // For reconnection, just log the error - we'll fail on next send
                #if DEBUG
                if isReconnection {
                    print("[BLE] Reconnection: subscription failed - \(error.localizedDescription)")
                }
                #endif
                return
            }
        }

        // Only update state and resume continuation for initial connection
        if isInitialConnection {
            _connectionState = .connected
            connectionContinuation?.resume()
            connectionContinuation = nil
        } else if isReconnection {
            // For reconnection, restore to connected state
            _connectionState = .connected

            // Clear auto-reconnection flag now that we're fully reconnected
            isAutoReconnecting = false

            #if DEBUG
            print("[BLE] Auto-reconnection complete, state restored to connected")
            #endif

            // Notify that reconnection completed - device may have rebooted
            if let peripheral = connectedPeripheral {
                reconnectionHandler?(peripheral.identifier)
            }
        }
    }

    nonisolated public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil,
              let data = characteristic.value else { return }

        Task {
            await handleReceivedData(data)
        }
    }

    nonisolated public func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        // Write completed
        if let error {
            Task {
                await handleWriteError(error)
            }
        }
    }

    nonisolated public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task {
            await handleNotificationStateUpdate(characteristic: characteristic, error: error)
        }
    }

    private func handleNotificationStateUpdate(characteristic: CBCharacteristic, error: Error?) {
        guard characteristic.uuid == rxCharacteristicUUID else { return }

        // Guard against already-cancelled continuation (e.g., during reconnection race)
        // If continuation is nil, the subscription request was cancelled - nothing to resume
        guard let continuation = notificationContinuation else {
            #if DEBUG
            print("[BLE] Notification state update arrived but continuation was already cancelled")
            #endif
            return
        }
        notificationContinuation = nil

        if let error {
            continuation.resume(throwing: BLEError.characteristicNotFound)
        } else {
            continuation.resume()
        }
    }

    private func handleWriteError(_ error: Error) {
        // Check if this is a pairing failure error
        if isPairingFailureError(error) {
            lastPairingError = error
            // Pairing failed - exit pairing window and fail immediately
            // Don't wait for timeout - we know pairing won't succeed
            exitPairingWindow()
            resumePendingResponse(with: nil)
            return
        }

        // If we're in the pairing window, ignore transient write errors
        // iOS pairing can cause temporary write failures that resolve after PIN entry
        if isWithinPairingWindow() {
            // Transient error during pairing - ignore and let timeout handle it
            return
        }

        // Outside pairing window - treat as real error
        resumePendingResponse(with: nil)
    }
}
