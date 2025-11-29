import Combine
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh.mock", category: "Peripheral")

/// Mock BLE peripheral implementing BLEPeripheralProtocol
public actor MockBLEPeripheral: @preconcurrency BLEPeripheralProtocol {
    public nonisolated let identifier: UUID
    public nonisolated let name: String?

    // State backing storage - synchronous access for protocol conformance
    private let _stateBox: StateBox

    // Nonisolated property for protocol conformance
    public nonisolated var state: BLEConnectionState {
        _stateBox.state
    }

    // Internal helper class for thread-safe state access
    private final class StateBox: @unchecked Sendable {
        private let lock = NSLock()
        private var _state: BLEConnectionState = .disconnected

        var state: BLEConnectionState {
            get {
                lock.lock()
                defer { lock.unlock() }
                return _state
            }
            set {
                lock.lock()
                defer { lock.unlock() }
                _state = newValue
            }
        }
    }

    private let radioService: RadioService
    private var services: [BLEServiceProtocol] = []
    private var mtu: Int = RadioConstants.defaultMTU
    private let config: MockRadioConfig
    private var frameCounter: Int = 0

    public init(
        identifier: UUID = UUID(),
        name: String?,
        radioService: RadioService,
        config: MockRadioConfig = .default,
    ) {
        self.identifier = identifier
        self.name = name
        self._stateBox = StateBox()
        self.radioService = radioService
        self.services = [radioService]
        self.config = config

        logger.info("Mock peripheral created: \(name ?? "unknown")")
    }

    // MARK: - BLEPeripheralProtocol

    public func discoverServices(_ serviceUUIDs: [UUID]?) async throws {
        logger.debug("Discovering services: \(serviceUUIDs?.map(\.uuidString) ?? ["all"])")
        // Services already populated in init
    }

    public func discoverCharacteristics(
        _: [UUID]?,
        for service: BLEServiceProtocol,
    ) async throws {
        logger.debug("Discovering characteristics for service: \(service.uuid.uuidString)")
        // Characteristics already populated in RadioService init
    }

    public func readValue(for characteristic: BLECharacteristicProtocol) async throws -> Data {
        guard characteristic.properties.contains(.read) else {
            throw RadioError.characteristicNotFound
        }

        // Only RX characteristic supports read
        if let rxChar = characteristic as? RXCharacteristic {
            return await rxChar.read() ?? Data()
        }

        throw RadioError.characteristicNotFound
    }

    public func writeValue(
        _ data: Data,
        for characteristic: BLECharacteristicProtocol,
        type: BLEWriteType,
    ) async throws {
        guard characteristic.properties.contains(
            type == .withResponse ? .write : .writeWithoutResponse,
        ) else {
            throw RadioError.characteristicNotFound
        }

        // Apply packet loss simulation
        if config.packetLossRate > 0, Double.random(in: 0 ... 1) < config.packetLossRate {
            logger.warning("Simulated packet loss, dropping write")
            return
        }

        // Apply random delay simulation
        if config.maxRandomDelay > 0 {
            let delay = Double.random(in: 0 ... config.maxRandomDelay)
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }

        // Handle disconnect simulation
        if let disconnectAfter = config.disconnectAfterFrames {
            frameCounter += 1
            if frameCounter >= disconnectAfter {
                logger.warning("Simulated disconnect after \(self.frameCounter) frames")
                _stateBox.state = .disconnected
                throw RadioError.notConnected
            }
        }

        // Forward to TX characteristic
        if let txChar = characteristic as? TXCharacteristic {
            try await txChar.write(data, type: type)
        } else {
            throw RadioError.characteristicNotFound
        }
    }

    public func setNotifyValue(
        _ enabled: Bool,
        for characteristic: BLECharacteristicProtocol,
    ) async throws {
        guard characteristic.properties.contains(.notify) else {
            throw RadioError.characteristicNotFound
        }

        if let rxChar = characteristic as? RXCharacteristic {
            await rxChar.setNotifyValue(enabled)
        } else {
            throw RadioError.characteristicNotFound
        }
    }

    public nonisolated func maximumWriteValueLength(for _: BLEWriteType) -> Int {
        config.forcedMTU ?? RadioConstants.defaultMTU
    }

    // MARK: - Connection Management

    public func connect() {
        logger.info("Connecting peripheral")
        _stateBox.state = .connecting

        // Simulate async connection
        Task {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            await self.setStateConnected()
            logger.info("Peripheral connected")
        }
    }

    private func setStateConnected() {
        _stateBox.state = .connected
    }

    public func disconnect() {
        logger.info("Disconnecting peripheral")
        _stateBox.state = .disconnecting

        Task {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            await self.setStateDisconnected()
            logger.info("Peripheral disconnected")
        }
    }

    private func setStateDisconnected() {
        _stateBox.state = .disconnected
    }

    public func setMTU(_ mtu: Int) {
        self.mtu = mtu
        logger.debug("MTU set to \(mtu)")
    }

    // MARK: - Test Control

    public func simulateDisconnectWithError() {
        logger.warning("Simulating unexpected disconnect")
        _stateBox.state = .disconnected
    }
}
