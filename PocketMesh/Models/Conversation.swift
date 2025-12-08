import Foundation
import PocketMeshKit

/// Represents a conversation in the chat list - either a direct chat or channel
enum Conversation: Identifiable, Hashable {
    case direct(ContactDTO)
    case channel(ChannelDTO)

    var id: UUID {
        switch self {
        case .direct(let contact):
            return contact.id
        case .channel(let channel):
            return channel.id
        }
    }

    var displayName: String {
        switch self {
        case .direct(let contact):
            return contact.displayName
        case .channel(let channel):
            return channel.name.isEmpty ? "Channel \(channel.index)" : channel.name
        }
    }

    var lastMessageDate: Date? {
        switch self {
        case .direct(let contact):
            return contact.lastMessageDate
        case .channel(let channel):
            return channel.lastMessageDate
        }
    }

    var unreadCount: Int {
        switch self {
        case .direct(let contact):
            return contact.unreadCount
        case .channel(let channel):
            return channel.unreadCount
        }
    }

    var isChannel: Bool {
        if case .channel = self { return true }
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
}
