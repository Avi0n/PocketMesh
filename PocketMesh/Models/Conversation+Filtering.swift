import Foundation

extension Array where Element == Conversation {
    /// Filters conversations by category and search text
    /// - Parameters:
    ///   - filter: Optional filter category (nil = show all)
    ///   - searchText: Search string to match against display names
    /// - Returns: Filtered array of conversations
    func filtered(by filter: ChatFilter?, searchText: String) -> [Conversation] {
        let categoryFiltered: [Conversation]
        switch filter {
        case .none:
            categoryFiltered = self
        case .unread:
            categoryFiltered = self.filter { $0.unreadCount > 0 && !$0.isMuted }
        case .directMessages:
            categoryFiltered = self.filter {
                if case .direct = $0 { return true }
                return false
            }
        case .channels:
            categoryFiltered = self.filter {
                if case .channel = $0 { return true }
                if case .room = $0 { return true }
                return false
            }
        case .favorites:
            categoryFiltered = self.filter { $0.isFavorite }
        }

        if searchText.isEmpty {
            return categoryFiltered
        }
        return categoryFiltered.filter { conversation in
            conversation.displayName.localizedStandardContains(searchText)
        }
    }
}
