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

    /// Whether a message is being sent
    var isSending = false

    /// Last message previews cache
    private var lastMessageCache: [UUID: MessageDTO] = [:]

    // MARK: - Dependencies

    private var dataStore: DataStore?
    private var messageService: MessageService?
    private var notificationService: NotificationService?
    private var channelService: ChannelService?
    private var roomServerService: RoomServerService?
    private weak var appState: AppState?

    // MARK: - Initialization

    init() {}

    /// Configure with services from AppState
    func configure(appState: AppState) {
        self.dataStore = appState.services?.dataStore
        self.messageService = appState.services?.messageService
        self.notificationService = appState.services?.notificationService
        self.channelService = appState.services?.channelService
        self.roomServerService = appState.services?.roomServerService
        self.appState = appState
    }

    /// Configure with services (for testing)
    func configure(dataStore: DataStore, messageService: MessageService) {
        self.dataStore = dataStore
        self.messageService = messageService
    }

    // MARK: - Conversation List

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
    func sendMessage() async {
        guard let contact = currentContact,
              let messageService,
              !composingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let text = composingText.trimmingCharacters(in: .whitespacesAndNewlines)
        composingText = ""
        isSending = true
        errorMessage = nil

        do {
            _ = try await messageService.sendMessageWithRetry(
                text: text,
                to: contact,
                onMessageCreated: { [weak self] _ in
                    // Reload messages immediately when message is saved (before retry loop starts)
                    guard let self else { return }
                    await MainActor.run {
                        Task {
                            await self.loadMessages(for: contact)
                        }
                    }
                }
            )

            // Final reload to show delivered status
            await loadMessages(for: contact)

            // Update conversations list to reflect new message
            await loadConversations(deviceID: contact.deviceID)
            await appState?.syncCoordinator?.notifyConversationsChanged()
        } catch {
            errorMessage = error.localizedDescription
            // Note: composingText already cleared - failed message can be retried from bubble
        }

        isSending = false
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
        isSending = true
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
            await appState?.syncCoordinator?.notifyConversationsChanged()
        } catch {
            errorMessage = error.localizedDescription
            // Restore the text so user can retry
            composingText = text
        }

        isSending = false
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

        isSending = true
        errorMessage = nil

        do {
            // Retry the existing message (preserves message identity)
            logger.debug("retryMessage: calling retryDirectMessage with messageID")
            _ = try await messageService.retryDirectMessage(messageID: message.id, to: contact)
            logger.info("retryMessage: retryDirectMessage succeeded")

            // Reload messages to show updated status
            await loadMessages(for: contact)
        } catch {
            logger.error("retryMessage: error - \(error)")
            errorMessage = error.localizedDescription
            showRetryError = true
            // Reload to show the failed status
            await loadMessages(for: contact)
        }

        isSending = false
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

        // Clear last message date on contact
        try await dataStore.updateContactLastMessage(contactID: contact.id, date: Date.distantPast)

        // Reload conversations
        await loadConversations(deviceID: contact.deviceID)
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
}
