import Combine
@preconcurrency import CoreBluetooth
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh.app", category: "BLE")

/// Protocol defining the BLE manager interface for testing and dependency injection
@preconcurrency
public protocol BLEManagerProtocol: AnyObject, Sendable {
    @MainActor var framePublisher: AnyPublisher<Data, Never> { get }
    @MainActor @preconcurrency func send(frame: Data) async throws
}

/// Manages CoreBluetooth central operations for MeshCore device connections
@MainActor
public final class BLEManager: NSObject, ObservableObject {
    // MARK: - Published State

    @Published public private(set) var state: BLEState = .idle
    @Published public private(set) var discoveredDevices: [MeshCoreDevice] = []
    @Published public private(set) var connectedDevice: MeshCoreDevice?

    // MARK: - Private Properties

    private var centralManager: CBCentralManager!
    private var activePeripheral: CBPeripheral?
    private var txCharacteristic: CBCharacteristic?
    private var rxCharacteristic: CBCharacteristic?

    // Add these new properties for state restoration
    private var restoredPeripherals: [CBPeripheral] = []
    private var isRestoringState = false

    // Protocol constants from MeshCore documentation
    private let meshCoreServiceUUID = CBUUID(string: "6E400001-B5A3-F393-E0A9-E50E24DCCA9E") // Nordic UART Service
    private let txCharacteristicUUID = CBUUID(string: "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    private let rxCharacteristicUUID = CBUUID(string: "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")

    private var dataBuffer = Data()
    private let frameSubject = PassthroughSubject<Data, Never>()

    // MARK: - Public Interface

    public var framePublisher: AnyPublisher<Data, Never> {
        frameSubject.eraseToAnyPublisher()
    }

    /// CoreBluetooth state preservation key
    public static let stateRestorationIdentifier = "com.pocketmesh.ble.central"

    override public init() {
        super.init()
        centralManager = CBCentralManager(
            delegate: self,
            queue: .main,
            options: [
                CBCentralManagerOptionRestoreIdentifierKey: Self.stateRestorationIdentifier,
                CBCentralManagerOptionShowPowerAlertKey: true,
            ],
        )
    }

    public func startScanning() {
        guard centralManager.state == .poweredOn else {
            logger.warning("Cannot scan - Bluetooth not powered on")
            state = .unauthorized
            return
        }

        logger.info("Starting BLE scan for MeshCore devices")
        discoveredDevices.removeAll()
        centralManager.scanForPeripherals(
            withServices: [meshCoreServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false],
        )
        state = .scanning
    }

    public func stopScanning() {
        centralManager.stopScan()
        if state == .scanning {
            state = .idle
        }
    }

    public func connect(to device: MeshCoreDevice) {
        guard let peripheral = device.peripheral else { return }

        logger.info("Connecting to device: \(device.name)")
        activePeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)
        state = .connecting
    }

    public func disconnect() {
        guard let peripheral = activePeripheral else { return }

        logger.info("Disconnecting from device")
        centralManager.cancelPeripheralConnection(peripheral)
    }

    public func send(frame: Data) async throws {
        guard let characteristic = txCharacteristic,
              let peripheral = activePeripheral,
              state == .connected
        else {
            throw BLEError.notConnected
        }

        // BLE write without response (per MeshCore protocol)
        let mtu = peripheral.maximumWriteValueLength(for: .withoutResponse)
        logger.debug("Writing frame of \(frame.count) bytes (MTU: \(mtu))")

        // Chunk if necessary (though protocol frames should fit in single write)
        if frame.count <= mtu {
            peripheral.writeValue(frame, for: characteristic, type: .withoutResponse)
        } else {
            // Chunked write for large frames
            for offset in stride(from: 0, to: frame.count, by: mtu) {
                let end = min(offset + mtu, frame.count)
                let chunk = frame.subdata(in: offset ..< end)
                peripheral.writeValue(chunk, for: characteristic, type: .withoutResponse)
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms between chunks
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEManager: CBCentralManagerDelegate {
    public nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                logger.info("Bluetooth powered on")
                state = .idle
            case .poweredOff:
                logger.warning("Bluetooth powered off")
                state = .unauthorized
            case .unauthorized:
                logger.error("Bluetooth unauthorized")
                state = .unauthorized
            case .unsupported:
                logger.error("Bluetooth unsupported on this device")
                state = .unauthorized
            default:
                state = .idle
            }
        }
    }

    public nonisolated func centralManager(
        _: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData _: [String: Any],
        rssi RSSI: NSNumber,
    ) {
        Task { @MainActor in
            let deviceName = peripheral.name ?? "Unknown MeshCore Device"

            // Check if already discovered
            guard !discoveredDevices.contains(where: { $0.id == peripheral.identifier }) else {
                return
            }

            let device = MeshCoreDevice(
                id: peripheral.identifier,
                name: deviceName,
                rssi: RSSI.intValue,
                peripheral: peripheral,
            )

            discoveredDevices.append(device)
            logger.info("Discovered device: \(deviceName) (RSSI: \(RSSI))")
        }
    }

    public nonisolated func centralManager(_: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            logger.info("Connected to peripheral: \(peripheral.name ?? "unknown")")
            state = .connected
            peripheral.discoverServices([meshCoreServiceUUID])
        }
    }

    public nonisolated func centralManager(
        _: CBCentralManager,
        didFailToConnect _: CBPeripheral,
        error: Error?,
    ) {
        Task { @MainActor in
            logger.error("Failed to connect: \(error?.localizedDescription ?? "unknown error")")
            state = .disconnected
            activePeripheral = nil
        }
    }

    public nonisolated func centralManager(
        _: CBCentralManager,
        didDisconnectPeripheral _: CBPeripheral,
        error: Error?,
    ) {
        Task { @MainActor in
            if let error {
                logger.error("Disconnected with error: \(error.localizedDescription)")
            } else {
                logger.info("Disconnected from peripheral")
            }
            state = .disconnected
            activePeripheral = nil
            connectedDevice = nil
            txCharacteristic = nil
            rxCharacteristic = nil
        }
    }

    /// Handle state restoration from system
    /// NOTE: This is called by CoreBluetooth on app launch if state was preserved
    public nonisolated func centralManager(
        _: CBCentralManager,
        willRestoreState dict: [String: Any],
    ) {
        // Log immediately outside of MainActor
        logger.info("BLE state restoration triggered")

        // Handle peripherals that were connected or connecting
        if let peripherals = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] {
            // Process each peripheral without capturing arrays across isolation boundary
            for peripheral in peripherals {
                Task { @MainActor in
                    self.isRestoringState = true

                    logger.info("Processing restored peripheral: \(peripheral.name ?? "unknown")")

                    peripheral.delegate = self

                    if peripheral.state == .connected {
                        logger.info(
                            "Peripheral '\(peripheral.name ?? "unknown")' already connected - rediscovering services",
                        )
                        self.activePeripheral = peripheral
                        self.state = .connected

                        // Rediscover services and characteristics
                        peripheral.discoverServices([self.meshCoreServiceUUID])

                    } else if peripheral.state == .connecting {
                        logger.info(
                            "Peripheral '\(peripheral.name ?? "unknown")' is connecting - waiting for connection",
                        )
                        self.activePeripheral = peripheral
                        self.state = .connecting
                    }

                    self.isRestoringState = false
                }
            }
        }

        // Handle scan state
        if let scanServices = dict[CBCentralManagerRestoredStateScanServicesKey] as? [CBUUID] {
            logger.info("Was scanning for services: \(scanServices)")
            // Don't auto-resume scanning - let user initiate
        }

        // Handle scan options
        if let scanOptions = dict[CBCentralManagerRestoredStateScanOptionsKey] as? [String: Any] {
            logger.debug("Scan options: \(scanOptions)")
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BLEManager: CBPeripheralDelegate {
    public nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error {
                logger.error("Service discovery failed: \(error.localizedDescription)")
                return
            }

            guard let service = peripheral.services?.first(where: { $0.uuid == meshCoreServiceUUID }) else {
                logger.error("MeshCore service not found")
                return
            }

            logger.info("Discovered MeshCore service, discovering characteristics")
            peripheral.discoverCharacteristics([txCharacteristicUUID, rxCharacteristicUUID], for: service)
        }
    }

    public nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?,
    ) {
        Task { @MainActor in
            if let error {
                logger.error("Characteristic discovery failed: \(error.localizedDescription)")
                return
            }

            guard let characteristics = service.characteristics else {
                logger.error("No characteristics found")
                return
            }

            // Find TX and RX characteristics
            for characteristic in characteristics {
                if characteristic.uuid == txCharacteristicUUID {
                    txCharacteristic = characteristic
                    logger.info("Found TX characteristic")
                } else if characteristic.uuid == rxCharacteristicUUID {
                    rxCharacteristic = characteristic
                    peripheral.setNotifyValue(true, for: characteristic)
                    logger.info("Found RX characteristic, enabled notifications")
                }
            }

            // Verify we have both characteristics
            if txCharacteristic != nil, rxCharacteristic != nil {
                state = .connected
                logger.info("BLE connection fully established\(self.isRestoringState ? " (restored)" : "")")

                // If this was a restoration, notify AppCoordinator to reinitialize services
                if self.isRestoringState {
                    // Post notification that connection was restored
                    NotificationCenter.default.post(
                        name: NSNotification.Name("BLEConnectionRestored"),
                        object: nil,
                    )
                }
            } else {
                logger.error("Missing required characteristics")
                disconnect()
            }
        }
    }

    public nonisolated func peripheral(
        _: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?,
    ) {
        let isNotifying = characteristic.isNotifying

        Task { @MainActor in
            if let error {
                logger.error("Notification state update failed: \(error.localizedDescription)")
            } else if isNotifying {
                logger.info("Notifications enabled for RX characteristic")
            }
        }
    }

    public nonisolated func peripheral(
        _: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?,
    ) {
        let value = characteristic.value

        Task { @MainActor in
            if let error {
                logger.error("Characteristic read failed: \(error.localizedDescription)")
                return
            }

            guard let data = value, !data.isEmpty else { return }

            logger.debug("Received \(data.count) bytes from RX characteristic")

            // BLE transport: each characteristic value is a complete frame
            // (no frame delimiters needed like USB)
            frameSubject.send(data)
        }
    }
}

// MARK: - Supporting Types

public enum BLEState {
    case idle
    case unauthorized
    case scanning
    case connecting
    case connected
    case disconnected
}

public enum BLEError: LocalizedError {
    case notConnected
    case characteristicNotFound
    case writeTimedOut

    public var errorDescription: String? {
        switch self {
        case .notConnected: "Not connected to a device"
        case .characteristicNotFound: "Required BLE characteristic not found"
        case .writeTimedOut: "Write operation timed out"
        }
    }
}

// MARK: - BLEManagerProtocol Conformance

extension BLEManager: BLEManagerProtocol {}

public struct MeshCoreDevice: Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let rssi: Int
    public weak var peripheral: CBPeripheral?

    public static func == (lhs: MeshCoreDevice, rhs: MeshCoreDevice) -> Bool {
        lhs.id == rhs.id
    }
}
