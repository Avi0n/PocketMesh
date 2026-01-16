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

    /// Current channels with messages
    var channels: [ChannelDTO] = []

    /// Current room sessions
    var roomSessions: [RemoteNodeSessionDTO] = []

    /// Combined conversations (contacts + channels + rooms)
    var allConversations: [Conversation] {
        // Filter out repeaters and blocked contacts from direct conversations
        let contactConversations = conversations
            .filter { $0.type != .repeater && !$0.isBlocked }
            .map { Conversation.direct($0) }
        // Show channels that are configured (have a name OR have a non-zero secret)
        let channelConversations = channels.filter { !$0.name.isEmpty || $0.hasSecret }.map { Conversation.channel($0) }
        // Show all room sessions (connected or disconnected)
        let roomConversations = roomSessions.map { Conversation.room($0) }
        return (contactConversations + channelConversations + roomConversations)
            .sorted { ($0.lastMessageDate ?? .distantPast) > ($1.lastMessageDate ?? .distantPast) }
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

    // MARK: - Dependencies

    private var dataStore: DataStore?
    private var linkPreviewCache: (any LinkPreviewCaching)?
    private var messageService: MessageService?
    private var notificationService: NotificationService?
    private var channelService: ChannelService?
    private var roomServerService: RoomServerService?
    private var syncCoordinator: SyncCoordinator?

    // MARK: - Initialization

    init() {}

    /// Configure with services from AppState (with link preview cache for message views)
    func configure(appState: AppState, linkPreviewCache: any LinkPreviewCaching) {
        self.dataStore = appState.services?.dataStore
        self.messageService = appState.services?.messageService
        self.notificationService = appState.services?.notificationService
        self.channelService = appState.services?.channelService
        self.roomServerService = appState.services?.roomServerService
        self.syncCoordinator = appState.syncCoordinator
        self.linkPreviewCache = linkPreviewCache
    }

    /// Configure with services from AppState (for conversation list views that don't show previews)
    func configure(appState: AppState) {
        self.dataStore = appState.services?.dataStore
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
                    isMuted: isMuted
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
                    lastRxAirtimeSeconds: updated.lastRxAirtimeSeconds,
                    neighborCount: updated.neighborCount,
                    lastSyncTimestamp: updated.lastSyncTimestamp
                )
            }
        }
    }

    // MARK: - Conversation List

    /// Removes a conversation from local arrays (optimistic UI update).
    /// Call before async deletion to prevent SwiftUI List animation glitches.
    func removeConversation(_ conversation: Conversation) {
        switch conversation {
        case .direct(let contact):
            conversations.removeAll { $0.id == contact.id }
        case .channel(let channel):
            channels.removeAll { $0.id == channel.id }
        case .room(let session):
            roomSessions.removeAll { $0.id == session.id }
        }
    }

    /// Load conversations for a device
    func loadConversations(deviceID: UUID) async {
        guard let dataStore else { return }

        isLoading = true
        errorMessage = nil

        do {
            conversations = try await dataStore.fetchConversations(deviceID: deviceID)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Load all contacts for mention autocomplete
    func loadAllContacts(deviceID: UUID) async {
        guard let dataStore else { return }

        do {
            allContacts = try await dataStore.fetchContacts(deviceID: deviceID)
        } catch {
            logger.warning("Failed to load contacts for mentions: \(error.localizedDescription)")
        }
    }

    /// Load channels for a device
    func loadChannels(deviceID: UUID) async {
        guard let dataStore else { return }

        do {
            channels = try await dataStore.fetchChannels(deviceID: deviceID)
        } catch {
            // Silently handle - channels are optional
        }
    }

    /// Load room sessions for a device
    func loadRoomSessions(deviceID: UUID) async {
        guard let roomServerService else { return }

        do {
            roomSessions = try await roomServerService.fetchRoomSessions(deviceID: deviceID)
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

        // Clear preview state from previous conversation
        clearPreviewState()

        currentContact = contact

        // Track active conversation for notification suppression
        notificationService?.activeContactID = contact.id

        isLoading = true
        errorMessage = nil

        do {
            messages = try await dataStore.fetchMessages(contactID: contact.id)
            await buildDisplayItems()

            // Clear unread count and notify UI to refresh chat list
            try await dataStore.clearUnreadCount(contactID: contact.id)
            await syncCoordinator?.notifyConversationsChanged()

            // Update app badge
            await notificationService?.updateBadgeCount()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Optimistically append a message if not already present.
    /// Called synchronously before async reload to ensure ChatTableView
    /// sees the new count immediately for unread tracking.
    func appendMessageIfNew(_ message: MessageDTO) {
        guard !messages.contains(where: { $0.id == message.id }) else { return }
        let index = messages.count
        messages.append(message)
        messagesByID[message.id] = message

        // Build display item synchronously for immediate consistency
        let newItem = MessageDisplayItem(
            messageID: message.id,
            showTimestamp: Self.shouldShowTimestamp(at: index, in: messages),
            showDirectionGap: Self.isDirectionChange(at: index, in: messages),
            detectedURL: nil,  // URL detection deferred to avoid main thread blocking
            isOutgoing: message.isOutgoing,
            containsSelfMention: message.containsSelfMention,
            mentionSeen: message.mentionSeen,
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
            detectedURL: detectedURL,
            isOutgoing: item.isOutgoing,
            containsSelfMention: item.containsSelfMention,
            mentionSeen: item.mentionSeen,
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
            messages.append(message)

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

        // Clear preview state from previous conversation
        clearPreviewState()

        currentChannel = channel
        currentContact = nil

        // Track active channel for notification suppression
        notificationService?.activeContactID = nil
        notificationService?.activeChannelIndex = channel.index
        notificationService?.activeChannelDeviceID = channel.deviceID

        logger.info("loadChannelMessages: setting isLoading=true, current messages.count=\(self.messages.count)")
        isLoading = true
        errorMessage = nil

        do {
            var fetchedMessages = try await dataStore.fetchMessages(deviceID: channel.deviceID, channelIndex: channel.index)
            logger.info("loadChannelMessages: fetched \(fetchedMessages.count) messages")

            // Filter out messages from blocked contacts (defensive: if fetch fails, show all)
            let blockedNames: Set<String>
            do {
                let blockedContacts = try await dataStore.fetchBlockedContacts(deviceID: channel.deviceID)
                blockedNames = Set(blockedContacts.map(\.name))
            } catch {
                logger.error("Failed to fetch blocked contacts for filtering: \(error)")
                blockedNames = []
            }

            if !blockedNames.isEmpty {
                fetchedMessages = fetchedMessages.filter { message in
                    guard let senderName = message.senderNodeName else { return true }
                    return !blockedNames.contains(senderName)
                }
            }

            messages = fetchedMessages
            await buildDisplayItems()

            // Clear unread count and notify UI to refresh chat list
            try await dataStore.clearChannelUnreadCount(channelID: channel.id)
            await syncCoordinator?.notifyConversationsChanged()

            // Update app badge
            await notificationService?.updateBadgeCount()
        } catch {
            logger.info("loadChannelMessages: error - \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }

        logger.info("loadChannelMessages: done, isLoading=false, messages.count=\(self.messages.count)")
        isLoading = false
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

    /// Delete a single message
    func deleteMessage(_ message: MessageDTO) async {
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
            MessageDisplayItem(
                messageID: message.id,
                showTimestamp: Self.shouldShowTimestamp(at: index, in: messages),
                showDirectionGap: Self.isDirectionChange(at: index, in: messages),
                detectedURL: urls[index],
                isOutgoing: message.isOutgoing,
                containsSelfMention: message.containsSelfMention,
                mentionSeen: message.mentionSeen,
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
            detectedURL: item.detectedURL,
            isOutgoing: item.isOutgoing,
            containsSelfMention: item.containsSelfMention,
            mentionSeen: item.mentionSeen,
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
