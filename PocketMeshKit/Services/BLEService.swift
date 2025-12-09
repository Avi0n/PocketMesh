@preconcurrency import CoreBluetooth
import Foundation

// MARK: - BLE Connection State

/// Connection state for BLE devices
public enum BLEConnectionState: Sendable, Equatable {
    case disconnected
    case scanning
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


// MARK: - Discovered Device

/// A discovered MeshCore device during scanning
public struct DiscoveredDevice: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let rssi: Int

    public init(id: UUID, name: String, rssi: Int) {
        self.id = id
        self.name = name
        self.rssi = rssi
    }
}

// MARK: - BLE Service Protocol

/// Protocol for BLE transport (allows mock injection for testing)
public protocol BLETransport: Actor {
    var connectionState: BLEConnectionState { get async }
    var connectedDeviceID: UUID? { get async }

    func startScanning() async throws
    func stopScanning() async
    func connect(to deviceID: UUID) async throws
    func disconnect() async
    func send(_ data: Data) async throws -> Data?
    func setResponseHandler(_ handler: @escaping @Sendable (Data) -> Void) async
}

// MARK: - BLE Service Actor

/// Actor-isolated BLE service for CoreBluetooth operations.
/// Handles scanning, connection, and Nordic UART communication.
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

    // Discovered devices during scanning
    private var discoveredDevices: [UUID: DiscoveredDevice] = [:]

    // Response handling
    private var responseHandler: (@Sendable (Data) -> Void)?
    private var pendingResponse: CheckedContinuation<Data?, Never>?
    private var responseBuffer: Data = Data()
    /// Task for pending response timeout (cancelled when response arrives)
    private var responseTimeoutTask: Task<Void, Never>?


    /// Tracks whether we're in the initial pairing window where transient errors are expected
    private var inPairingWindow: Bool = false

    /// Timestamp when pairing window started (for timeout calculation)
    private var pairingWindowStart: Date?

    /// Duration of the pairing window - slightly longer than iOS's ~30s pairing dialog timeout
    private let pairingWindowDuration: TimeInterval = 35.0

    /// Stores the last pairing error for more specific error messages
    private var lastPairingError: Error?

    // Disconnection handling
    private var disconnectionHandler: (@Sendable (UUID, Error?) -> Void)?

    // Connection handling
    private var connectionContinuation: CheckedContinuation<Void, Error>?
    private var scanContinuation: AsyncStream<DiscoveredDevice>.Continuation?
    private var bluetoothReadyContinuation: CheckedContinuation<Void, Never>?

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

    // MARK: - Scanning

    public func startScanning() async throws {
        guard let centralManager else {
            throw BLEError.bluetoothUnavailable
        }

        // Wait for Bluetooth to be ready (with timeout)
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                await self.waitForBluetoothReady()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(5))
                throw BLEError.operationTimeout
            }
            try await group.next()
            group.cancelAll()
        }

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

        discoveredDevices.removeAll()
        _connectionState = .scanning

        centralManager.scanForPeripherals(
            withServices: [nordicUARTServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    public func stopScanning() async {
        centralManager?.stopScan()
        if _connectionState == .scanning {
            _connectionState = .disconnected
        }
        scanContinuation?.finish()
        scanContinuation = nil
    }

    /// Returns an async stream of discovered devices
    public func scanForDevices() -> AsyncStream<DiscoveredDevice> {
        AsyncStream { continuation in
            self.scanContinuation = continuation
        }
    }

    /// Get current list of discovered devices
    public func getDiscoveredDevices() -> [DiscoveredDevice] {
        Array(discoveredDevices.values).sorted { $0.rssi > $1.rssi }
    }

    // MARK: - Connection

    public func connect(to deviceID: UUID) async throws {
        guard let centralManager else {
            throw BLEError.bluetoothUnavailable
        }

        // Find the peripheral
        let peripherals = centralManager.retrievePeripherals(withIdentifiers: [deviceID])
        guard let peripheral = peripherals.first else {
            throw BLEError.deviceNotFound
        }

        await stopScanning()
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

        // Clear continuation to prevent double-resume from late callbacks
        connectionContinuation = nil

        _connectionState = .disconnected
        if let peripheral = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        txCharacteristic = nil
        rxCharacteristic = nil
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
        // Unsubscribe from characteristics before disconnecting
        // This ensures clean teardown and prevents undefined peripheral behavior
        if let peripheral = connectedPeripheral {
            if let rx = rxCharacteristic {
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

    // MARK: - Data Transfer

    public func send(_ data: Data) async throws -> Data? {
        try await send(data, timeout: responseTimeout, forPairing: false)
    }

    /// Internal send method with configurable timeout and pairing window handling
    private func send(_ data: Data, timeout: TimeInterval, forPairing: Bool) async throws -> Data? {
        guard let peripheral = connectedPeripheral,
              let txCharacteristic else {
            throw BLEError.notConnected
        }

        guard _connectionState == .connected || _connectionState == .ready else {
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
    /// - Parameter maxRetries: Maximum number of retry attempts (default: 1 for pairing, retrying won't help if cancelled)
    /// - Parameter retryDelay: Delay between retries in seconds (default: 2.0)
    /// - Returns: Tuple of DeviceInfo and SelfInfo on success
    public func initializeDeviceWithRetry(
        maxRetries: Int = 1,  // Reduced from 3 - retrying won't help if user cancelled pairing
        retryDelay: TimeInterval = 2.0
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
            } catch {
                lastError = error

                // Don't retry if we're no longer connected
                guard _connectionState == .connected else {
                    throw error
                }

                // Don't retry on the last attempt
                if attempt < maxRetries {
                    // Check cancellation before sleeping
                    try Task.checkCancellation()
                    try await Task.sleep(for: .seconds(retryDelay))
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
            Task {
                await disconnect()
            }
        default:
            break
        }
    }

    nonisolated public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let name = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unknown"
        let device = DiscoveredDevice(id: peripheral.identifier, name: name, rssi: RSSI.intValue)

        Task {
            await handleDiscoveredDevice(device)
        }
    }

    private func handleDiscoveredDevice(_ device: DiscoveredDevice) {
        discoveredDevices[device.id] = device
        scanContinuation?.yield(device)
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
        // If system is auto-reconnecting, don't fully clean up
        if isReconnecting {
            // System is handling reconnection - update state but keep references
            _connectionState = .connecting
            return
        }

        // Full disconnection - delegate to normal handler
        handleDisconnection(peripheral: peripheral, error: error)
    }

    private func handleDisconnection(peripheral: CBPeripheral, error: Error?) {
        let deviceID = peripheral.identifier

        // Clean up pairing window state
        exitPairingWindow()

        // Clean up pending response to avoid continuation leaks
        // This is critical - the callback will never be called for a disconnected device
        resumePendingResponse(with: nil)

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
            _connectionState = .connected
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

    private func handleCharacteristicDiscovery(service: CBService, error: Error?) {
        // Guard against multiple calls - only process if we haven't completed connection
        guard connectionContinuation != nil else { return }

        guard error == nil else {
            connectionContinuation?.resume(throwing: BLEError.characteristicNotFound)
            connectionContinuation = nil
            return
        }

        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case txCharacteristicUUID:
                txCharacteristic = characteristic
            case rxCharacteristicUUID:
                rxCharacteristic = characteristic
                // Subscribe to notifications
                connectedPeripheral?.setNotifyValue(true, for: characteristic)
            default:
                break
            }
        }

        if txCharacteristic != nil && rxCharacteristic != nil {
            _connectionState = .connected
            connectionContinuation?.resume()
            connectionContinuation = nil
        }
        // Note: Don't fail here if characteristics not found yet -
        // multi-service devices may need multiple discovery calls
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
