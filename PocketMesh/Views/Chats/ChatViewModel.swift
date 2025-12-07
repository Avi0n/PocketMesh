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

    // MARK: - Dependencies

    private var dataStore: DataStore?
    private var messageService: MessageService?

    // MARK: - Initialization

    init() {}

    /// Configure with services
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
        // This would need a separate query in a full implementation
        // For now, we'll just show an indicator
        guard contact.lastMessageDate != nil else { return nil }
        return "Message"
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
