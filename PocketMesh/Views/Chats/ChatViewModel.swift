import SwiftUI
import UIKit
import PocketMeshServices
import OSLog

/// ViewModel for chat operations
@Observable
@MainActor
final class ChatViewModel {

    // MARK: - Properties

    let logger = Logger(subsystem: "com.pocketmesh", category: "ChatViewModel")

    /// Current conversations (contacts with messages)
    var conversations: [ContactDTO] = []

    /// All contacts for mention autocomplete (includes contacts without messages)
    var allContacts: [ContactDTO] = []

    /// Synthetic contacts for channel senders not in contacts
    var channelSenders: [ContactDTO] = []

    /// O(1) lookup for channel sender names
    var channelSenderNames: Set<String> = []

    /// O(1) lookup for contact names
    var contactNameSet: Set<String> = []

    /// Current channels with messages
    var channels: [ChannelDTO] = []

    /// Current room sessions
    var roomSessions: [RemoteNodeSessionDTO] = []

    /// Combined conversations (contacts + channels + rooms) - favorites first
    var allConversations: [Conversation] {
        favoriteConversations + nonFavoriteConversations
    }

    /// Favorite conversations sorted by last message date
    var favoriteConversations: [Conversation] {
        rebuildConversationCacheIfNeeded()
        // Touch source arrays to maintain observation dependencies even when cache is valid.
        // Without this, SwiftUI won't track changes after initial render because
        // @ObservationIgnored cache properties don't register dependencies.
        _ = conversations.count
        _ = channels.count
        _ = roomSessions.count
        return cachedFavoriteConversations
    }

    /// Non-favorite conversations sorted by last message date
    var nonFavoriteConversations: [Conversation] {
        rebuildConversationCacheIfNeeded()
        // Touch source arrays to maintain observation dependencies
        _ = conversations.count
        _ = channels.count
        _ = roomSessions.count
        return cachedNonFavoriteConversations
    }

    // MARK: - Conversation Cache

    @ObservationIgnored private var cachedFavoriteConversations: [Conversation] = []
    @ObservationIgnored private var cachedNonFavoriteConversations: [Conversation] = []
    @ObservationIgnored private var conversationCacheValid = false

    /// Invalidates the conversation cache, forcing rebuild on next access
    func invalidateConversationCache() {
        conversationCacheValid = false
    }

    private func rebuildConversationCacheIfNeeded() {
        guard !conversationCacheValid else { return }

        let contactConversations = conversations
            .filter { $0.type != .repeater && !$0.isBlocked }
            .map { Conversation.direct($0) }
        let channelConversations = channels
            .filter { !$0.name.isEmpty || $0.hasSecret }
            .map { Conversation.channel($0) }
        let roomConversations = roomSessions.map { Conversation.room($0) }
        let all = contactConversations + channelConversations + roomConversations

        cachedFavoriteConversations = all
            .filter { $0.isFavorite }
            .sorted { ($0.lastMessageDate ?? .distantPast) > ($1.lastMessageDate ?? .distantPast) }
        cachedNonFavoriteConversations = all
            .filter { !$0.isFavorite }
            .sorted { ($0.lastMessageDate ?? .distantPast) > ($1.lastMessageDate ?? .distantPast) }

        conversationCacheValid = true
    }

    /// Messages for the current conversation
    var messages: [MessageDTO] = []

    /// Pre-computed display items for efficient cell rendering
    var displayItems: [MessageDisplayItem] = []

    /// O(1) message lookup by ID (used by views to get full DTO when needed)
    var messagesByID: [UUID: MessageDTO] = [:]

    /// O(1) display item index lookup by message ID
    var displayItemIndexByID: [UUID: Int] = [:]

    /// Current contact being chatted with
    var currentContact: ContactDTO?

    /// Current channel being viewed
    var currentChannel: ChannelDTO?

    /// Loading state
    var isLoading = false

    /// Whether data has been loaded at least once (prevents empty state flash)
    var hasLoadedOnce = false

    /// Error message if any
    var errorMessage: String?

    /// Whether to show retry error alert
    var showRetryError = false

    /// Message text being composed
    var composingText = ""

    /// A message waiting to be sent, with its target contact captured at enqueue time
    struct QueuedMessage {
        let messageID: UUID
        let contactID: UUID
    }

    /// Queue of message IDs waiting to be sent
    var sendQueue: [QueuedMessage] = []

    /// Whether the queue processor is running
    var isProcessingQueue = false

    /// Number of messages in the send queue (for testing)
    var sendQueueCount: Int { sendQueue.count }

    /// Last message previews cache
    var lastMessageCache: [UUID: MessageDTO] = [:]

    /// Store for recently used reaction emojis
    let recentEmojisStore = RecentEmojisStore()

    /// Preview state per message (keyed by message ID)
    var previewStates: [UUID: PreviewLoadState] = [:]

    /// Loaded preview data per message (keyed by message ID)
    var loadedPreviews: [UUID: LinkPreviewDataDTO] = [:]

    /// In-flight preview fetch tasks (prevents duplicate fetches)
    var previewFetchTasks: [UUID: Task<Void, Never>] = [:]

    /// Raw image data per message (keyed by message ID)
    var loadedImageData: [UUID: Data] = [:]

    /// Pre-decoded UIImage per message (avoids decoding in view body)
    var decodedImages: [UUID: UIImage] = [:]

    /// Whether each image message is a GIF (computed once during decode)
    var imageIsGIF: [UUID: Bool] = [:]

    /// In-flight image fetch tasks
    var imageFetchTasks: [UUID: Task<Void, Never>] = [:]

    /// In-flight reaction sends (prevents duplicate reactions on rapid taps)
    /// Key format: "{messageID}-{emoji}"
    var inFlightReactions: Set<String> = []

    // MARK: - Pagination State

    /// Whether currently fetching older messages (exposed for UI binding)
    var isLoadingOlder = false

    /// Whether more messages exist beyond what's loaded
    var hasMoreMessages = true

    /// Number of messages to fetch per page
    let pageSize = 50

    /// Total messages fetched from database (unfiltered, for accurate offset calculation)
    var totalFetchedCount = 0

    /// Message ID that should show the "New Messages" divider above it
    var newMessagesDividerMessageID: UUID?

    /// Whether the divider position has been computed for the current conversation
    var dividerComputed = false

    /// Minimum unread count before showing the "New Messages" divider
    private let newMessagesDividerMinUnreadCount = 10

    /// Computes the divider message ID from a fetched (unfiltered) message array.
    /// Must be called before filtering. Sets `dividerComputed = true`.
    func computeDividerPosition(from messages: [MessageDTO], unreadCount: Int) {
        guard !dividerComputed, unreadCount > newMessagesDividerMinUnreadCount else { return }
        let dividerIndex = max(0, messages.count - unreadCount)
        if dividerIndex < messages.count {
            newMessagesDividerMessageID = messages[dividerIndex].id
        }
        dividerComputed = true
    }

    // MARK: - Dependencies

    var dataStore: DataStore?
    var linkPreviewCache: (any LinkPreviewCaching)?
    var messageService: MessageService?
    var notificationService: NotificationService?
    var channelService: ChannelService?
    private var roomServerService: RoomServerService?
    var contactService: ContactService?
    var syncCoordinator: SyncCoordinator?
    weak var appState: AppState?

    /// Contact ID currently having its favorite status toggled (for loading UI)
    var togglingFavoriteID: UUID?

    // MARK: - Initialization

    init() {}

    /// Configure with services from AppState (with link preview cache for message views)
    func configure(appState: AppState, linkPreviewCache: any LinkPreviewCaching) {
        self.appState = appState
        self.dataStore = appState.offlineDataStore
        self.messageService = appState.services?.messageService
        self.notificationService = appState.services?.notificationService
        self.channelService = appState.services?.channelService
        self.roomServerService = appState.services?.roomServerService
        self.contactService = appState.services?.contactService
        self.syncCoordinator = appState.syncCoordinator
        self.linkPreviewCache = linkPreviewCache
    }

    /// Configure with services from AppState (for conversation list views that don't show previews)
    func configure(appState: AppState) {
        self.appState = appState
        self.dataStore = appState.offlineDataStore
        self.messageService = appState.services?.messageService
        self.notificationService = appState.services?.notificationService
        self.channelService = appState.services?.channelService
        self.roomServerService = appState.services?.roomServerService
        self.contactService = appState.services?.contactService
        self.syncCoordinator = appState.syncCoordinator
    }

    /// Configure with services (for testing)
    func configure(dataStore: DataStore, messageService: MessageService, linkPreviewCache: any LinkPreviewCaching) {
        self.dataStore = dataStore
        self.messageService = messageService
        self.linkPreviewCache = linkPreviewCache
    }

    // MARK: - Timestamp Helpers

    /// Time gap (in seconds) that breaks message grouping for timestamps and sender names.
    static let messageGroupingGapSeconds = 300

    /// Pre-computed display flags for a single message
    struct DisplayFlags {
        let showTimestamp: Bool
        let showDirectionGap: Bool
        let showSenderName: Bool
    }

    /// Computes all display flags in a single pass to avoid redundant message lookups.
    /// Used by buildDisplayItems() for O(n) performance instead of O(3n).
    static func computeDisplayFlags(for message: MessageDTO, previous: MessageDTO?) -> DisplayFlags {
        guard let previous else {
            // First message: show timestamp, no direction gap, show sender name
            return DisplayFlags(showTimestamp: true, showDirectionGap: false, showSenderName: true)
        }

        // Time gap calculation (shared by timestamp and sender name logic)
        let timeGap = abs(Int(message.timestamp) - Int(previous.timestamp))

        // Timestamp: gap > 5 minutes
        let showTimestamp = timeGap > messageGroupingGapSeconds

        // Direction gap: direction changed from previous
        let showDirectionGap = message.direction != previous.direction

        // Sender name grouping (channel messages only)
        let showSenderName: Bool
        if message.contactID != nil || message.isOutgoing {
            // Direct messages or outgoing: always true (UI ignores for direct messages anyway)
            showSenderName = true
        } else if previous.isOutgoing || timeGap > messageGroupingGapSeconds {
            // Direction change or time gap breaks group
            showSenderName = true
        } else if let currentName = message.senderNodeName, let previousName = previous.senderNodeName {
            // Same sender continues group
            showSenderName = currentName != previousName
        } else {
            // Malformed message: show name to be safe
            showSenderName = true
        }

        return DisplayFlags(showTimestamp: showTimestamp, showDirectionGap: showDirectionGap, showSenderName: showSenderName)
    }
}

// MARK: - Environment Key

private struct ChatViewModelKey: EnvironmentKey {
    static let defaultValue: ChatViewModel? = nil
}

extension EnvironmentValues {
    var chatViewModel: ChatViewModel? {
        get { self[ChatViewModelKey.self] }
        set { self[ChatViewModelKey.self] = newValue }
    }
}
