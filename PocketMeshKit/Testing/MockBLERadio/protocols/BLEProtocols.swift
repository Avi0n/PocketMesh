import Combine
import Foundation

/// Protocol defining BLE peripheral behavior (mimics CBPeripheral)
public protocol BLEPeripheralProtocol: AnyObject, Sendable {
    var identifier: UUID { get }
    var name: String? { get }
    var state: BLEConnectionState { get }

    func discoverServices(_ serviceUUIDs: [UUID]?) async throws
    func discoverCharacteristics(_ characteristicUUIDs: [UUID]?, for service: BLEServiceProtocol) async throws
    func readValue(for characteristic: BLECharacteristicProtocol) async throws -> Data
    func writeValue(_ data: Data, for characteristic: BLECharacteristicProtocol, type: BLEWriteType) async throws
    func setNotifyValue(_ enabled: Bool, for characteristic: BLECharacteristicProtocol) async throws
    func maximumWriteValueLength(for type: BLEWriteType) -> Int
}

/// Protocol defining BLE service behavior (mimics CBService)
public protocol BLEServiceProtocol: AnyObject, Sendable {
    var uuid: UUID { get }
    var characteristics: [BLECharacteristicProtocol]? { get }
}

/// Protocol defining BLE characteristic behavior (mimics CBCharacteristic)
public protocol BLECharacteristicProtocol: AnyObject, Sendable {
    var uuid: UUID { get }
    var properties: BLECharacteristicProperties { get }
    var value: Data? { get }
    var isNotifying: Bool { get }
}

/// Connection state enum
public enum BLEConnectionState: Sendable {
    case disconnected
    case connecting
    case connected
    case disconnecting
}

/// Write type enum
public enum BLEWriteType: Sendable {
    case withResponse
    case withoutResponse
}

/// Characteristic properties
public struct BLECharacteristicProperties: OptionSet, Sendable {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }

    public static let read = BLECharacteristicProperties(rawValue: 1 << 0)
    public static let write = BLECharacteristicProperties(rawValue: 1 << 1)
    public static let writeWithoutResponse = BLECharacteristicProperties(rawValue: 1 << 2)
    public static let notify = BLECharacteristicProperties(rawValue: 1 << 3)
    public static let indicate = BLECharacteristicProperties(rawValue: 1 << 4)
}

// MARK: - Mock BLE Manager

/// Mock BLE Manager for testing (conforms to BLEManagerProtocol)
@MainActor
public final class MockBLEManager: BLEManagerProtocol {
    private let radio: MockBLERadio
    private let frameSubject = PassthroughSubject<Data, Never>()
    private var cancellables = Set<AnyCancellable>()

    public var framePublisher: AnyPublisher<Data, Never> {
        frameSubject.eraseToAnyPublisher()
    }

    public init(radio: MockBLERadio) {
        self.radio = radio

        // Forward RX notifications to frame publisher
        radio.rxNotifications
            .sink { [weak self] frame in
                self?.frameSubject.send(frame)
            }
            .store(in: &cancellables)
    }

    public func send(frame: Data) async throws {
        // Write to TX characteristic via peripheral
        let peripheral = radio.peripheral
        let service = radio.radioService
        let txChar = service.txCharacteristic

        try await peripheral.writeValue(frame, for: txChar, type: .withoutResponse)
    }
}
