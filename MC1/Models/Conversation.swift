import Foundation
import MC1Services

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
            return channel.displayName
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

    var notificationLevel: NotificationLevel {
        switch self {
        case .direct(let contact):
            return contact.isMuted ? .muted : .all
        case .channel(let channel):
            return channel.notificationLevel
        case .room(let session):
            return session.notificationLevel
        }
    }

    var isMuted: Bool {
        notificationLevel == .muted
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

}
