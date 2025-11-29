import Combine
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh.mock", category: "RXChar")

/// Mock RX characteristic (UUID: 6E400003-B5A3-F393-E0A9-E50E24DCCA9E)
/// Handles notifications to central (radio → app)
public actor RXCharacteristic: BLECharacteristicProtocol {
    public nonisolated let uuid: UUID
    public nonisolated let properties: BLECharacteristicProperties = [.read, .notify]
    public nonisolated(unsafe) var value: Data?
    public nonisolated(unsafe) var isNotifying: Bool = false

    // Replace Combine PassthroughSubject with AsyncStream
    // Use bounded buffering to prevent memory issues in high-volume tests
    private let (rxStream, rxContinuation) = AsyncStream<Data>.makeStream(
        bufferingPolicy: .bufferingNewest(10)
    )
    public nonisolated var notificationStream: AsyncStream<Data> { rxStream }

    // Keep Combine publisher for backward compatibility during transition
    private nonisolated(unsafe) let notificationSubject = PassthroughSubject<Data, Never>()
    public nonisolated var notificationPublisher: AnyPublisher<Data, Never> {
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
        return self.value
    }

    /// Send notification to central (called by radio to send responses)
    public func sendNotification(_ data: Data) async {
        guard isNotifying else {
            logger.warning("Cannot send notification, notifications disabled")
            return
        }

        logger.debug("RX notify: \(data.count) bytes")
        // Note: value/isNotifying are nonisolated(unsafe) - safe for test isolation
        // but audit if using in production mocks
        value = data

        // Send via AsyncStream for proper async integration
        await rxContinuation.yield(data)

        // Also send via Combine for backward compatibility during transition
        notificationSubject.send(data)
    }

    deinit {
        // Properly clean up AsyncStream continuation
        rxContinuation.finish()
    }
}
