import Foundation
import SwiftData

/// Represents a channel (group) for broadcast messaging.
/// Max number of channels depends on the device, with slot 0 being the public channel.
@Model
public final class Channel {
    /// Unique identifier
    @Attribute(.unique)
    public var id: UUID

    /// The device this channel belongs to
    public var deviceID: UUID

    /// Channel slot index
    public var index: UInt8

    /// Channel name
    public var name: String

    /// Channel secret (16 bytes, SHA-256 hashed from passphrase)
    public var secret: Data

    /// Whether this channel is enabled/active
    public var isEnabled: Bool

    /// Last message timestamp for this channel
    public var lastMessageDate: Date?

    /// Unread message count
    public var unreadCount: Int

    /// Unread mention count (mentions of current user not yet seen)
    public var unreadMentionCount: Int = 0

    /// Whether this channel's notifications are muted
    public var isMuted: Bool = false

    /// Whether this channel is marked as favorite
    public var isFavorite: Bool = false

    public init(
        id: UUID = UUID(),
        deviceID: UUID,
        index: UInt8,
        name: String,
        secret: Data = Data(repeating: 0, count: 16),
        isEnabled: Bool = true,
        lastMessageDate: Date? = nil,
        unreadCount: Int = 0,
        unreadMentionCount: Int = 0,
        isMuted: Bool = false,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.deviceID = deviceID
        self.index = index
        self.name = name
        self.secret = secret
        self.isEnabled = isEnabled
        self.lastMessageDate = lastMessageDate
        self.unreadCount = unreadCount
        self.unreadMentionCount = unreadMentionCount
        self.isMuted = isMuted
        self.isFavorite = isFavorite
    }

    /// Creates a Channel from a protocol ChannelInfo
    public convenience init(deviceID: UUID, from info: ChannelInfo) {
        self.init(
            deviceID: deviceID,
            index: info.index,
            name: info.name,
            secret: info.secret
        )
    }
}

// MARK: - Computed Properties

public extension Channel {
    /// Whether this is the public channel (slot 0)
    var isPublicChannel: Bool {
        index == 0
    }

    /// Whether this channel has a non-empty secret
    var hasSecret: Bool {
        !secret.allSatisfy { $0 == 0 }
    }

    /// Updates from a protocol ChannelInfo
    func update(from info: ChannelInfo) {
        self.name = info.name
        self.secret = info.secret
    }

    /// Converts to a protocol ChannelInfo
    func toChannelInfo() -> ChannelInfo {
        ChannelInfo(index: index, name: name, secret: secret)
    }
}

// MARK: - Sendable DTO

/// A sendable snapshot of Channel for cross-actor transfers
public struct ChannelDTO: Sendable, Equatable, Identifiable, Hashable {
    public let id: UUID
    public let deviceID: UUID
    public let index: UInt8
    public let name: String
    public let secret: Data
    public let isEnabled: Bool
    public let lastMessageDate: Date?
    public let unreadCount: Int
    public let unreadMentionCount: Int
    public let isMuted: Bool
    public let isFavorite: Bool

    public init(from channel: Channel) {
        self.id = channel.id
        self.deviceID = channel.deviceID
        self.index = channel.index
        self.name = channel.name
        self.secret = channel.secret
        self.isEnabled = channel.isEnabled
        self.lastMessageDate = channel.lastMessageDate
        self.unreadCount = channel.unreadCount
        self.unreadMentionCount = channel.unreadMentionCount
        self.isMuted = channel.isMuted
        self.isFavorite = channel.isFavorite
    }

    /// Memberwise initializer for creating DTOs directly
    public init(
        id: UUID,
        deviceID: UUID,
        index: UInt8,
        name: String,
        secret: Data,
        isEnabled: Bool,
        lastMessageDate: Date?,
        unreadCount: Int,
        unreadMentionCount: Int = 0,
        isMuted: Bool,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.deviceID = deviceID
        self.index = index
        self.name = name
        self.secret = secret
        self.isEnabled = isEnabled
        self.lastMessageDate = lastMessageDate
        self.unreadCount = unreadCount
        self.unreadMentionCount = unreadMentionCount
        self.isMuted = isMuted
        self.isFavorite = isFavorite
    }

    public var isPublicChannel: Bool {
        index == 0
    }

    public var hasSecret: Bool {
        !secret.allSatisfy { $0 == 0 }
    }
}
