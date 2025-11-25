import Combine
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh.mock", category: "RXChar")

/// Mock RX characteristic (UUID: 6E400003-B5A3-F393-E0A9-E50E24DCCA9E)
/// Handles notifications to central (radio → app)
public final class RXCharacteristic: BLECharacteristicProtocol, @unchecked Sendable {
    public let uuid: UUID
    public let properties: BLECharacteristicProperties = [.read, .notify]
    public private(set) var value: Data?
    public private(set) var isNotifying: Bool = false

    private let notificationSubject = PassthroughSubject<Data, Never>()
    public var notificationPublisher: AnyPublisher<Data, Never> {
        notificationSubject.eraseToAnyPublisher()
    }

    public init(uuid: UUID) {
        self.uuid = uuid
    }

    /// Enable/disable notifications
    public func setNotifyValue(_ enabled: Bool) {
        logger.info("RX notifications \(enabled ? "enabled" : "disabled")")
        isNotifying = enabled
    }

    /// Read current value
    public func read() -> Data? {
        logger.debug("RX read: \(self.value?.count ?? 0) bytes")
        return value
    }

    /// Send notification to central (called by radio to send responses)
    public func sendNotification(_ data: Data) {
        guard isNotifying else {
            logger.warning("Cannot send notification, notifications disabled")
            return
        }

        logger.debug("RX notify: \(data.count) bytes")
        value = data
        notificationSubject.send(data)
    }
}
