import Foundation
import SwiftData
import CryptoKit

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

    /// Current retry attempt (0 = first attempt, 1 = first retry, etc.)
    public var retryAttempt: Int

    /// Maximum retry attempts configured for this message
    public var maxRetryAttempts: Int

    /// Deduplication key for preventing duplicate incoming messages
    public var deduplicationKey: String?

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
        senderKeyPrefix: Data? = nil,
        senderNodeName: String? = nil,
        isRead: Bool = false,
        replyToID: UUID? = nil,
        roundTripTime: UInt32? = nil,
        heardRepeats: Int = 0,
        retryAttempt: Int = 0,
        maxRetryAttempts: Int = 0,
        deduplicationKey: String? = nil
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
        self.retryAttempt = retryAttempt
        self.maxRetryAttempts = maxRetryAttempts
        self.deduplicationKey = deduplicationKey
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

// MARK: - Deduplication

public extension Message {
    /// Sentinel value for unknown sender in deduplication key
    static let unknownSenderSentinel = Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])

    /// Generate a stable deduplication key for a message.
    /// Uses SHA256 hash prefix for text content (stable across app executions).
    static func generateDeduplicationKey(
        timestamp: UInt32,
        senderKeyPrefix: Data?,
        text: String
    ) -> String {
        let senderHex = (senderKeyPrefix ?? unknownSenderSentinel).hex
        let contentHash = SHA256.hash(data: Data(text.utf8))
        let hashPrefix = contentHash.prefix(4).map { String(format: "%02x", $0) }.joined()
        return "\(timestamp)-\(senderHex)-\(hashPrefix)"
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
    public let senderKeyPrefix: Data?
    public let senderNodeName: String?
    public let isRead: Bool
    public let replyToID: UUID?
    public let roundTripTime: UInt32?
    public let heardRepeats: Int
    public let retryAttempt: Int
    public let maxRetryAttempts: Int
    public let deduplicationKey: String?

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
        self.senderNodeName = message.senderNodeName
        self.isRead = message.isRead
        self.replyToID = message.replyToID
        self.roundTripTime = message.roundTripTime
        self.heardRepeats = message.heardRepeats
        self.retryAttempt = message.retryAttempt
        self.maxRetryAttempts = message.maxRetryAttempts
        self.deduplicationKey = message.deduplicationKey
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
        senderKeyPrefix: Data?,
        senderNodeName: String?,
        isRead: Bool,
        replyToID: UUID?,
        roundTripTime: UInt32?,
        heardRepeats: Int,
        retryAttempt: Int,
        maxRetryAttempts: Int,
        deduplicationKey: String? = nil
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
        self.senderKeyPrefix = senderKeyPrefix
        self.senderNodeName = senderNodeName
        self.isRead = isRead
        self.replyToID = replyToID
        self.roundTripTime = roundTripTime
        self.heardRepeats = heardRepeats
        self.retryAttempt = retryAttempt
        self.maxRetryAttempts = maxRetryAttempts
        self.deduplicationKey = deduplicationKey
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

    public var date: Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
}
