import Foundation

/// Filter options for the Chats list view
enum ChatFilter: String, CaseIterable, Identifiable {
    case unread = "Unread"
    case directMessages = "DMs"
    case channels = "Channels"
    case favorites = "Favorites"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .unread: return "message.badge"
        case .directMessages: return "person"
        case .channels: return "number"
        case .favorites: return "star"
        }
    }
}
