import Foundation

/// Mock Nordic UART Service (UUID: 6E400001-B5A3-F393-E0A9-E50E24DCCA9E)
public final class RadioService: BLEServiceProtocol, @unchecked Sendable {
    public let uuid: UUID
    public let characteristics: [BLECharacteristicProtocol]?

    public let txCharacteristic: TXCharacteristic
    public let rxCharacteristic: RXCharacteristic

    public init(
        uuid: UUID,
        txUUID: UUID,
        rxCharacteristic: RXCharacteristic,
        onTXWrite: @escaping @Sendable (Data) async -> Void,
    ) {
        self.uuid = uuid
        self.txCharacteristic = TXCharacteristic(uuid: txUUID, onWrite: onTXWrite)
        self.rxCharacteristic = rxCharacteristic
        self.characteristics = [txCharacteristic, rxCharacteristic]
    }
}
