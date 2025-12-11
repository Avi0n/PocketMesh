import Foundation
import SwiftData

/// Message delivery status
public enum MessageStatus: Int, Sendable, Codable {
    case pending = 0      // Queued locally, not yet sent
    case sending = 1      // Sent to device, awaiting ACK
    case sent = 2         // ACK received from device (message left device)
    case delivered = 3    // Delivery confirmed by recipient
    case failed = 4       // Failed after retries
    case read = 5         // Read by recipient (future use)
}

/// Message direction
public enum MessageDirection: Int, Sendable, Codable {
    case incoming = 0
    case outgoing = 1
}

/// Represents a message in a conversation.
/// Messages are stored per-device and associated with a contact or channel.
@Model
public final class Message {
    /// Unique message identifier
    @Attribute(.unique)
    public var id: UUID

    /// The device this message belongs to
    public var deviceID: UUID

    /// Contact ID for direct messages (nil for channel messages)
    public var contactID: UUID?

    /// Channel index for channel messages (nil for direct messages)
    public var channelIndex: UInt8?

    /// Message text content
    public var text: String

    /// Message timestamp (device time)
    public var timestamp: UInt32

    /// Local creation date
    public var createdAt: Date

    /// Direction (incoming/outgoing)
    public var directionRawValue: Int

    /// Delivery status
    public var statusRawValue: Int

    /// Text type (plain, signed, etc.)
    public var textTypeRawValue: UInt8

    /// ACK code for tracking delivery (outgoing only)
    public var ackCode: UInt32?

    /// Path length when received
    public var pathLength: UInt8

    /// Signal-to-noise ratio (scaled by 4)
    public var snr: Int8?

    /// Sender public key prefix (6 bytes, for incoming messages)
    public var senderKeyPrefix: Data?

    /// Sender node name (for channel messages, parsed from "NodeName: MessageText" format)
    public var senderNodeName: String?

    /// Whether this message has been read locally
    public var isRead: Bool

    /// Reply-to message ID (for threaded replies)
    public var replyToID: UUID?

    /// Round-trip time in ms (when ACK received)
    public var roundTripTime: UInt32?

    /// Count of mesh repeats heard for this message (outgoing only)
    public var heardRepeats: Int

    public init(
        id: UUID = UUID(),
        deviceID: UUID,
        contactID: UUID? = nil,
        channelIndex: UInt8? = nil,
        text: String,
        timestamp: UInt32 = 0,
        createdAt: Date = Date(),
        directionRawValue: Int = MessageDirection.outgoing.rawValue,
        statusRawValue: Int = MessageStatus.pending.rawValue,
        textTypeRawValue: UInt8 = TextType.plain.rawValue,
        ackCode: UInt32? = nil,
        pathLength: UInt8 = 0,
        snr: Int8? = nil,
        senderKeyPrefix: Data? = nil,
        senderNodeName: String? = nil,
        isRead: Bool = false,
        replyToID: UUID? = nil,
        roundTripTime: UInt32? = nil,
        heardRepeats: Int = 0
    ) {
        self.id = id
        self.deviceID = deviceID
        self.contactID = contactID
        self.channelIndex = channelIndex
        self.text = text
        self.timestamp = timestamp > 0 ? timestamp : UInt32(createdAt.timeIntervalSince1970)
        self.createdAt = createdAt
        self.directionRawValue = directionRawValue
        self.statusRawValue = statusRawValue
        self.textTypeRawValue = textTypeRawValue
        self.ackCode = ackCode
        self.pathLength = pathLength
        self.snr = snr
        self.senderKeyPrefix = senderKeyPrefix
        self.senderNodeName = senderNodeName
        self.isRead = isRead
        self.replyToID = replyToID
        self.roundTripTime = roundTripTime
        self.heardRepeats = heardRepeats
    }

    /// Creates an incoming message from a MessageFrame
    public convenience init(deviceID: UUID, contactID: UUID, from frame: MessageFrame) {
        self.init(
            deviceID: deviceID,
            contactID: contactID,
            text: frame.text,
            timestamp: frame.timestamp,
            directionRawValue: MessageDirection.incoming.rawValue,
            statusRawValue: MessageStatus.delivered.rawValue,
            textTypeRawValue: frame.textType.rawValue,
            pathLength: frame.pathLength,
            snr: frame.snr,
            senderKeyPrefix: frame.senderPublicKeyPrefix
        )
    }

    /// Creates an incoming channel message from a ChannelMessageFrame
    public convenience init(deviceID: UUID, from frame: ChannelMessageFrame) {
        self.init(
            deviceID: deviceID,
            channelIndex: frame.channelIndex,
            text: frame.text,  // Now contains parsed message text (without sender prefix)
            timestamp: frame.timestamp,
            directionRawValue: MessageDirection.incoming.rawValue,
            statusRawValue: MessageStatus.delivered.rawValue,
            textTypeRawValue: frame.textType.rawValue,
            pathLength: frame.pathLength,
            snr: frame.snr,
            senderNodeName: frame.senderNodeName  // NEW: Store parsed sender name
        )
    }
}

// MARK: - Computed Properties

public extension Message {
    /// Direction enum
    var direction: MessageDirection {
        MessageDirection(rawValue: directionRawValue) ?? .outgoing
    }

    /// Status enum
    var status: MessageStatus {
        get { MessageStatus(rawValue: statusRawValue) ?? .pending }
        set { statusRawValue = newValue.rawValue }
    }

    /// Text type enum
    var textType: TextType {
        TextType(rawValue: textTypeRawValue) ?? .plain
    }

    /// Whether this is an outgoing message
    var isOutgoing: Bool {
        direction == .outgoing
    }

    /// Whether this is a channel message
    var isChannelMessage: Bool {
        channelIndex != nil
    }

    /// Whether the message is still pending delivery
    var isPending: Bool {
        status == .pending || status == .sending
    }

    /// Whether the message failed to send
    var hasFailed: Bool {
        status == .failed
    }

    /// SNR as a readable float value
    var snrValue: Float? {
        guard let snr else { return nil }
        return Float(snr) / 4.0
    }

    /// Date representation of timestamp
    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
}

// MARK: - Sendable DTO

/// A sendable snapshot of Message for cross-actor transfers
public struct MessageDTO: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let deviceID: UUID
    public let contactID: UUID?
    public let channelIndex: UInt8?
    public let text: String
    public let timestamp: UInt32
    public let createdAt: Date
    public let direction: MessageDirection
    public let status: MessageStatus
    public let textType: TextType
    public let ackCode: UInt32?
    public let pathLength: UInt8
    public let snr: Int8?
    public let senderKeyPrefix: Data?
    public let senderNodeName: String?  // NEW - add after senderKeyPrefix
    public let isRead: Bool
    public let replyToID: UUID?
    public let roundTripTime: UInt32?
    public let heardRepeats: Int

    public init(from message: Message) {
        self.id = message.id
        self.deviceID = message.deviceID
        self.contactID = message.contactID
        self.channelIndex = message.channelIndex
        self.text = message.text
        self.timestamp = message.timestamp
        self.createdAt = message.createdAt
        self.direction = message.direction
        self.status = message.status
        self.textType = message.textType
        self.ackCode = message.ackCode
        self.pathLength = message.pathLength
        self.snr = message.snr
        self.senderKeyPrefix = message.senderKeyPrefix
        self.senderNodeName = message.senderNodeName  // NEW
        self.isRead = message.isRead
        self.replyToID = message.replyToID
        self.roundTripTime = message.roundTripTime
        self.heardRepeats = message.heardRepeats
    }

    public var isOutgoing: Bool {
        direction == .outgoing
    }

    public var isChannelMessage: Bool {
        channelIndex != nil
    }

    public var isPending: Bool {
        status == .pending || status == .sending
    }

    public var hasFailed: Bool {
        status == .failed
    }

    public var snrValue: Float? {
        guard let snr else { return nil }
        return Float(snr) / 4.0
    }

    public var date: Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
}
