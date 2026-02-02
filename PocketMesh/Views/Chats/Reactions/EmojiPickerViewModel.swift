import Foundation
import Observation

/// View model for the emoji picker sheet
@MainActor
@Observable
final class EmojiPickerViewModel {
    private let provider = EmojiProvider()

    var searchQuery: String = "" {
        didSet {
            Task {
                await updateCategories()
            }
        }
    }

    private(set) var categories: [EmojiCategoryData] = []

    func load() async {
        await updateCategories()
    }

    func markAsFrequentlyUsed(_ emoji: String) {
        provider.markAsFrequentlyUsed(emoji)
    }

    private func updateCategories() async {
        let query = searchQuery.isEmpty ? nil : searchQuery
        categories = await provider.categories(searchQuery: query)
    }
}
