import CryptoKit
import Foundation
import SwiftData

/// Represents a message in a room server conversation.
@Model
public final class RoomMessage {
    /// Unique message identifier
    @Attribute(.unique)
    public var id: UUID

    /// References RemoteNodeSession.id
    public var sessionID: UUID

    /// 4-byte original author's public key prefix from server push
    public var authorKeyPrefix: Data

    /// Resolved author name (from contacts or nil)
    public var authorName: String?

    /// Message text content
    public var text: String

    /// Message timestamp (server time)
    public var timestamp: UInt32

    /// Local creation date
    public var createdAt: Date

    /// Whether this message was posted by the current user
    public var isFromSelf: Bool

    /// Deduplication key combining timestamp, author, and content hash
    /// Format: "\(timestamp)-\(authorPrefixHex)-\(contentHashPrefix)"
    public var deduplicationKey: String

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        authorKeyPrefix: Data,
        authorName: String? = nil,
        text: String,
        timestamp: UInt32,
        isFromSelf: Bool = false
    ) {
        self.id = id
        self.sessionID = sessionID
        self.authorKeyPrefix = authorKeyPrefix
        self.authorName = authorName
        self.text = text
        self.timestamp = timestamp
        self.createdAt = Date()
        self.isFromSelf = isFromSelf
        self.deduplicationKey = Self.generateDeduplicationKey(
            timestamp: timestamp,
            authorKeyPrefix: authorKeyPrefix,
            text: text
        )
    }
}

// MARK: - Computed Properties

public extension RoomMessage {
    /// Display name for author (resolved name or hex prefix)
    var authorDisplayName: String {
        authorName ?? authorKeyPrefix.map { String(format: "%02X", $0) }.joined()
    }

    /// Date representation of timestamp
    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
}

// MARK: - Deduplication

public extension RoomMessage {
    /// Generate a deduplication key for message uniqueness.
    /// Uses timestamp + author prefix + first 8 chars of content hash.
    static func generateDeduplicationKey(
        timestamp: UInt32,
        authorKeyPrefix: Data,
        text: String
    ) -> String {
        let authorHex = authorKeyPrefix.map { String(format: "%02X", $0) }.joined()
        let contentHash = SHA256.hash(data: Data(text.utf8))
        let hashPrefix = contentHash.prefix(4).map { String(format: "%02X", $0) }.joined()
        return "\(timestamp)-\(authorHex)-\(hashPrefix)"
    }
}

// MARK: - Sendable DTO

/// A sendable snapshot of RoomMessage for cross-actor transfers
public struct RoomMessageDTO: Sendable, Equatable, Identifiable, Hashable {
    public let id: UUID
    public let sessionID: UUID
    public let authorKeyPrefix: Data
    public let authorName: String?
    public let text: String
    public let timestamp: UInt32
    public let createdAt: Date
    public let isFromSelf: Bool
    public let deduplicationKey: String

    public init(from model: RoomMessage) {
        self.id = model.id
        self.sessionID = model.sessionID
        self.authorKeyPrefix = model.authorKeyPrefix
        self.authorName = model.authorName
        self.text = model.text
        self.timestamp = model.timestamp
        self.createdAt = model.createdAt
        self.isFromSelf = model.isFromSelf
        self.deduplicationKey = model.deduplicationKey
    }

    public init(
        id: UUID = UUID(),
        sessionID: UUID,
        authorKeyPrefix: Data,
        authorName: String? = nil,
        text: String,
        timestamp: UInt32,
        createdAt: Date = Date(),
        isFromSelf: Bool = false
    ) {
        self.id = id
        self.sessionID = sessionID
        self.authorKeyPrefix = authorKeyPrefix
        self.authorName = authorName
        self.text = text
        self.timestamp = timestamp
        self.createdAt = createdAt
        self.isFromSelf = isFromSelf
        self.deduplicationKey = RoomMessage.generateDeduplicationKey(
            timestamp: timestamp,
            authorKeyPrefix: authorKeyPrefix,
            text: text
        )
    }

    public var authorDisplayName: String {
        authorName ?? authorKeyPrefix.map { String(format: "%02X", $0) }.joined()
    }

    public var date: Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp))
    }
}
