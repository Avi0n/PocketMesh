import Foundation
import PocketMeshServices

/// Represents a conversation in the chat list - direct chat, channel, or room
enum Conversation: Identifiable, Hashable {
    case direct(ContactDTO)
    case channel(ChannelDTO)
    case room(RemoteNodeSessionDTO)

    var id: UUID {
        switch self {
        case .direct(let contact):
            return contact.id
        case .channel(let channel):
            return channel.id
        case .room(let session):
            return session.id
        }
    }

    var displayName: String {
        switch self {
        case .direct(let contact):
            return contact.displayName
        case .channel(let channel):
            return channel.name.isEmpty ? "Channel \(channel.index)" : channel.name
        case .room(let session):
            return session.name
        }
    }

    var lastMessageDate: Date? {
        switch self {
        case .direct(let contact):
            return contact.lastMessageDate
        case .channel(let channel):
            return channel.lastMessageDate
        case .room(let session):
            return session.lastMessageDate
        }
    }

    var unreadCount: Int {
        switch self {
        case .direct(let contact):
            return contact.unreadCount
        case .channel(let channel):
            return channel.unreadCount
        case .room(let session):
            return session.unreadCount
        }
    }

    var isMuted: Bool {
        switch self {
        case .direct(let contact):
            return contact.isMuted
        case .channel(let channel):
            return channel.isMuted
        case .room(let session):
            return session.isMuted
        }
    }

    var isFavorite: Bool {
        switch self {
        case .direct(let contact):
            return contact.isFavorite
        case .channel(let channel):
            return channel.isFavorite
        case .room(let session):
            return session.isFavorite
        }
    }

    var isChannel: Bool {
        if case .channel = self { return true }
        return false
    }

    var isRoom: Bool {
        if case .room = self { return true }
        return false
    }

    /// For channels, returns the channel index
    var channelIndex: UInt8? {
        if case .channel(let channel) = self {
            return channel.index
        }
        return nil
    }

    /// For direct chats, returns the contact
    var contact: ContactDTO? {
        if case .direct(let contact) = self {
            return contact
        }
        return nil
    }

    /// For channels, returns the channel
    var channel: ChannelDTO? {
        if case .channel(let channel) = self {
            return channel
        }
        return nil
    }

    /// For rooms, returns the session
    var roomSession: RemoteNodeSessionDTO? {
        if case .room(let session) = self {
            return session
        }
        return nil
    }
}
