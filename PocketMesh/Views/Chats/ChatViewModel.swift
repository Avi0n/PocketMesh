import SwiftUI
import PocketMeshKit

/// ViewModel for chat operations
@Observable
@MainActor
final class ChatViewModel {

    // MARK: - Properties

    /// Current conversations (contacts with messages)
    var conversations: [ContactDTO] = []

    /// Messages for the current conversation
    var messages: [MessageDTO] = []

    /// Current contact being chatted with
    var currentContact: ContactDTO?

    /// Loading state
    var isLoading = false

    /// Error message if any
    var errorMessage: String?

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

    // MARK: - Initialization

    init() {}

    /// Configure with services from AppState
    func configure(appState: AppState) {
        self.dataStore = appState.dataStore
        self.messageService = appState.messageService
        self.notificationService = appState.notificationService
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

    // MARK: - Messages

    /// Load messages for a contact
    func loadMessages(for contact: ContactDTO) async {
        guard let dataStore else { return }

        currentContact = contact
        isLoading = true
        errorMessage = nil

        do {
            messages = try await dataStore.fetchMessages(contactID: contact.id)

            // Clear unread count
            try await dataStore.clearUnreadCount(contactID: contact.id)
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
            let result = try await messageService.sendDirectMessage(text: text, to: contact)

            // Reload messages to show the sent message
            await loadMessages(for: contact)

            // Update conversations list to reflect new message
            await loadConversations(deviceID: contact.deviceID)
        } catch {
            errorMessage = error.localizedDescription
            // Restore the text so user can retry
            composingText = text
        }

        isSending = false
    }

    /// Refresh messages for current contact
    func refreshMessages() async {
        guard let contact = currentContact else { return }
        await loadMessages(for: contact)
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
    }

    /// Retry sending a failed message
    func retryMessage(_ message: MessageDTO) async {
        guard let messageService,
              let contact = currentContact else { return }

        isSending = true
        errorMessage = nil

        do {
            // Delete the failed message
            try await dataStore?.deleteMessage(id: message.id)

            // Send a new message with the same text
            _ = try await messageService.sendDirectMessage(text: message.text, to: contact)

            // Reload messages
            await loadMessages(for: contact)
        } catch {
            errorMessage = error.localizedDescription
        }

        isSending = false
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

    // MARK: - Message Status Helpers

    /// Returns a system image name for the message status
    static func statusIcon(for status: MessageStatus) -> String {
        switch status {
        case .pending:
            return "clock"
        case .sending:
            return "arrow.up.circle"
        case .sent:
            return "checkmark"
        case .delivered:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.circle"
        case .read:
            return "eye"
        }
    }

    /// Returns a color for the message status
    static func statusColor(for status: MessageStatus) -> Color {
        switch status {
        case .pending, .sending:
            return .secondary
        case .sent:
            return .blue
        case .delivered:
            return .green
        case .failed:
            return .red
        case .read:
            return .purple
        }
    }
}
