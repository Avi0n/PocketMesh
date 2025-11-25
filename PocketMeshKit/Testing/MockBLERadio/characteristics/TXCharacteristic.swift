import Foundation
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh.mock", category: "TXChar")

/// Mock TX characteristic (UUID: 6E400002-B5A3-F393-E0A9-E50E24DCCA9E)
/// Handles writes from central (app → radio)
public final class TXCharacteristic: BLECharacteristicProtocol, @unchecked Sendable {
    public let uuid: UUID
    public let properties: BLECharacteristicProperties = [.write, .writeWithoutResponse]
    public private(set) var value: Data?
    public let isNotifying: Bool = false

    private let onWrite: @Sendable (Data) async -> Void

    public init(uuid: UUID, onWrite: @escaping @Sendable (Data) async -> Void) {
        self.uuid = uuid
        self.onWrite = onWrite
    }

    /// Handle write from central
    public func write(_ data: Data, type: BLEWriteType) async throws {
        logger.debug("TX write (\(type == .withResponse ? "response" : "no-response")): \(data.count) bytes")
        value = data
        await onWrite(data)
    }
}
