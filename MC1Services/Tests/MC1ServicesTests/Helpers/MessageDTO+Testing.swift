import Foundation
@testable import PocketMeshServices

extension MessageDTO {

    /// Creates a MessageDTO with sensible test defaults for a direct message.
    ///
    /// Usage:
    /// ```
    /// let message = MessageDTO.testDirectMessage(deviceID: myDeviceID, contactID: contactID)
    /// let failed = MessageDTO.testDirectMessage(deviceID: id, contactID: cID, status: .failed)
    /// ```
    static func testDirectMessage(
        id: UUID = UUID(),
        deviceID: UUID = UUID(),
        contactID: UUID = UUID(),
        text: String = "Test message",
        timestamp: UInt32 = UInt32(Date().timeIntervalSince1970),
        createdAt: Date = Date(),
        direction: MessageDirection = .outgoing,
        status: MessageStatus = .pending,
        textType: TextType = .plain,
        ackCode: UInt32? = nil,
        pathLength: UInt8 = 0,
        snr: Double? = nil,
        senderKeyPrefix: Data? = nil,
        isRead: Bool = false,
        replyToID: UUID? = nil,
        roundTripTime: UInt32? = nil,
        heardRepeats: Int = 0,
        sendCount: Int = 1,
        retryAttempt: Int = 0,
        maxRetryAttempts: Int = 0,
        containsSelfMention: Bool = false
    ) -> MessageDTO {
        MessageDTO(
            id: id,
            deviceID: deviceID,
            contactID: contactID,
            channelIndex: nil,
            text: text,
            timestamp: timestamp,
            createdAt: createdAt,
            direction: direction,
            status: status,
            textType: textType,
            ackCode: ackCode,
            pathLength: pathLength,
            snr: snr,
            senderKeyPrefix: senderKeyPrefix,
            senderNodeName: nil,
            isRead: isRead,
            replyToID: replyToID,
            roundTripTime: roundTripTime,
            heardRepeats: heardRepeats,
            sendCount: sendCount,
            retryAttempt: retryAttempt,
            maxRetryAttempts: maxRetryAttempts,
            containsSelfMention: containsSelfMention
        )
    }

    /// Creates a MessageDTO with sensible test defaults for a channel message.
    ///
    /// Usage:
    /// ```
    /// let message = MessageDTO.testChannelMessage(deviceID: myDeviceID, channelIndex: 0)
    /// ```
    static func testChannelMessage(
        id: UUID = UUID(),
        deviceID: UUID = UUID(),
        channelIndex: UInt8 = 0,
        text: String = "Test channel message",
        timestamp: UInt32 = UInt32(Date().timeIntervalSince1970),
        createdAt: Date = Date(),
        direction: MessageDirection = .outgoing,
        status: MessageStatus = .sent,
        textType: TextType = .plain,
        pathLength: UInt8 = 0,
        snr: Double? = nil,
        senderNodeName: String? = nil,
        isRead: Bool = false,
        heardRepeats: Int = 0,
        sendCount: Int = 1,
        containsSelfMention: Bool = false
    ) -> MessageDTO {
        MessageDTO(
            id: id,
            deviceID: deviceID,
            contactID: nil,
            channelIndex: channelIndex,
            text: text,
            timestamp: timestamp,
            createdAt: createdAt,
            direction: direction,
            status: status,
            textType: textType,
            ackCode: nil,
            pathLength: pathLength,
            snr: snr,
            senderKeyPrefix: nil,
            senderNodeName: senderNodeName,
            isRead: isRead,
            replyToID: nil,
            roundTripTime: nil,
            heardRepeats: heardRepeats,
            sendCount: sendCount,
            retryAttempt: 0,
            maxRetryAttempts: 0,
            containsSelfMention: containsSelfMention
        )
    }
}
