@preconcurrency import CoreBluetooth
import Foundation

// MARK: - BLE Connection State

/// Connection state for BLE devices
public enum BLEConnectionState: Sendable, Equatable {
    case disconnected
    case scanning
    case connecting
    case connected
    case ready  // After device query and app start complete
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

    private var _connectionState: BLEConnectionState = .disconnected
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

        // Connect with timeout
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    Task { @MainActor in
                        await self.setConnectionContinuation(continuation)
                        centralManager.connect(peripheral, options: nil)
                    }
                }
            }

            group.addTask {
                try await Task.sleep(for: .seconds(self.connectionTimeout))
                throw BLEError.connectionTimeout
            }

            // Wait for either connection or timeout
            do {
                try await group.next()
                group.cancelAll()
            } catch {
                group.cancelAll()
                await self.handleConnectionFailure()
                throw error
            }
        }
    }

    private func setConnectionContinuation(_ continuation: CheckedContinuation<Void, Error>) {
        connectionContinuation = continuation
    }

    private func handleConnectionFailure() {
        _connectionState = .disconnected
        if let peripheral = connectedPeripheral {
            centralManager?.cancelPeripheralConnection(peripheral)
        }
        connectedPeripheral = nil
        txCharacteristic = nil
        rxCharacteristic = nil
    }

    public func disconnect() async {
        if let peripheral = connectedPeripheral {
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
        guard let peripheral = connectedPeripheral,
              let txCharacteristic else {
            throw BLEError.notConnected
        }

        guard _connectionState == .connected || _connectionState == .ready else {
            throw BLEError.notConnected
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
            Task {
                self.pendingResponse = continuation

                // Set up timeout
                Task {
                    try? await Task.sleep(for: .seconds(self.responseTimeout))
                    if let pending = self.pendingResponse {
                        self.pendingResponse = nil
                        pending.resume(returning: nil)
                    }
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

    // MARK: - Protocol Helpers

    /// Performs device initialization sequence (device query + app start)
    public func initializeDevice() async throws -> (DeviceInfo, SelfInfo) {
        guard _connectionState == .connected else {
            throw BLEError.notConnected
        }

        // Send device query
        let queryData = FrameCodec.encodeDeviceQuery(protocolVersion: 8)
        guard let queryResponse = try await send(queryData),
              queryResponse.first == ResponseCode.deviceInfo.rawValue else {
            throw BLEError.invalidResponse
        }
        let deviceInfo = try FrameCodec.decodeDeviceInfo(from: queryResponse)

        // Send app start
        let appStartData = FrameCodec.encodeAppStart(appName: "PocketMesh")
        guard let selfResponse = try await send(appStartData),
              selfResponse.first == ResponseCode.selfInfo.rawValue else {
            throw BLEError.invalidResponse
        }
        let selfInfo = try FrameCodec.decodeSelfInfo(from: selfResponse)

        _connectionState = .ready
        return (deviceInfo, selfInfo)
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
        if let pending = pendingResponse {
            pendingResponse = nil
            pending.resume(returning: data)
        }
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
            // Resume any waiting task
            bluetoothReadyContinuation?.resume()
            bluetoothReadyContinuation = nil
        case .poweredOff, .unauthorized, .unsupported:
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

    nonisolated public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        Task {
            await handleDisconnection(peripheral: peripheral, error: error)
        }
    }

    private func handleDisconnection(peripheral: CBPeripheral, error: Error?) {
        let deviceID = peripheral.identifier
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
        } else {
            connectionContinuation?.resume(throwing: BLEError.characteristicNotFound)
            connectionContinuation = nil
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

    private func handleWriteError(_ error: Error) {
        // Resume pending response with nil on write error
        if let pending = pendingResponse {
            pendingResponse = nil
            pending.resume(returning: nil)
        }
    }
}
