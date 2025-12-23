import SwiftUI
import PocketMeshServices

/// ViewModel for room conversation operations
@Observable
@MainActor
final class RoomConversationViewModel {

    // MARK: - Properties

    /// Current room session
    var session: RemoteNodeSessionDTO?

    /// Room messages
    var messages: [RoomMessageDTO] = []

    /// Loading state
    var isLoading = false

    /// Error message if any
    var errorMessage: String?

    /// Message text being composed
    var composingText = ""

    /// Whether a message is being sent
    var isSending = false

    // MARK: - Dependencies

    private var roomServerService: RoomServerService?
    private var dataStore: DataStore?
    private weak var appState: AppState?

    // MARK: - Initialization

    init() {}

    /// Configure with services from AppState
    func configure(appState: AppState) {
        self.roomServerService = appState.services?.roomServerService
        self.dataStore = appState.services?.dataStore
        self.appState = appState
    }

    // MARK: - Messages

    /// Load messages for the current session
    func loadMessages(for session: RemoteNodeSessionDTO) async {
        guard let roomServerService else { return }

        self.session = session
        isLoading = true
        errorMessage = nil

        do {
            messages = try await roomServerService.fetchMessages(sessionID: session.id)

            // Clear unread count
            try await roomServerService.markAsRead(sessionID: session.id)
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Send a message to the current room
    func sendMessage() async {
        guard let session,
              let roomServerService,
              !composingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let text = composingText.trimmingCharacters(in: .whitespacesAndNewlines)
        composingText = ""
        isSending = true
        errorMessage = nil

        do {
            let message = try await roomServerService.postMessage(sessionID: session.id, text: text)

            // Add to local array
            messages.append(message)
            await appState?.syncCoordinator?.notifyConversationsChanged()
        } catch {
            errorMessage = error.localizedDescription
            // Restore the text so user can retry
            composingText = text
        }

        isSending = false
    }

    /// Refresh messages for current session
    func refreshMessages() async {
        guard let session else { return }
        await loadMessages(for: session)
    }

    // MARK: - Timestamp Helpers

    /// Determines if a timestamp should be shown for a message at the given index.
    /// Shows timestamp for first message or when there's a gap > 5 minutes.
    static func shouldShowTimestamp(at index: Int, in messages: [RoomMessageDTO]) -> Bool {
        guard index > 0 else { return true }

        let currentMessage = messages[index]
        let previousMessage = messages[index - 1]

        let gap = abs(Int(currentMessage.timestamp) - Int(previousMessage.timestamp))
        return gap > 300
    }
}
