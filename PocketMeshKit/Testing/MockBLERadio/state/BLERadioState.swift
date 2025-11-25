import Foundation
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh.mock", category: "RadioState")

/// Thread-safe state actor for mock radio
public actor BLERadioState {
    // Connection state
    private(set) var connectionState: RadioConnectionState = .disconnected
    private(set) var advertisingMode: AdvertisingMode = .connectable
    private(set) var mtu: Int = RadioConstants.defaultMTU

    // Offline queue (matches firmware)
    private var offlineQueue: [OfflineQueueEntry] = []

    // Expected ACK table (matches firmware)
    private var expectedAcks: [ExpectedAckEntry] = []
    private var nextAckIndex: Int = 0

    // Device info (from CMD_DEVICE_QUERY response)
    private(set) var deviceInfo: DeviceInfo

    // Self info (from CMD_APP_START response)
    private(set) var selfInfo: SelfInfo

    public init(deviceInfo: DeviceInfo, selfInfo: SelfInfo) {
        self.deviceInfo = deviceInfo
        self.selfInfo = selfInfo
    }

    // MARK: - Connection State

    public func setConnectionState(_ state: RadioConnectionState) {
        logger.info("Connection state: \(String(describing: self.connectionState)) → \(String(describing: state))")
        connectionState = state
    }

    public func setMTU(_ mtu: Int) {
        logger.debug("MTU updated: \(self.mtu) → \(mtu)")
        self.mtu = mtu
    }

    // MARK: - Offline Queue

    public func enqueueOfflineFrame(_ frame: RadioFrame) throws {
        // Match firmware behavior: evict oldest channel message if queue full
        if offlineQueue.count >= RadioConstants.offlineQueueSize {
            if let channelMsgIndex = offlineQueue.firstIndex(where: { $0.isChannelMsg() }) {
                logger.warning("Offline queue full, evicting oldest channel message at index \(channelMsgIndex)")
                offlineQueue.remove(at: channelMsgIndex)
            } else {
                logger.error("Offline queue full, no channel messages to evict")
                throw RadioError.queueFull
            }
        }

        let entry = OfflineQueueEntry(frame: frame, timestamp: Date())
        offlineQueue.append(entry)
        logger.debug("Enqueued offline frame, queue length: \(self.offlineQueue.count)")
    }

    public func dequeueOfflineFrame() -> RadioFrame? {
        guard !offlineQueue.isEmpty else { return nil }
        let entry = offlineQueue.removeFirst()
        logger.debug("Dequeued offline frame, queue length: \(self.offlineQueue.count)")
        return entry.frame
    }

    public func offlineQueueLength() -> Int {
        offlineQueue.count
    }

    // MARK: - Expected ACK Tracking

    public func addExpectedAck(_ ackCode: UInt32, contactPublicKey: Data) {
        let entry = ExpectedAckEntry(
            ackCode: ackCode,
            timestamp: Date(),
            contactPublicKey: contactPublicKey,
        )

        // Circular buffer behavior (matches firmware)
        if expectedAcks.count < RadioConstants.expectedAckTableSize {
            expectedAcks.append(entry)
        } else {
            expectedAcks[nextAckIndex] = entry
            nextAckIndex = (nextAckIndex + 1) % RadioConstants.expectedAckTableSize
        }

        logger.debug("Added expected ACK: \(ackCode), table size: \(self.expectedAcks.count)")
    }

    public func checkExpectedAck(_ ackCode: UInt32) -> Data? {
        guard let index = expectedAcks.firstIndex(where: { $0.ackCode == ackCode }) else {
            return nil
        }

        let contactKey = expectedAcks[index].contactPublicKey
        // Clear the entry (matches firmware: expected_ack_table[i].ack = 0)
        expectedAcks.remove(at: index)
        logger.info("Matched expected ACK: \(ackCode)")
        return contactKey
    }
}
