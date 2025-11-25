import Foundation

/// Mock Device Information Service (UUID: 180A)
/// Optional for advanced testing
public final class DeviceInformationService: BLEServiceProtocol, @unchecked Sendable {
    public let uuid: UUID
    public let characteristics: [BLECharacteristicProtocol]?

    public let manufacturerName: String
    public let modelNumber: String
    public let firmwareRevision: String

    public init(manufacturerName: String, modelNumber: String, firmwareRevision: String) {
        uuid = UUID(uuidString: "0000180A-0000-1000-8000-00805F9B34FB")!
        self.manufacturerName = manufacturerName
        self.modelNumber = modelNumber
        self.firmwareRevision = firmwareRevision
        characteristics = nil
    }
}
