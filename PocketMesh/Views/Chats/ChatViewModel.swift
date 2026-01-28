import SwiftUI
import PocketMeshServices
import OSLog

/// ViewModel for chat operations
@Observable
@MainActor
final class ChatViewModel {

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.pocketmesh", category: "ChatViewModel")

    /// Current conversations (contacts with messages)
    var conversations: [ContactDTO] = []

    /// All contacts for mention autocomplete (includes contacts without messages)
    var allContacts: [ContactDTO] = []

    /// Synthetic contacts for channel senders not in contacts
    var channelSenders: [ContactDTO] = []

    /// O(1) lookup for channel sender names
    private var channelSenderNames: Set<String> = []

    /// O(1) lookup for contact names
    private var contactNameSet: Set<String> = []

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
    private(set) var displayItems: [MessageDisplayItem] = []

    /// O(1) message lookup by ID (used by views to get full DTO when needed)
    private(set) var messagesByID: [UUID: MessageDTO] = [:]

    /// O(1) display item index lookup by message ID
    private var displayItemIndexByID: [UUID: Int] = [:]

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
    private struct QueuedMessage {
        let messageID: UUID
        let contactID: UUID
    }

    /// Queue of message IDs waiting to be sent
    private var sendQueue: [QueuedMessage] = []

    /// Whether the queue processor is running
    private(set) var isProcessingQueue = false

    /// Number of messages in the send queue (for testing)
    var sendQueueCount: Int { sendQueue.count }

    /// Last message previews cache
    private var lastMessageCache: [UUID: MessageDTO] = [:]

    /// Preview state per message (keyed by message ID)
    private var previewStates: [UUID: PreviewLoadState] = [:]

    /// Loaded preview data per message (keyed by message ID)
    private var loadedPreviews: [UUID: LinkPreviewDataDTO] = [:]

    /// In-flight preview fetch tasks (prevents duplicate fetches)
    private var previewFetchTasks: [UUID: Task<Void, Never>] = [:]

    // MARK: - Pagination State

    /// Whether currently fetching older messages (exposed for UI binding)
    private(set) var isLoadingOlder = false

    /// Whether more messages exist beyond what's loaded
    private var hasMoreMessages = true

    /// Number of messages to fetch per page
    private let pageSize = 50

    /// Cached blocked contact names for channel filtering (set during initial load)
    private var cachedBlockedNames: Set<String> = []

    /// Total messages fetched from database (unfiltered, for accurate offset calculation)
    private var totalFetchedCount = 0

    // MARK: - Dependencies

    private var dataStore: DataStore?
    private var linkPreviewCache: (any LinkPreviewCaching)?
    private var messageService: MessageService?
    private var notificationService: NotificationService?
    private var channelService: ChannelService?
    private var roomServerService: RoomServerService?
    private var syncCoordinator: SyncCoordinator?
    private weak var appState: AppState?

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
        self.syncCoordinator = appState.syncCoordinator
    }

    /// Configure with services (for testing)
    func configure(dataStore: DataStore, messageService: MessageService, linkPreviewCache: any LinkPreviewCaching) {
        self.dataStore = dataStore
        self.messageService = messageService
        self.linkPreviewCache = linkPreviewCache
    }

    // MARK: - Mute

    /// Toggles mute state for a conversation with optimistic UI update
    func toggleMute(_ conversation: Conversation) async {
        guard appState?.connectionState == .ready else { return }
        let originalState = conversation.isMuted
        let newState = !originalState

        // Optimistic UI update
        updateConversationMuteState(conversation, isMuted: newState)

        do {
            switch conversation {
            case .direct(let contact):
                try await dataStore?.setContactMuted(contact.id, isMuted: newState)
            case .channel(let channel):
                try await dataStore?.setChannelMuted(channel.id, isMuted: newState)
            case .room(let session):
                try await dataStore?.setSessionMuted(session.id, isMuted: newState)
            }
            // Update badge on success
            await notificationService?.updateBadgeCount()
        } catch {
            // Rollback on failure
            updateConversationMuteState(conversation, isMuted: originalState)
            logger.error("Failed to toggle mute: \(error)")
        }
    }

    /// Updates the mute state in the local conversations array
    private func updateConversationMuteState(_ conversation: Conversation, isMuted: Bool) {
        invalidateConversationCache()
        switch conversation {
        case .direct(let contact):
            if let index = conversations.firstIndex(where: { $0.id == contact.id }) {
                let updated = conversations[index]
                conversations[index] = ContactDTO(
                    id: updated.id,
                    deviceID: updated.deviceID,
                    publicKey: updated.publicKey,
                    name: updated.name,
                    typeRawValue: updated.typeRawValue,
                    flags: updated.flags,
                    outPathLength: updated.outPathLength,
                    outPath: updated.outPath,
                    lastAdvertTimestamp: updated.lastAdvertTimestamp,
                    latitude: updated.latitude,
                    longitude: updated.longitude,
                    lastModified: updated.lastModified,
                    nickname: updated.nickname,
                    isBlocked: updated.isBlocked,
                    isMuted: isMuted,
                    isFavorite: updated.isFavorite,
                    isDiscovered: updated.isDiscovered,
                    lastMessageDate: updated.lastMessageDate,
                    unreadCount: updated.unreadCount,
                    ocvPreset: updated.ocvPreset,
                    customOCVArrayString: updated.customOCVArrayString
                )
            }
        case .channel(let channel):
            if let index = channels.firstIndex(where: { $0.id == channel.id }) {
                let updated = channels[index]
                channels[index] = ChannelDTO(
                    id: updated.id,
                    deviceID: updated.deviceID,
                    index: updated.index,
                    name: updated.name,
                    secret: updated.secret,
                    isEnabled: updated.isEnabled,
                    lastMessageDate: updated.lastMessageDate,
                    unreadCount: updated.unreadCount,
                    unreadMentionCount: updated.unreadMentionCount,
                    isMuted: isMuted,
                    isFavorite: updated.isFavorite
                )
            }
        case .room(let session):
            if let index = roomSessions.firstIndex(where: { $0.id == session.id }) {
                let updated = roomSessions[index]
                roomSessions[index] = RemoteNodeSessionDTO(
                    id: updated.id,
                    deviceID: updated.deviceID,
                    publicKey: updated.publicKey,
                    name: updated.name,
                    role: updated.role,
                    latitude: updated.latitude,
                    longitude: updated.longitude,
                    isConnected: updated.isConnected,
                    permissionLevel: updated.permissionLevel,
                    lastConnectedDate: updated.lastConnectedDate,
                    lastBatteryMillivolts: updated.lastBatteryMillivolts,
                    lastUptimeSeconds: updated.lastUptimeSeconds,
                    lastNoiseFloor: updated.lastNoiseFloor,
                    unreadCount: updated.unreadCount,
                    isMuted: isMuted,
                    isFavorite: updated.isFavorite,
                    lastRxAirtimeSeconds: updated.lastRxAirtimeSeconds,
                    neighborCount: updated.neighborCount,
                    lastSyncTimestamp: updated.lastSyncTimestamp
                )
            }
        }
    }

    // MARK: - Favorite

    /// Toggles favorite state for a conversation with optimistic UI update
    /// - Parameters:
    ///   - conversation: The conversation to toggle
    ///   - disableAnimation: When true, disables SwiftUI List animations to prevent
    ///     conflicts with swipe action dismissal animations
    func toggleFavorite(_ conversation: Conversation, disableAnimation: Bool = false) async {
        guard appState?.connectionState == .ready else { return }
        let originalState = conversation.isFavorite
        let newState = !originalState

        // Optimistic UI update
        if disableAnimation {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                updateConversationFavoriteState(conversation, isFavorite: newState)
            }
        } else {
            updateConversationFavoriteState(conversation, isFavorite: newState)
        }

        do {
            switch conversation {
            case .direct(let contact):
                try await dataStore?.setContactFavorite(contact.id, isFavorite: newState)
            case .channel(let channel):
                try await dataStore?.setChannelFavorite(channel.id, isFavorite: newState)
            case .room(let session):
                try await dataStore?.setSessionFavorite(session.id, isFavorite: newState)
            }
        } catch {
            // Rollback on failure
            if disableAnimation {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    updateConversationFavoriteState(conversation, isFavorite: originalState)
                }
            } else {
                updateConversationFavoriteState(conversation, isFavorite: originalState)
            }
            logger.error("Failed to toggle favorite: \(error)")
        }
    }

    /// Updates the favorite state in the local conversations array
    private func updateConversationFavoriteState(_ conversation: Conversation, isFavorite: Bool) {
        invalidateConversationCache()
        switch conversation {
        case .direct(let contact):
            if let index = conversations.firstIndex(where: { $0.id == contact.id }) {
                let updated = conversations[index]
                conversations[index] = ContactDTO(
                    id: updated.id,
                    deviceID: updated.deviceID,
                    publicKey: updated.publicKey,
                    name: updated.name,
                    typeRawValue: updated.typeRawValue,
                    flags: updated.flags,
                    outPathLength: updated.outPathLength,
                    outPath: updated.outPath,
                    lastAdvertTimestamp: updated.lastAdvertTimestamp,
                    latitude: updated.latitude,
                    longitude: updated.longitude,
                    lastModified: updated.lastModified,
                    nickname: updated.nickname,
                    isBlocked: updated.isBlocked,
                    isMuted: updated.isMuted,
                    isFavorite: isFavorite,
                    isDiscovered: updated.isDiscovered,
                    lastMessageDate: updated.lastMessageDate,
                    unreadCount: updated.unreadCount,
                    ocvPreset: updated.ocvPreset,
                    customOCVArrayString: updated.customOCVArrayString
                )
            }
        case .channel(let channel):
            if let index = channels.firstIndex(where: { $0.id == channel.id }) {
                let updated = channels[index]
                channels[index] = ChannelDTO(
                    id: updated.id,
                    deviceID: updated.deviceID,
                    index: updated.index,
                    name: updated.name,
                    secret: updated.secret,
                    isEnabled: updated.isEnabled,
                    lastMessageDate: updated.lastMessageDate,
                    unreadCount: updated.unreadCount,
                    unreadMentionCount: updated.unreadMentionCount,
                    isMuted: updated.isMuted,
                    isFavorite: isFavorite
                )
            }
        case .room(let session):
            if let index = roomSessions.firstIndex(where: { $0.id == session.id }) {
                let updated = roomSessions[index]
                roomSessions[index] = RemoteNodeSessionDTO(
                    id: updated.id,
                    deviceID: updated.deviceID,
                    publicKey: updated.publicKey,
                    name: updated.name,
                    role: updated.role,
                    latitude: updated.latitude,
                    longitude: updated.longitude,
                    isConnected: updated.isConnected,
                    permissionLevel: updated.permissionLevel,
                    lastConnectedDate: updated.lastConnectedDate,
                    lastBatteryMillivolts: updated.lastBatteryMillivolts,
                    lastUptimeSeconds: updated.lastUptimeSeconds,
                    lastNoiseFloor: updated.lastNoiseFloor,
                    unreadCount: updated.unreadCount,
                    isMuted: updated.isMuted,
                    isFavorite: isFavorite,
                    lastRxAirtimeSeconds: updated.lastRxAirtimeSeconds,
                    neighborCount: updated.neighborCount,
                    lastSyncTimestamp: updated.lastSyncTimestamp
                )
            }
        }
    }

    // MARK: - Conversation List

    /// Removes a conversation from local arrays for optimistic UI update.
    func removeConversation(_ conversation: Conversation) {
        invalidateConversationCache()
        switch conversation {
        case .direct(let contact):
            conversations = conversations.filter { $0.id != contact.id }
        case .channel(let channel):
            channels = channels.filter { $0.id != channel.id }
        case .room(let session):
            roomSessions = roomSessions.filter { $0.id != session.id }
        }
    }

    /// Load conversations for a device
    func loadConversations(deviceID: UUID) async {
        guard let dataStore else { return }

        isLoading = true
        errorMessage = nil

        do {
            conversations = try await dataStore.fetchConversations(deviceID: deviceID)
            invalidateConversationCache()
        } catch {
            errorMessage = error.localizedDescription
        }

        hasLoadedOnce = true
        isLoading = false
    }

    /// Load all contacts for mention autocomplete
    func loadAllContacts(deviceID: UUID) async {
        guard let dataStore else { return }

        do {
            allContacts = try await dataStore.fetchContacts(deviceID: deviceID)
            contactNameSet = Set(allContacts.map(\.name))
        } catch {
            logger.warning("Failed to load contacts for mentions: \(error.localizedDescription)")
        }
    }

    /// Load channels for a device
    func loadChannels(deviceID: UUID) async {
        guard let dataStore else { return }

        do {
            channels = try await dataStore.fetchChannels(deviceID: deviceID)
            invalidateConversationCache()
        } catch {
            // Silently handle - channels are optional
        }
    }

    /// Load room sessions for a device
    func loadRoomSessions(deviceID: UUID) async {
        guard let roomServerService else { return }

        do {
            roomSessions = try await roomServerService.fetchRoomSessions(deviceID: deviceID)
            invalidateConversationCache()
        } catch {
            // Silently handle - rooms are optional
        }
    }

    /// Load all conversations (contacts + channels + rooms) for unified display
    func loadAllConversations(deviceID: UUID) async {
        await loadConversations(deviceID: deviceID)
        await loadChannels(deviceID: deviceID)
        await loadRoomSessions(deviceID: deviceID)
        await loadLastMessagePreviews()
    }

    // MARK: - Messages

    /// Load messages for a contact
    func loadMessages(for contact: ContactDTO) async {
        guard let dataStore else { return }

        // Clear preview state only when switching to a different conversation
        if currentContact?.id != contact.id {
            clearPreviewState()
        }

        currentContact = contact

        // Track active conversation for notification suppression
        notificationService?.activeContactID = contact.id

        isLoading = true
        errorMessage = nil

        // Reset pagination state for new conversation
        hasMoreMessages = true
        isLoadingOlder = false
        cachedBlockedNames = []
        totalFetchedCount = 0

        do {
            messages = try await dataStore.fetchMessages(contactID: contact.id, limit: pageSize, offset: 0)
            totalFetchedCount = messages.count
            hasMoreMessages = messages.count == pageSize
            await buildDisplayItems()

            // Clear unread count and notify UI to refresh chat list
            try await dataStore.clearUnreadCount(contactID: contact.id)
            syncCoordinator?.notifyConversationsChanged()

            // Update app badge
            await notificationService?.updateBadgeCount()
        } catch {
            errorMessage = error.localizedDescription
        }

        hasLoadedOnce = true
        isLoading = false
    }

    /// Optimistically append a message if not already present.
    /// Called synchronously before async reload to ensure ChatTableView
    /// sees the new count immediately for unread tracking.
    func appendMessageIfNew(_ message: MessageDTO) {
        guard !messages.contains(where: { $0.id == message.id }) else { return }
        let previous = messages.last
        messages.append(message)
        messagesByID[message.id] = message
        totalFetchedCount += 1

        // Build display item synchronously for immediate consistency
        let flags = Self.computeDisplayFlags(for: message, previous: previous)
        let newItem = MessageDisplayItem(
            messageID: message.id,
            showTimestamp: flags.showTimestamp,
            showDirectionGap: flags.showDirectionGap,
            showSenderName: flags.showSenderName,
            detectedURL: nil,  // URL detection deferred to avoid main thread blocking
            isOutgoing: message.isOutgoing,
            status: message.status,
            containsSelfMention: message.containsSelfMention,
            mentionSeen: message.mentionSeen,
            heardRepeats: message.heardRepeats,
            previewState: .idle,
            loadedPreview: nil
        )
        displayItems.append(newItem)
        displayItemIndexByID[message.id] = displayItems.count - 1

        // Async URL detection for this message only
        // Capture messageID (not index) to handle concurrent buildDisplayItems() calls
        let messageID = message.id
        let text = message.text
        Task {
            await updateURLForDisplayItem(messageID: messageID, text: text)
        }

        // Add sender to channelSenders if new (for channel messages)
        if let senderName = message.senderNodeName,
           let deviceID = currentChannel?.deviceID {
            addChannelSenderIfNew(senderName, deviceID: deviceID)
        }
    }

    /// Update URL detection for a single display item by message ID.
    /// Uses O(1) dictionary lookup to handle concurrent array modifications.
    private func updateURLForDisplayItem(messageID: UUID, text: String) async {
        let detectedURL = await Task.detached(priority: .userInitiated) {
            LinkPreviewService.extractFirstURL(from: text)
        }.value

        guard let index = displayItemIndexByID[messageID] else { return }
        let item = displayItems[index]
        displayItems[index] = MessageDisplayItem(
            messageID: item.messageID,
            showTimestamp: item.showTimestamp,
            showDirectionGap: item.showDirectionGap,
            showSenderName: item.showSenderName,
            detectedURL: detectedURL,
            isOutgoing: item.isOutgoing,
            status: item.status,
            containsSelfMention: item.containsSelfMention,
            mentionSeen: item.mentionSeen,
            heardRepeats: item.heardRepeats,
            previewState: previewStates[messageID] ?? .idle,
            loadedPreview: loadedPreviews[messageID]
        )
    }

    /// Load any saved draft for the current contact
    /// Drafts are consumed (removed) after loading to prevent re-display
    /// If no draft exists, this method does nothing
    func loadDraftIfExists() {
        guard let contact = currentContact,
              let notificationService,
              let draft = notificationService.consumeDraft(for: contact.id) else {
            return
        }
        composingText = draft
    }

    /// Send a message to the current contact
    /// This is non-blocking - message is created and shown immediately, sent in background
    func sendMessage() async {
        guard let contact = currentContact,
              let messageService,
              !composingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let text = composingText.trimmingCharacters(in: .whitespacesAndNewlines)
        composingText = ""
        errorMessage = nil

        do {
            // Create message immediately and show it
            let message = try await messageService.createPendingMessage(text: text, to: contact)
            appendMessageIfNew(message)

            // Queue for sending
            sendQueue.append(QueuedMessage(messageID: message.id, contactID: contact.id))

            // Start processor if not already running
            if !isProcessingQueue {
                Task { await processQueue() }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Refresh messages for current contact
    func refreshMessages() async {
        guard let contact = currentContact else { return }
        await loadMessages(for: contact)
    }

    /// Load messages for a channel
    func loadChannelMessages(for channel: ChannelDTO) async {
        logger.info("loadChannelMessages: start channel=\(channel.index) deviceID=\(channel.deviceID)")

        guard let dataStore else {
            logger.info("loadChannelMessages: dataStore is nil, returning early")
            return
        }

        // Clear preview state only when switching to a different conversation
        if currentChannel?.id != channel.id {
            clearPreviewState()
        }

        currentChannel = channel
        currentContact = nil

        // Track active channel for notification suppression
        notificationService?.activeContactID = nil
        notificationService?.activeChannelIndex = channel.index
        notificationService?.activeChannelDeviceID = channel.deviceID

        logger.info("loadChannelMessages: setting isLoading=true, current messages.count=\(self.messages.count)")
        isLoading = true
        errorMessage = nil

        // Reset pagination state for new conversation
        hasMoreMessages = true
        isLoadingOlder = false
        cachedBlockedNames = []
        totalFetchedCount = 0

        do {
            var fetchedMessages = try await dataStore.fetchMessages(deviceID: channel.deviceID, channelIndex: channel.index, limit: pageSize, offset: 0)
            let unfilteredCount = fetchedMessages.count
            totalFetchedCount = unfilteredCount
            logger.info("loadChannelMessages: fetched \(unfilteredCount) messages")

            // Filter out messages from blocked contacts (defensive: if fetch fails, show all)
            let blockedNames: Set<String>
            do {
                let blockedContacts = try await dataStore.fetchBlockedContacts(deviceID: channel.deviceID)
                blockedNames = Set(blockedContacts.map(\.name))
            } catch {
                logger.error("Failed to fetch blocked contacts for filtering: \(error)")
                blockedNames = []
            }

            // Cache for pagination
            cachedBlockedNames = blockedNames

            if !blockedNames.isEmpty {
                fetchedMessages = fetchedMessages.filter { message in
                    guard let senderName = message.senderNodeName else { return true }
                    return !blockedNames.contains(senderName)
                }
            }

            // Use unfiltered count to determine if more messages exist
            hasMoreMessages = unfilteredCount == pageSize
            messages = fetchedMessages
            buildChannelSenders(deviceID: channel.deviceID)
            await buildDisplayItems()

            // Clear unread count and notify UI to refresh chat list
            try await dataStore.clearChannelUnreadCount(channelID: channel.id)
            syncCoordinator?.notifyConversationsChanged()

            // Update app badge
            await notificationService?.updateBadgeCount()
        } catch {
            logger.info("loadChannelMessages: error - \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }

        logger.info("loadChannelMessages: done, isLoading=false, messages.count=\(self.messages.count)")
        hasLoadedOnce = true
        isLoading = false
    }

    // MARK: - Pagination

    /// Load older messages when user scrolls near the top
    func loadOlderMessages() async {
        // Guard against duplicate fetches and end of history
        guard !isLoadingOlder, hasMoreMessages else { return }
        guard let dataStore else { return }

        isLoadingOlder = true
        defer { isLoadingOlder = false }

        do {
            let currentOffset = totalFetchedCount
            var olderMessages: [MessageDTO]

            if let contact = currentContact {
                olderMessages = try await dataStore.fetchMessages(
                    contactID: contact.id,
                    limit: pageSize,
                    offset: currentOffset
                )
            } else if let channel = currentChannel {
                olderMessages = try await dataStore.fetchMessages(
                    deviceID: channel.deviceID,
                    channelIndex: channel.index,
                    limit: pageSize,
                    offset: currentOffset
                )
            } else {
                return
            }

            // Use unfiltered count to determine if more messages exist
            let unfilteredCount = olderMessages.count
            totalFetchedCount += unfilteredCount
            if unfilteredCount < pageSize {
                hasMoreMessages = false
            }

            // Filter blocked senders for channel messages (use cached names from initial load)
            if currentChannel != nil && !cachedBlockedNames.isEmpty {
                olderMessages = olderMessages.filter { message in
                    guard let senderName = message.senderNodeName else { return true }
                    return !cachedBlockedNames.contains(senderName)
                }
            }

            // Prepend older messages (they're chronologically earlier)
            messages.insert(contentsOf: olderMessages, at: 0)

            // Update lookup dictionary
            for message in olderMessages {
                messagesByID[message.id] = message
            }

            // Rebuild display items with new messages
            await buildDisplayItems()

        } catch {
            errorMessage = L10n.Chats.Chats.Errors.loadOlderMessagesFailed
            logger.error("Failed to load older messages: \(error)")
        }
    }

    /// Send a channel message
    func sendChannelMessage() async {
        guard let channel = currentChannel,
              let messageService,
              !composingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let text = composingText.trimmingCharacters(in: .whitespacesAndNewlines)
        composingText = ""
        errorMessage = nil

        do {
            _ = try await messageService.sendChannelMessage(
                text: text,
                channelIndex: channel.index,
                deviceID: channel.deviceID
            )

            // Reload messages to show the sent message
            await loadChannelMessages(for: channel)

            // Reload channels to update conversation list
            await loadChannels(deviceID: channel.deviceID)
        } catch {
            errorMessage = error.localizedDescription
            // Restore the text so user can retry
            composingText = text
        }
    }

    // MARK: - Channel Sender Tracking

    /// Build synthetic contacts from channel message senders not in contacts.
    /// Called after loading channel messages to populate mention picker.
    /// Builds into local collections first to avoid multiple @Observable updates.
    private func buildChannelSenders(deviceID: UUID) {
        var localNames: Set<String> = []
        var localSenders: [ContactDTO] = []

        for message in messages {
            if let name = message.senderNodeName {
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty,
                      trimmed.count <= 128,
                      !contactNameSet.contains(trimmed),
                      !localNames.contains(trimmed) else { continue }

                localNames.insert(trimmed)
                localSenders.append(makeSyntheticContact(name: trimmed, deviceID: deviceID))
            }
        }

        // Assign once to minimize observation updates
        channelSenderNames = localNames
        channelSenders = localSenders

        logger.info("Built \(self.channelSenders.count) synthetic contacts from channel senders")
    }

    /// Add a channel sender as a synthetic contact if not already tracked.
    /// Used for incremental additions when new messages arrive.
    private func addChannelSenderIfNew(_ name: String, deviceID: UUID) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              trimmed.count <= 128,
              !contactNameSet.contains(trimmed),
              !channelSenderNames.contains(trimmed) else { return }

        channelSenderNames.insert(trimmed)
        channelSenders.append(makeSyntheticContact(name: trimmed, deviceID: deviceID))
    }

    /// Create a synthetic ContactDTO for a channel sender not in contacts.
    private func makeSyntheticContact(name: String, deviceID: UUID) -> ContactDTO {
        ContactDTO(
            id: name.stableUUID,
            deviceID: deviceID,
            publicKey: Data(),
            name: name,
            typeRawValue: ContactType.chat.rawValue,
            flags: 0,
            outPathLength: -1,
            outPath: Data(),
            lastAdvertTimestamp: 0,
            latitude: 0.0,
            longitude: 0.0,
            lastModified: 0,
            nickname: nil,
            isBlocked: false,
            isMuted: false,
            isFavorite: false,
            isDiscovered: false,
            lastMessageDate: nil,
            unreadCount: 0
        )
    }

    /// Get the last message preview for a contact
    func lastMessagePreview(for contact: ContactDTO) -> String? {
        // Check cache first
        if let cached = lastMessageCache[contact.id] {
            return cached.text
        }
        return nil
    }

    /// Load last message previews for all conversations
    func loadLastMessagePreviews() async {
        guard let dataStore else { return }

        // Load contact message previews
        for contact in conversations {
            do {
                let messages = try await dataStore.fetchMessages(contactID: contact.id, limit: 1)
                if let lastMessage = messages.last {
                    lastMessageCache[contact.id] = lastMessage
                }
            } catch {
                // Silently ignore errors for preview loading
            }
        }

        // Load channel message previews (filter out blocked senders)
        // Group channels by deviceID to minimize blocked contacts fetches
        let channelsByDevice = Dictionary(grouping: channels, by: \.deviceID)
        for (deviceID, deviceChannels) in channelsByDevice {
            // Fetch blocked contacts once per device
            let blockedNames: Set<String>
            do {
                let blockedContacts = try await dataStore.fetchBlockedContacts(deviceID: deviceID)
                blockedNames = Set(blockedContacts.map(\.name))
            } catch {
                blockedNames = []
            }

            for channel in deviceChannels {
                do {
                    // Fetch extra messages in case recent ones are from blocked senders
                    let messages = try await dataStore.fetchMessages(deviceID: channel.deviceID, channelIndex: channel.index, limit: 20)

                    // Filter out messages from blocked senders and get the last valid one
                    let lastMessage: MessageDTO?
                    if blockedNames.isEmpty {
                        lastMessage = messages.last
                    } else {
                        lastMessage = messages.last { message in
                            guard let senderName = message.senderNodeName else { return true }
                            return !blockedNames.contains(senderName)
                        }
                    }

                    if let lastMessage {
                        lastMessageCache[channel.id] = lastMessage
                    }
                } catch {
                    // Silently ignore errors for preview loading
                }
            }
        }
    }

    /// Get the last message preview for a channel
    func lastMessagePreview(for channel: ChannelDTO) -> String? {
        if let cached = lastMessageCache[channel.id] {
            return cached.text
        }
        return nil
    }

    /// Retry sending a failed message with flood routing enabled
    func retryMessage(_ message: MessageDTO) async {
        logger.info("retryMessage called for message: \(message.id)")

        guard let messageService else {
            logger.warning("retryMessage: messageService is nil")
            return
        }

        guard let contact = currentContact else {
            logger.warning("retryMessage: currentContact is nil")
            return
        }

        logger.info("retryMessage: starting retry for contact \(contact.displayName)")

        errorMessage = nil

        do {
            // Retry the existing message (preserves message identity)
            logger.info("retryMessage: calling retryDirectMessage with messageID")
            let result = try await messageService.retryDirectMessage(messageID: message.id, to: contact)
            logger.info("retryMessage: completed with status \(String(describing: result.status))")

            // Reload messages to show updated status
            await loadMessages(for: contact)
        } catch {
            logger.error("retryMessage: error - \(error)")
            errorMessage = error.localizedDescription
            showRetryError = true
            // Reload to show the failed status
            await loadMessages(for: contact)
        }
    }

    /// Retry sending a failed channel message.
    /// This resends the message text to MeshCore - the UI should NOT change
    /// during retry. Only the status will update (Sent -> Delivered or Failed).
    func retryChannelMessage(_ message: MessageDTO) async {
        guard let messageService,
              let channel = currentChannel else { return }

        // Update status to pending
        try? await dataStore?.updateMessageStatus(id: message.id, status: .pending)

        // Reload to show updated status
        await loadChannelMessages(for: channel)

        do {
            // Resend the message text
            _ = try await messageService.sendChannelMessage(
                text: message.text,
                channelIndex: channel.index,
                deviceID: channel.deviceID
            )

            // Delete the old failed message since a new one was created
            try await dataStore?.deleteMessage(id: message.id)

            // Reload messages
            await loadChannelMessages(for: channel)
        } catch {
            // Restore failed status
            try? await dataStore?.updateMessageStatus(id: message.id, status: .failed)
            await loadChannelMessages(for: channel)
            errorMessage = error.localizedDescription
            showRetryError = true
        }
    }

    /// Resend a channel message in place, or copy text for direct messages.
    /// Used for "Send Again" context menu action.
    func sendAgain(_ message: MessageDTO) async {
        if message.channelIndex != nil {
            // Channel messages: resend in place (increments send count)
            guard let messageService else { return }
            do {
                try await messageService.resendChannelMessage(messageID: message.id)
                // Reload to show updated send count
                if let channel = currentChannel {
                    await loadChannelMessages(for: channel)
                }
            } catch {
                logger.error("Failed to resend message: \(error)")
            }
        } else {
            // Direct messages: keep existing behavior (copy to compose field)
            composingText = message.text
            await sendMessage()
        }
    }

    /// Delete a single message
    func deleteMessage(_ message: MessageDTO) async {
        guard appState?.connectionState == .ready else { return }
        guard let dataStore else { return }

        do {
            try await dataStore.deleteMessage(id: message.id)

            // Remove from all local collections
            messages.removeAll { $0.id == message.id }
            messagesByID.removeValue(forKey: message.id)
            displayItems.removeAll { $0.messageID == message.id }
            // Rebuild index dictionary after removal (indices shift)
            displayItemIndexByID = Dictionary(uniqueKeysWithValues: displayItems.enumerated().map { ($0.element.messageID, $0.offset) })

            // Clean up preview state for deleted message
            cleanupPreviewState(for: message.id)

            // Update last message date if needed
            if let currentContact {
                if let lastMessage = messages.last {
                    try await dataStore.updateContactLastMessage(
                        contactID: currentContact.id,
                        date: lastMessage.date
                    )
                } else {
                    try await dataStore.updateContactLastMessage(
                        contactID: currentContact.id,
                        date: Date.distantPast
                    )
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Delete all messages for a contact (conversation deletion)
    func deleteConversation(for contact: ContactDTO) async throws {
        guard appState?.connectionState == .ready else { return }
        guard let dataStore else { return }

        // Fetch all messages for this contact
        let messages = try await dataStore.fetchMessages(contactID: contact.id, limit: 10000)

        // Delete each message
        for message in messages {
            try await dataStore.deleteMessage(id: message.id)
        }

        // Clear unread count before hiding from list
        try await dataStore.clearUnreadCount(contactID: contact.id)

        // Clear last message date on contact (nil removes it from conversations list)
        try await dataStore.updateContactLastMessage(contactID: contact.id, date: nil)

        // Recalculate badge
        await notificationService?.updateBadgeCount()
    }

    // MARK: - Timestamp Helpers

    /// Determines if a timestamp should be shown for a message at the given index.
    /// Shows timestamp for first message or when there's a gap > 5 minutes.
    static func shouldShowTimestamp(at index: Int, in messages: [MessageDTO]) -> Bool {
        guard index > 0 else { return true }

        let currentMessage = messages[index]
        let previousMessage = messages[index - 1]

        let gap = abs(Int(currentMessage.timestamp) - Int(previousMessage.timestamp))
        return gap > 300
    }

    /// Determines if the message direction changed from the previous message.
    /// Used to add visual separation between incoming and outgoing message groups.
    static func isDirectionChange(at index: Int, in messages: [MessageDTO]) -> Bool {
        guard index > 0 else { return false }

        let currentMessage = messages[index]
        let previousMessage = messages[index - 1]

        return currentMessage.direction != previousMessage.direction
    }

    /// Determines if sender name should be shown for a channel message at the given index.
    /// Returns true for first message or when sender/timing breaks the group.
    ///
    /// **Note:** Channel messages identify senders solely by parsing "NodeName: text" from
    /// the message content (per MeshCore protocol). There is no cryptographic sender
    /// verification. `senderKeyPrefix` is always nil for channel messages.
    static func shouldShowSenderName(at index: Int, in messages: [MessageDTO]) -> Bool {
        let currentMessage = messages[index]

        // Direct messages use configuration.showSenderName=false to hide names,
        // so this value is ignored. Return true (no grouping) for simplicity.
        guard currentMessage.contactID == nil else { return true }

        // Outgoing messages don't show sender name
        guard !currentMessage.isOutgoing else { return true }

        // First message always shows sender name
        guard index > 0 else { return true }

        let previousMessage = messages[index - 1]

        // Direction change breaks group
        guard !previousMessage.isOutgoing else { return true }

        // Time gap > 5 minutes breaks group
        let gap = abs(Int(currentMessage.timestamp) - Int(previousMessage.timestamp))
        guard gap <= 300 else { return true }

        // Different sender breaks group (channel messages only use senderNodeName)
        if let currentName = currentMessage.senderNodeName,
           let previousName = previousMessage.senderNodeName {
            return currentName != previousName
        }

        // No sender name available (malformed message), show name to be safe
        return true
    }

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
        let showTimestamp = timeGap > 300

        // Direction gap: direction changed from previous
        let showDirectionGap = message.direction != previous.direction

        // Sender name grouping (channel messages only)
        let showSenderName: Bool
        if message.contactID != nil || message.isOutgoing {
            // Direct messages or outgoing: always true (UI ignores for direct messages anyway)
            showSenderName = true
        } else if previous.isOutgoing || timeGap > 300 {
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

    // MARK: - Display Items

    /// Build display items with pre-computed properties.
    /// URL detection runs off main thread to avoid blocking.
    func buildDisplayItems() async {
        messagesByID = Dictionary(uniqueKeysWithValues: messages.map { ($0.id, $0) })

        // Extract texts for URL detection off main thread
        let texts = messages.map { $0.text }
        let urls = await Task.detached(priority: .userInitiated) {
            texts.map { LinkPreviewService.extractFirstURL(from: $0) }
        }.value

        displayItems = messages.enumerated().map { index, message in
            // Compute all display flags in single pass to avoid redundant array lookups
            let previous: MessageDTO? = index > 0 ? messages[index - 1] : nil
            let flags = Self.computeDisplayFlags(for: message, previous: previous)

            return MessageDisplayItem(
                messageID: message.id,
                showTimestamp: flags.showTimestamp,
                showDirectionGap: flags.showDirectionGap,
                showSenderName: flags.showSenderName,
                detectedURL: urls[index],
                isOutgoing: message.isOutgoing,
                status: message.status,
                containsSelfMention: message.containsSelfMention,
                mentionSeen: message.mentionSeen,
                heardRepeats: message.heardRepeats,
                previewState: previewStates[message.id] ?? .idle,
                loadedPreview: loadedPreviews[message.id]
            )
        }

        // Build O(1) index lookup
        displayItemIndexByID = Dictionary(uniqueKeysWithValues: displayItems.enumerated().map { ($0.element.messageID, $0.offset) })
    }

    /// Get full message DTO for a display item.
    /// Logs a warning if lookup fails (indicates data inconsistency).
    func message(for displayItem: MessageDisplayItem) -> MessageDTO? {
        guard let message = messagesByID[displayItem.messageID] else {
            logger.warning("Message lookup failed for displayItem id=\(displayItem.messageID)")
            return nil
        }
        return message
    }

    // MARK: - Preview State Management

    /// Request preview fetch for a message (called when cell becomes visible)
    func requestPreviewFetch(for messageID: UUID) {
        // Ignore if already fetched or in progress
        guard previewStates[messageID] == nil || previewStates[messageID] == .idle else { return }

        // Get the display item to check for detected URL
        guard let displayItem = displayItems.first(where: { $0.messageID == messageID }),
              let url = displayItem.detectedURL else { return }

        // Check if channel message
        let isChannel = currentChannel != nil

        // Start fetch task
        previewFetchTasks[messageID] = Task {
            await fetchPreview(for: messageID, url: url, isChannelMessage: isChannel)
        }
    }

    /// Fetch preview for a message and update state
    private func fetchPreview(for messageID: UUID, url: URL, isChannelMessage: Bool) async {
        guard let dataStore, let linkPreviewCache else { return }

        // Update to loading state
        previewStates[messageID] = .loading
        rebuildDisplayItem(for: messageID)

        // Get preview from cache (handles all tiers: memory, database, network)
        let result = await linkPreviewCache.preview(
            for: url,
            using: dataStore,
            isChannelMessage: isChannelMessage
        )

        // Check if task was cancelled (message scrolled away or conversation changed)
        guard !Task.isCancelled else {
            previewFetchTasks.removeValue(forKey: messageID)
            return
        }

        // Update state based on result
        switch result {
        case .loaded(let dto):
            previewStates[messageID] = .loaded
            loadedPreviews[messageID] = dto
            // VoiceOver announcement for dynamic content
            if let title = dto.title {
                AccessibilityNotification.Announcement("Preview loaded: \(title)")
                    .post()
            }

        case .loading:
            // Still loading (duplicate request), keep current state
            break

        case .noPreviewAvailable, .failed:
            previewStates[messageID] = .noPreview

        case .disabled:
            previewStates[messageID] = .disabled
        }

        previewFetchTasks.removeValue(forKey: messageID)
        rebuildDisplayItem(for: messageID)
    }

    /// Manually fetch preview (for tap-to-load when previews disabled)
    func manualFetchPreview(for messageID: UUID) async {
        guard let displayItem = displayItems.first(where: { $0.messageID == messageID }),
              let url = displayItem.detectedURL,
              let dataStore,
              let linkPreviewCache else { return }

        previewStates[messageID] = .loading
        rebuildDisplayItem(for: messageID)

        let result = await linkPreviewCache.manualFetch(for: url, using: dataStore)

        switch result {
        case .loaded(let dto):
            previewStates[messageID] = .loaded
            loadedPreviews[messageID] = dto
            // VoiceOver announcement for dynamic content
            if let title = dto.title {
                AccessibilityNotification.Announcement("Preview loaded: \(title)")
                    .post()
            }
        case .loading:
            break
        case .noPreviewAvailable, .failed, .disabled:
            previewStates[messageID] = .noPreview
        }

        rebuildDisplayItem(for: messageID)
    }

    /// Rebuild a single display item with current preview state (O(1) lookup)
    private func rebuildDisplayItem(for messageID: UUID) {
        guard let index = displayItemIndexByID[messageID] else { return }
        let item = displayItems[index]

        displayItems[index] = MessageDisplayItem(
            messageID: item.messageID,
            showTimestamp: item.showTimestamp,
            showDirectionGap: item.showDirectionGap,
            showSenderName: item.showSenderName,
            detectedURL: item.detectedURL,
            isOutgoing: item.isOutgoing,
            status: item.status,
            containsSelfMention: item.containsSelfMention,
            mentionSeen: item.mentionSeen,
            heardRepeats: item.heardRepeats,
            previewState: previewStates[messageID] ?? .idle,
            loadedPreview: loadedPreviews[messageID]
        )
    }

    /// Cancel preview fetch for a message (called when cell scrolls away)
    func cancelPreviewFetch(for messageID: UUID) {
        previewFetchTasks[messageID]?.cancel()
        previewFetchTasks.removeValue(forKey: messageID)
    }

    /// Clear all preview state (called on conversation switch)
    private func clearPreviewState() {
        previewFetchTasks.values.forEach { $0.cancel() }
        previewFetchTasks.removeAll()
        previewStates.removeAll()
        loadedPreviews.removeAll()
    }

    /// Clean up preview state for a specific message (called on message deletion)
    private func cleanupPreviewState(for messageID: UUID) {
        previewStates.removeValue(forKey: messageID)
        loadedPreviews.removeValue(forKey: messageID)
        previewFetchTasks[messageID]?.cancel()
        previewFetchTasks.removeValue(forKey: messageID)
    }

    // MARK: - Message Queue

    /// Add a message to the send queue (for testing)
    func enqueueMessage(_ messageID: UUID, contactID: UUID) {
        sendQueue.append(QueuedMessage(messageID: messageID, contactID: contactID))
    }

    /// Process the queue (exposed for testing)
    func processQueueForTesting() async {
        await processQueue()
    }

    /// Process queued messages serially
    private func processQueue() async {
        guard let messageService,
              let dataStore else { return }

        isProcessingQueue = true
        defer { isProcessingQueue = false }

        var lastDeviceID: UUID?

        // Process messages with re-check after reload to catch any that arrived during reload
        repeat {
            while !sendQueue.isEmpty {
                let queued = sendQueue.removeFirst()

                // Fetch the target contact by ID - it may differ from currentContact
                guard let contact = try? await dataStore.fetchContact(id: queued.contactID) else {
                    // Contact was deleted, skip this message
                    logger.info("Skipping queued message - contact \(queued.contactID) was deleted")
                    continue
                }

                lastDeviceID = contact.deviceID

                do {
                    _ = try await messageService.sendExistingMessage(
                        messageID: queued.messageID,
                        to: contact
                    )
                } catch {
                    errorMessage = error.localizedDescription
                }
            }

            // Reload after queue drains - syncs statuses and conversation list
            if let contact = currentContact {
                await loadMessages(for: contact)
            }
            if let deviceID = lastDeviceID {
                await loadConversations(deviceID: deviceID)
            }
        } while !sendQueue.isEmpty
    }
}
