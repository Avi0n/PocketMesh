@preconcurrency import CoreBluetooth
import Foundation
import os

/// Nordic UART Service UUIDs (avoid string duplication)
private enum UARTUUID {
    static let service = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let rx = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")  // Write to device
    static let tx = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")  // Read from device
}

/// BLE transport implementation using CoreBluetooth
/// Uses AsyncStream for Swift 6 concurrency safety
public actor BLETransport: MeshTransport {

    private let logger = Logger(subsystem: "MeshCore", category: "BLETransport")

    private nonisolated let delegate: BLEDelegate
    private let address: String?
    private var peripheral: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic?

    private let dataStream: AsyncStream<Data>
    private let dataContinuation: AsyncStream<Data>.Continuation

    public private(set) var isConnected = false
    public private(set) var connectionState: ConnectionState = .disconnected

    public var receivedData: AsyncStream<Data> { dataStream }

    /// Creates a BLE transport for MeshCore device communication.
    ///
    /// - Parameter address: Optional BLE address (UUID string) to connect to a specific device.
    ///                      If nil, scans for any device advertising the Nordic UART Service
    ///                      with a name starting with "MeshCore".
    ///
    /// - Note: This transport does not handle automatic reconnection. CoreBluetooth's
    ///         `connect(_:options:)` persists connection intent, and apps should implement
    ///         their own reconnection policy by observing `connectionState` and calling
    ///         `connect()` again when appropriate.
    public init(address: String? = nil) {
        self.address = address

        let (stream, continuation) = AsyncStream.makeStream(of: Data.self)
        self.dataStream = stream
        self.dataContinuation = continuation

        self.delegate = BLEDelegate(dataContinuation: continuation)
    }

    public func connect() async throws {
        logger.info("Connecting to BLE device...")
        connectionState = .connecting

        try await delegate.waitForPoweredOn()

        if let address = address {
            try await connectToAddress(address)
        } else {
            try await scanAndConnect()
        }

        guard let peripheral = peripheral else {
            connectionState = .failed(MeshTransportError.connectionFailed("No peripheral"))
            throw MeshTransportError.connectionFailed("No peripheral")
        }

        try await discoverServices(peripheral)
        isConnected = true
        connectionState = .connected
        logger.info("BLE connection established")
    }

    public func disconnect() async {
        if let peripheral = peripheral {
            delegate.centralManager.cancelPeripheralConnection(peripheral)
        }
        isConnected = false
        connectionState = .disconnected
        dataContinuation.finish()
        logger.info("BLE disconnected")
    }

    public func send(_ data: Data) async throws {
        guard isConnected else {
            throw MeshTransportError.notConnected
        }
        guard let peripheral = peripheral,
              let characteristic = rxCharacteristic else {
            throw MeshTransportError.sendFailed("No characteristic")
        }

        peripheral.writeValue(data, for: characteristic, type: .withResponse)
        logger.debug("Sent \(data.count) bytes")
    }

    // MARK: - Private

    private func scanAndConnect() async throws {
        peripheral = try await delegate.scanForDevice()
        try await delegate.connect(to: peripheral!)
    }

    private func connectToAddress(_ address: String) async throws {
        peripheral = try await delegate.scanForDevice(withAddress: address)
        try await delegate.connect(to: peripheral!)
    }

    private func discoverServices(_ peripheral: CBPeripheral) async throws {
        let (_, txChar, rxChar) = try await delegate.discoverUARTService(on: peripheral)
        self.rxCharacteristic = rxChar
        peripheral.setNotifyValue(true, for: txChar)
    }
}

/// @unchecked Sendable: CBCentralManagerDelegate requires NSObject. All mutable state protected by continuationLock.
private final class BLEDelegate: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    let centralManager: CBCentralManager
    let disconnectionEvents: AsyncStream<Void>

    private let dataContinuation: AsyncStream<Data>.Continuation
    private let disconnectionContinuation: AsyncStream<Void>.Continuation
    private let continuationLock = OSAllocatedUnfairLock<ContinuationState>(initialState: ContinuationState())

    private struct ContinuationState {
        var state: CheckedContinuation<Void, Error>?
        var scan: CheckedContinuation<CBPeripheral, Error>?
        var connect: CheckedContinuation<Void, Error>?
        var discovery: CheckedContinuation<(CBService, CBCharacteristic, CBCharacteristic), Error>?
        var targetAddress: String?
    }

    private let bleQueue = DispatchQueue(label: "com.meshcore.ble", qos: .userInitiated)

    init(dataContinuation: AsyncStream<Data>.Continuation) {
        self.dataContinuation = dataContinuation
        
        let (disconnectStream, disconnectContinuation) = AsyncStream.makeStream(of: Void.self)
        self.disconnectionEvents = disconnectStream
        self.disconnectionContinuation = disconnectContinuation
        
        self.centralManager = CBCentralManager(delegate: nil, queue: bleQueue)
        super.init()
        centralManager.delegate = self
    }

    func waitForPoweredOn() async throws {
        // Check authorization before attempting BLE operations
        switch CBCentralManager.authorization {
        case .notDetermined:
            break  // Will prompt when we start scanning
        case .restricted, .denied:
            throw MeshTransportError.connectionFailed("Bluetooth access denied")
        case .allowedAlways:
            break
        @unknown default:
            break
        }

        if centralManager.state == .poweredOn { return }
        try await withCheckedThrowingContinuation { continuation in
            continuationLock.withLock { $0.state = continuation }
        }
    }

    func scanForDevice(withAddress targetAddress: String? = nil) async throws -> CBPeripheral {
        try await withCheckedThrowingContinuation { continuation in
            continuationLock.withLock { state in
                state.scan = continuation
                state.targetAddress = targetAddress
            }
            centralManager.scanForPeripherals(
                withServices: [UARTUUID.service],
                options: nil
            )
            // Timeout after 10 seconds
            Task { [weak self] in
                try await Task.sleep(for: .seconds(10))
                guard let self else { return }
                self.continuationLock.withLock { state in
                    if let cont = state.scan {
                        self.centralManager.stopScan()
                        cont.resume(throwing: MeshTransportError.deviceNotFound)
                        state.scan = nil
                        state.targetAddress = nil
                    }
                }
            }
        }
    }

    func connect(to peripheral: CBPeripheral) async throws {
        try await withCheckedThrowingContinuation { continuation in
            continuationLock.withLock { $0.connect = continuation }
            centralManager.connect(peripheral)
        }
    }

    func discoverUARTService(on peripheral: CBPeripheral) async throws -> (CBService, CBCharacteristic, CBCharacteristic) {
        try await withCheckedThrowingContinuation { continuation in
            continuationLock.withLock { $0.discovery = continuation }
            peripheral.delegate = self
            peripheral.discoverServices([UARTUUID.service])
        }
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        continuationLock.withLock { state in
            switch central.state {
            case .poweredOn:
                state.state?.resume()
                state.state = nil
            case .poweredOff:
                state.state?.resume(throwing: MeshTransportError.connectionFailed("Bluetooth is off"))
                state.state = nil
            case .unauthorized:
                state.state?.resume(throwing: MeshTransportError.connectionFailed("Bluetooth unauthorized"))
                state.state = nil
            case .unsupported:
                state.state?.resume(throwing: MeshTransportError.connectionFailed("BLE not supported"))
                state.state = nil
            case .resetting, .unknown:
                break // Wait for final state
            @unknown default:
                break
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        continuationLock.withLock { state in
            // If we have a target address, match against it
            if let targetAddress = state.targetAddress {
                if peripheral.identifier.uuidString == targetAddress {
                    central.stopScan()
                    state.scan?.resume(returning: peripheral)
                    state.scan = nil
                    state.targetAddress = nil
                }
            } else if let name = peripheral.name, name.hasPrefix("MeshCore") {
                // Default: match by name prefix
                central.stopScan()
                state.scan?.resume(returning: peripheral)
                state.scan = nil
            }
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        continuationLock.withLock { state in
            state.connect?.resume()
            state.connect = nil
        }
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        continuationLock.withLock { state in
            state.connect?.resume(throwing: error ?? MeshTransportError.connectionFailed("Unknown"))
            state.connect = nil
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        disconnectionContinuation.yield(())
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        continuationLock.withLock { state in
            if let error = error {
                state.discovery?.resume(throwing: error)
                state.discovery = nil
                return
            }
            guard let service = peripheral.services?.first(where: { $0.uuid == UARTUUID.service }) else {
                state.discovery?.resume(throwing: MeshTransportError.serviceNotFound)
                state.discovery = nil
                return
            }
            peripheral.discoverCharacteristics([UARTUUID.rx, UARTUUID.tx], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        continuationLock.withLock { state in
            if let error = error {
                state.discovery?.resume(throwing: error)
                state.discovery = nil
                return
            }
            guard let chars = service.characteristics,
                  let rxChar = chars.first(where: { $0.uuid == UARTUUID.rx }),
                  let txChar = chars.first(where: { $0.uuid == UARTUUID.tx }) else {
                state.discovery?.resume(throwing: MeshTransportError.characteristicNotFound)
                state.discovery = nil
                return
            }
            state.discovery?.resume(returning: (service, txChar, rxChar))
            state.discovery = nil
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let data = characteristic.value {
            dataContinuation.yield(data)
        }
    }
}
