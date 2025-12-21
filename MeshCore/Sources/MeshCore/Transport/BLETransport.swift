@preconcurrency import CoreBluetooth
import Foundation
import os

/// Nordic UART Service UUIDs (avoid string duplication)
private enum UARTUUID {
    static let service = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    static let rx = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")  // Write to device
    static let tx = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")  // Read from device
}

/// Implements a Bluetooth Low Energy transport for MeshCore devices.
///
/// `BLETransport` uses the Nordic UART Service (NUS) to provide a serial-like communication
/// channel over BLE. It manages the full lifecycle of a BLE connection, from scanning and
/// discovery to service and characteristic negotiation.
///
/// ## State Management
///
/// This implementation is an `actor`, ensuring that all mutable state (connection status,
/// peripheral references, and characteristics) is isolated and protected from concurrent
/// access. It uses modern Swift concurrency patterns, including `AsyncStream` for data
/// reception and checked continuations for bridging delegate-based callbacks to `async` methods.
///
/// ## Nordic UART Service (NUS)
///
/// The transport relies on two specific characteristics:
/// - **RX (Write)**: Used to send data packets to the MeshCore device.
/// - **TX (Notify)**: Used to receive data packets from the MeshCore device via notifications.
///
/// ## Example
///
/// ```swift
/// let transport = BLETransport()
/// try await transport.connect()
///
/// // Start listening for data
/// Task {
///     for await data in await transport.receivedData {
///         print("Received \(data.count) bytes")
///     }
/// }
///
/// // Send data
/// try await transport.send(Data([0x01, 0x02, 0x03]))
/// ```
public actor BLETransport: MeshTransport {

    private let logger = Logger(subsystem: "MeshCore", category: "BLETransport")

    private nonisolated let delegate: BLEDelegate
    private let address: String?
    private var peripheral: CBPeripheral?
    private var rxCharacteristic: CBCharacteristic?

    private let dataStream: AsyncStream<Data>
    private let dataContinuation: AsyncStream<Data>.Continuation

    /// The current connection state of the transport.
    public private(set) var isConnected = false
    
    /// The detailed connection state, including failure reasons.
    public private(set) var connectionState: ConnectionState = .disconnected

    /// An asynchronous stream of raw data received from the BLE device.
    public var receivedData: AsyncStream<Data> { dataStream }

    /// Initializes a new BLE transport.
    ///
    /// - Parameter address: An optional BLE peripheral identifier (UUID string). If provided,
    ///   the transport will attempt to connect only to that specific device. If `nil`, it scans
    ///   for any device advertising the Nordic UART Service with a name starting with "MeshCore".
    ///
    /// - Note: This transport does not handle automatic reconnection. Reconnection logic should
    ///   be implemented at a higher level (e.g., in ``MeshCoreSession``) by observing
    ///   `connectionState`.
    public init(address: String? = nil) {
        self.address = address

        let (stream, continuation) = AsyncStream.makeStream(of: Data.self)
        self.dataStream = stream
        self.dataContinuation = continuation

        self.delegate = BLEDelegate(dataContinuation: continuation)
    }

    /// Scans for and connects to a MeshCore BLE device.
    ///
    /// This method performs the following steps:
    /// 1. Waits for the Bluetooth hardware to be powered on.
    /// 2. Scans for peripherals matching the criteria (name prefix or address).
    /// 3. Connects to the discovered peripheral.
    /// 4. Discovers the Nordic UART Service and its characteristics.
    /// 5. Enables notifications on the TX characteristic.
    ///
    /// - Throws:
    ///   - ``MeshTransportError/connectionFailed(_:)`` if Bluetooth is unavailable or connection fails.
    ///   - ``MeshTransportError/deviceNotFound`` if no matching device is found within the timeout.
    ///   - ``MeshTransportError/serviceNotFound`` if the device does not support the NUS service.
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

    /// Disconnects from the current BLE device and stops all streaming.
    ///
    /// Closes the peripheral connection, updates the connection state, and finishes
    /// the data stream.
    public func disconnect() async {
        if let peripheral = peripheral {
            delegate.centralManager.cancelPeripheralConnection(peripheral)
        }
        isConnected = false
        connectionState = .disconnected
        dataContinuation.finish()
        logger.info("BLE disconnected")
    }

    /// Sends raw data to the device using the NUS RX characteristic.
    ///
    /// Data is sent using the `.withResponse` write type to ensure delivery.
    ///
    /// - Parameter data: The raw bytes to transmit.
    /// - Throws:
    ///   - ``MeshTransportError/notConnected`` if the transport is not currently connected.
    ///   - ``MeshTransportError/sendFailed(_:)`` if the write operation fails.
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

/// A private delegate class that handles CoreBluetooth callbacks and bridges them to Swift concurrency.
///
/// This class is internal to `BLETransport` and manages the complex interactions with `CBCentralManager`
/// and `CBPeripheral`. It uses thread-safe continuations to allow the actor to wait for BLE events
/// asynchronously.
///
/// - Note: Marked as `@unchecked Sendable` because it inherits from `NSObject` (as required by
///   BLE delegate protocols) but protects its mutable continuation state using `OSAllocatedUnfairLock`.
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
