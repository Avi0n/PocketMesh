import Foundation
import PocketMeshServices

/// Manages link preview fetching with throttling to prevent concurrent requests for the same message
@MainActor @Observable
final class LinkPreviewFetcher {
    private var inFlightFetches: Set<UUID> = []
    private let service = LinkPreviewService()
    private let preferences = LinkPreviewPreferences()

    /// Fetches link preview for a message if auto-resolve is enabled and not already fetching
    /// - Parameters:
    ///   - message: The message to fetch preview for
    ///   - isChannelMessage: Whether this is a channel message (for preference check)
    ///   - dataStore: Persistence store for saving preview data
    ///   - eventBroadcaster: Broadcaster for notifying views of the update
    func fetchIfNeeded(
        for message: MessageDTO,
        isChannelMessage: Bool,
        using dataStore: PersistenceStore,
        eventBroadcaster: MessageEventBroadcaster
    ) {
        guard preferences.shouldAutoResolve(isChannelMessage: isChannelMessage),
              !message.linkPreviewFetched,
              !inFlightFetches.contains(message.id) else {
            return
        }

        inFlightFetches.insert(message.id)

        Task {
            await service.fetchAndPersist(for: message, using: dataStore)
            inFlightFetches.remove(message.id)
            eventBroadcaster.handleLinkPreviewUpdated(messageID: message.id)
        }
    }

    /// Manually fetches link preview for a message (bypasses auto-resolve preference)
    /// - Parameters:
    ///   - message: The message to fetch preview for
    ///   - dataStore: Persistence store for saving preview data
    ///   - eventBroadcaster: Broadcaster for notifying views of the update
    func manualFetch(
        for message: MessageDTO,
        using dataStore: PersistenceStore,
        eventBroadcaster: MessageEventBroadcaster
    ) {
        guard !inFlightFetches.contains(message.id) else { return }

        inFlightFetches.insert(message.id)

        Task {
            await service.fetchAndPersist(for: message, using: dataStore)
            inFlightFetches.remove(message.id)
            eventBroadcaster.handleLinkPreviewUpdated(messageID: message.id)
        }
    }

    /// Checks if a fetch is currently in progress for a message
    func isFetching(_ messageID: UUID) -> Bool {
        inFlightFetches.contains(messageID)
    }
}
