import Foundation

/// Filter options for the Chats list view
enum ChatFilter: String, CaseIterable, Identifiable {
    case unread
    case directMessages
    case channels
    case favorites

    var id: String { rawValue }

    var localizedName: String {
        switch self {
        case .unread: L10n.Chats.Chats.Filter.unread
        case .directMessages: L10n.Chats.Chats.Filter.directMessages
        case .channels: L10n.Chats.Chats.Filter.channels
        case .favorites: L10n.Chats.Chats.Filter.favorites
        }
    }

    var systemImage: String {
        switch self {
        case .unread: "message.badge"
        case .directMessages: "person"
        case .channels: "number"
        case .favorites: "star"
        }
    }
}
