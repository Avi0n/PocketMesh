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

    /// Current channels with messages
    var channels: [ChannelDTO] = []

    /// Current room sessions
    var roomSessions: [RemoteNodeSessionDTO] = []

    /// Combined conversations (contacts + channels + rooms)
    var allConversations: [Conversation] {
        // Filter out repeaters from direct conversations - they should not appear in Chats
        let contactConversations = conversations
            .filter { $0.type != .repeater }
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

    // MARK: - Dependencies

    private var dataStore: DataStore?
    private var messageService: MessageService?
    private var notificationService: NotificationService?
    private var channelService: ChannelService?
    private var roomServerService: RoomServerService?

    // MARK: - Initialization

    init() {}

    /// Configure with services from AppState
    func configure(appState: AppState) {
        self.dataStore = appState.services?.dataStore
        self.messageService = appState.services?.messageService
        self.notificationService = appState.services?.notificationService
        self.channelService = appState.services?.channelService
        self.roomServerService = appState.services?.roomServerService
    }

    /// Configure with services (for testing)
    func configure(dataStore: DataStore, messageService: MessageService) {
        self.dataStore = dataStore
        self.messageService = messageService
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

        currentContact = contact

        // Track active conversation for notification suppression
        notificationService?.activeContactID = contact.id

        isLoading = true
        errorMessage = nil

        do {
            messages = try await dataStore.fetchMessages(contactID: contact.id)

            // Clear unread count
            try await dataStore.clearUnreadCount(contactID: contact.id)

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
        messages.append(message)
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
        guard let dataStore else { return }

        currentChannel = channel
        currentContact = nil

        // Track active channel for notification suppression
        notificationService?.activeContactID = nil
        notificationService?.activeChannelIndex = channel.index
        notificationService?.activeChannelDeviceID = channel.deviceID

        isLoading = true
        errorMessage = nil

        do {
            messages = try await dataStore.fetchMessages(deviceID: channel.deviceID, channelIndex: channel.index)

            // Clear unread count
            try await dataStore.clearChannelUnreadCount(channelID: channel.id)

            // Update app badge
            await notificationService?.updateBadgeCount()
        } catch {
            errorMessage = error.localizedDescription
        }

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

        // Load channel message previews
        for channel in channels {
            do {
                let messages = try await dataStore.fetchMessages(deviceID: channel.deviceID, channelIndex: channel.index, limit: 1)
                if let lastMessage = messages.last {
                    lastMessageCache[channel.id] = lastMessage
                }
            } catch {
                // Silently ignore errors for preview loading
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
        logger.debug("retryMessage called for message: \(message.id)")

        guard let messageService else {
            logger.warning("retryMessage: messageService is nil")
            return
        }

        guard let contact = currentContact else {
            logger.warning("retryMessage: currentContact is nil")
            return
        }

        logger.debug("retryMessage: starting retry for contact \(contact.displayName)")

        errorMessage = nil

        do {
            // Retry the existing message (preserves message identity)
            logger.debug("retryMessage: calling retryDirectMessage with messageID")
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

            // Remove from local array
            messages.removeAll { $0.id == message.id }

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

        var lastDeviceID: UUID?

        while !sendQueue.isEmpty {
            let queued = sendQueue.removeFirst()

            // Fetch the target contact by ID - it may differ from currentContact
            guard let contact = try? await dataStore.fetchContact(id: queued.contactID) else {
                // Contact was deleted, skip this message
                logger.debug("Skipping queued message - contact \(queued.contactID) was deleted")
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

        // Single reload after queue drains - syncs statuses and conversation list
        if let contact = currentContact {
            await loadMessages(for: contact)
        }
        if let deviceID = lastDeviceID {
            await loadConversations(deviceID: deviceID)
        }

        isProcessingQueue = false
    }
}
