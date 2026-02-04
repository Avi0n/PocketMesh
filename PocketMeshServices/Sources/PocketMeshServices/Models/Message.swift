import Foundation
import SwiftData

/// Message delivery status
public enum MessageStatus: Int, Sendable, Codable {
    case pending = 0
    case sending = 1
    case sent = 2
    case delivered = 3
    case failed = 4
    case retrying = 5
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
    #Index<Message>(
        [\.deviceID, \.channelIndex, \.timestamp],
        [\.contactID, \.containsSelfMention, \.mentionSeen],
        [\.deviceID, \.channelIndex, \.containsSelfMention, \.mentionSeen]
    )

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

    /// Signal-to-noise ratio in dB
    public var snr: Double?

    /// Path nodes for incoming messages (1 byte per hop, from RxLogEntry correlation)
    public var pathNodes: Data?

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
    public var heardRepeats: Int = 0

    /// Number of times this message has been sent (1 = original, 2+ = sent again)
    public var sendCount: Int = 1

    /// Current retry attempt (0 = first attempt, 1 = first retry, etc.)
    public var retryAttempt: Int = 0

    /// Maximum retry attempts configured for this message
    public var maxRetryAttempts: Int = 0

    /// Deduplication key for preventing duplicate incoming messages
    public var deduplicationKey: String?

    /// Link preview URL that was detected (nil if no URL in message)
    public var linkPreviewURL: String?

    /// Title from link metadata
    public var linkPreviewTitle: String?

    /// Preview image data (hero image)
    public var linkPreviewImageData: Data?

    /// Icon/favicon data
    public var linkPreviewIconData: Data?

    /// Whether fetch has been attempted (true = done, false = not yet tried)
    public var linkPreviewFetched: Bool = false

    /// Whether this incoming message contains a mention of the current user
    public var containsSelfMention: Bool = false

    /// Whether the user has scrolled to see this mention (for tracking unread mentions)
    public var mentionSeen: Bool = false

    /// Whether the timestamp was corrected due to sender clock being invalid
    public var timestampCorrected: Bool = false

    /// Original sender timestamp from the wire (for incoming messages when corrected).
    /// Used for reaction hash computation to ensure sender and receiver match.
    /// Nil when timestamp was not corrected or for outgoing messages.
    public var senderTimestamp: UInt32?

    /// Cached reaction summary for scroll performance
    /// Format: "👍:3,❤️:2,😂:1" (emoji:count pairs, ordered by count desc)
    public var reactionSummary: String?

    /// Heard repeats for this message (cascade delete)
    @Relationship(deleteRule: .cascade, inverse: \MessageRepeat.message)
    public var repeats: [MessageRepeat]?

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
        snr: Double? = nil,
        pathNodes: Data? = nil,
        senderKeyPrefix: Data? = nil,
        senderNodeName: String? = nil,
        isRead: Bool = false,
        replyToID: UUID? = nil,
        roundTripTime: UInt32? = nil,
        heardRepeats: Int = 0,
        sendCount: Int = 1,
        retryAttempt: Int = 0,
        maxRetryAttempts: Int = 0,
        deduplicationKey: String? = nil,
        linkPreviewURL: String? = nil,
        linkPreviewTitle: String? = nil,
        linkPreviewImageData: Data? = nil,
        linkPreviewIconData: Data? = nil,
        linkPreviewFetched: Bool = false,
        containsSelfMention: Bool = false,
        mentionSeen: Bool = false,
        timestampCorrected: Bool = false,
        senderTimestamp: UInt32? = nil,
        reactionSummary: String? = nil
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
        self.pathNodes = pathNodes
        self.senderKeyPrefix = senderKeyPrefix
        self.senderNodeName = senderNodeName
        self.isRead = isRead
        self.replyToID = replyToID
        self.roundTripTime = roundTripTime
        self.heardRepeats = heardRepeats
        self.sendCount = sendCount
        self.retryAttempt = retryAttempt
        self.maxRetryAttempts = maxRetryAttempts
        self.deduplicationKey = deduplicationKey
        self.linkPreviewURL = linkPreviewURL
        self.linkPreviewTitle = linkPreviewTitle
        self.linkPreviewImageData = linkPreviewImageData
        self.linkPreviewIconData = linkPreviewIconData
        self.linkPreviewFetched = linkPreviewFetched
        self.containsSelfMention = containsSelfMention
        self.mentionSeen = mentionSeen
        self.timestampCorrected = timestampCorrected
        self.senderTimestamp = senderTimestamp
        self.reactionSummary = reactionSummary
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

    /// Date representation of timestamp
    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
}

// MARK: - Sendable DTO

/// A sendable snapshot of Message for cross-actor transfers
public struct MessageDTO: Sendable, Equatable, Hashable, Identifiable {
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
    public let snr: Double?
    public let pathNodes: Data?
    public let senderKeyPrefix: Data?
    public let senderNodeName: String?
    public let isRead: Bool
    public let replyToID: UUID?
    public let roundTripTime: UInt32?
    public let heardRepeats: Int
    public let sendCount: Int
    public let retryAttempt: Int
    public let maxRetryAttempts: Int
    public let deduplicationKey: String?
    public let linkPreviewURL: String?
    public let linkPreviewTitle: String?
    public let linkPreviewImageData: Data?
    public let linkPreviewIconData: Data?
    public let linkPreviewFetched: Bool
    public let containsSelfMention: Bool
    public let mentionSeen: Bool
    public let timestampCorrected: Bool
    public let senderTimestamp: UInt32?
    public let reactionSummary: String?

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
        self.pathNodes = message.pathNodes
        self.senderKeyPrefix = message.senderKeyPrefix
        self.senderNodeName = message.senderNodeName
        self.isRead = message.isRead
        self.replyToID = message.replyToID
        self.roundTripTime = message.roundTripTime
        self.heardRepeats = message.heardRepeats
        self.sendCount = message.sendCount
        self.retryAttempt = message.retryAttempt
        self.maxRetryAttempts = message.maxRetryAttempts
        self.deduplicationKey = message.deduplicationKey
        self.linkPreviewURL = message.linkPreviewURL
        self.linkPreviewTitle = message.linkPreviewTitle
        self.linkPreviewImageData = message.linkPreviewImageData
        self.linkPreviewIconData = message.linkPreviewIconData
        self.linkPreviewFetched = message.linkPreviewFetched
        self.containsSelfMention = message.containsSelfMention
        self.mentionSeen = message.mentionSeen
        self.timestampCorrected = message.timestampCorrected
        self.senderTimestamp = message.senderTimestamp
        self.reactionSummary = message.reactionSummary
    }

    /// Memberwise initializer for creating DTOs directly
    public init(
        id: UUID,
        deviceID: UUID,
        contactID: UUID?,
        channelIndex: UInt8?,
        text: String,
        timestamp: UInt32,
        createdAt: Date,
        direction: MessageDirection,
        status: MessageStatus,
        textType: TextType,
        ackCode: UInt32?,
        pathLength: UInt8,
        snr: Double?,
        pathNodes: Data? = nil,
        senderKeyPrefix: Data?,
        senderNodeName: String?,
        isRead: Bool,
        replyToID: UUID?,
        roundTripTime: UInt32?,
        heardRepeats: Int,
        sendCount: Int = 1,
        retryAttempt: Int,
        maxRetryAttempts: Int,
        deduplicationKey: String? = nil,
        linkPreviewURL: String? = nil,
        linkPreviewTitle: String? = nil,
        linkPreviewImageData: Data? = nil,
        linkPreviewIconData: Data? = nil,
        linkPreviewFetched: Bool = false,
        containsSelfMention: Bool = false,
        mentionSeen: Bool = false,
        timestampCorrected: Bool = false,
        senderTimestamp: UInt32? = nil,
        reactionSummary: String? = nil
    ) {
        self.id = id
        self.deviceID = deviceID
        self.contactID = contactID
        self.channelIndex = channelIndex
        self.text = text
        self.timestamp = timestamp
        self.createdAt = createdAt
        self.direction = direction
        self.status = status
        self.textType = textType
        self.ackCode = ackCode
        self.pathLength = pathLength
        self.snr = snr
        self.pathNodes = pathNodes
        self.senderKeyPrefix = senderKeyPrefix
        self.senderNodeName = senderNodeName
        self.isRead = isRead
        self.replyToID = replyToID
        self.roundTripTime = roundTripTime
        self.heardRepeats = heardRepeats
        self.sendCount = sendCount
        self.retryAttempt = retryAttempt
        self.maxRetryAttempts = maxRetryAttempts
        self.deduplicationKey = deduplicationKey
        self.linkPreviewURL = linkPreviewURL
        self.linkPreviewTitle = linkPreviewTitle
        self.linkPreviewImageData = linkPreviewImageData
        self.linkPreviewIconData = linkPreviewIconData
        self.linkPreviewFetched = linkPreviewFetched
        self.containsSelfMention = containsSelfMention
        self.mentionSeen = mentionSeen
        self.timestampCorrected = timestampCorrected
        self.senderTimestamp = senderTimestamp
        self.reactionSummary = reactionSummary
    }

    public var isOutgoing: Bool {
        direction == .outgoing
    }

    public var isChannelMessage: Bool {
        channelIndex != nil
    }

    /// Timestamp to use for reaction hash computation.
    /// Uses original sender timestamp if available (for incoming messages with corrected timestamps),
    /// otherwise uses the stored timestamp.
    public var reactionTimestamp: UInt32 {
        senderTimestamp ?? timestamp
    }

    public var isPending: Bool {
        status == .pending || status == .sending
    }

    public var hasFailed: Bool {
        status == .failed
    }

    public var date: Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp))
    }

    /// Path nodes as hex strings for display (e.g., ["A3", "7F", "42"])
    public var pathNodesHex: [String] {
        guard let pathNodes else { return [] }
        return pathNodes.map { String(format: "%02X", $0) }
    }

    /// Path as arrow-separated string (e.g., "A3 → 7F → 42")
    public var pathString: String {
        pathNodesHex.joined(separator: " → ")
    }

    /// Path as comma-separated string for clipboard (e.g., "A3,7F,42")
    public var pathStringForClipboard: String {
        pathNodesHex.joined(separator: ",")
    }
}
