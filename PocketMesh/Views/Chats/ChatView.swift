import SwiftUI
import PocketMeshServices
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh", category: "ChatView")

/// Individual chat conversation view with iMessage-style UI
struct ChatView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.linkPreviewCache) private var linkPreviewCache

    @State private var contact: ContactDTO
    let parentViewModel: ChatViewModel?

    @State private var viewModel = ChatViewModel()
    @State private var keyboardObserver = KeyboardObserver()
    @State private var showingContactInfo = false
    @State private var isAtBottom = true
    @State private var unreadCount = 0
    @State private var scrollToBottomRequest = 0
    @State private var unreadMentionCount = 0
    @State private var scrollToMentionRequest = 0
    @State private var unseenMentionIDs: Set<UUID> = []
    @State private var selectedMessageForPath: MessageDTO?
    @FocusState private var isInputFocused: Bool

    init(contact: ContactDTO, parentViewModel: ChatViewModel? = nil) {
        self._contact = State(initialValue: contact)
        self.parentViewModel = parentViewModel
    }

    var body: some View {
        messagesView
            .safeAreaInset(edge: .bottom, spacing: 8) {
                inputBar
                    .floatingKeyboardAware()
            }
            .ignoreKeyboardOnIPad()
            .environment(keyboardObserver)
            .overlay(alignment: .bottom) {
                mentionSuggestionsOverlay
            }
            .navigationTitle(contact.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                headerView
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingContactInfo = true
                } label: {
                    Image(systemName: "info.circle")
                }
            }
        }
        .sheet(isPresented: $showingContactInfo, onDismiss: {
            Task {
                await refreshContact()
            }
        }, content: {
            NavigationStack {
                ContactDetailView(contact: contact, showFromDirectChat: true)
            }
        })
        .sheet(item: $selectedMessageForPath) { message in
            MessagePathSheet(message: message)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task(id: appState.servicesVersion) {
            viewModel.configure(appState: appState, linkPreviewCache: linkPreviewCache)
            await viewModel.loadMessages(for: contact)
            await viewModel.loadConversations(deviceID: contact.deviceID)
            await viewModel.loadAllContacts(deviceID: contact.deviceID)
            viewModel.loadDraftIfExists()
            await loadUnseenMentions()
        }
        .onDisappear {
            // Clear active conversation for notification suppression
            appState.services?.notificationService.activeContactID = nil

            // Refresh parent conversation list when leaving
            if let parent = parentViewModel {
                Task {
                    if let deviceID = appState.connectedDevice?.id {
                        await parent.loadConversations(deviceID: deviceID)
                        await parent.loadLastMessagePreviews()
                    }
                }
            }
        }
        .onChange(of: appState.messageEventBroadcaster.newMessageCount) { _, _ in
            switch appState.messageEventBroadcaster.latestEvent {
            case .directMessageReceived(let message, _) where message.contactID == contact.id:
                // Optimistic insert: add message immediately so ChatTableView sees new count
                // No full reload needed - appendMessageIfNew handles local state
                viewModel.appendMessageIfNew(message)
                // Link previews deferred - fetching during active message receipt causes
                // WKWebView process spawning that blocks main thread and causes scroll jank.
                // Previews will be fetched by batch mechanism when message flow settles.
                // Handle self-mention: if at bottom, mark seen immediately; otherwise reload unseen
                if message.containsSelfMention {
                    Task {
                        if isAtBottom {
                            // User will see the message immediately, mark it seen
                            await markNewArrivalMentionSeen(messageID: message.id)
                        } else {
                            await loadUnseenMentions()
                        }
                    }
                }
            case .messageStatusUpdated:
                // Reload to pick up status changes (Sent -> Delivered, etc.)
                Task {
                    await viewModel.loadMessages(for: contact)
                }
            case .messageFailed(let messageID):
                // Only reload if this message belongs to the current conversation
                // This prevents multiple reloads when several messages fail at once
                if viewModel.messages.contains(where: { $0.id == messageID }) {
                    Task {
                        await viewModel.loadMessages(for: contact)
                    }
                }
            case .routingChanged(let contactID, _) where contactID == contact.id:
                // Refresh contact to update header when routing changes
                Task {
                    await refreshContact()
                }
            case .messageRetrying:
                // Reload to pick up retry status changes
                Task {
                    await viewModel.loadMessages(for: contact)
                }
            default:
                break
            }
        }
        .alert("Unable to Send", isPresented: $viewModel.showRetryError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please ensure your device is connected and try again.")
        }
    }

    // MARK: - Contact Refresh

    private func refreshContact() async {
        if let updated = try? await appState.services?.dataStore.fetchContact(id: contact.id) {
            contact = updated
        }
    }

    // MARK: - Mention Tracking

    private func loadUnseenMentions() async {
        guard let dataStore = appState.services?.dataStore else { return }
        do {
            unseenMentionIDs = Set(try await dataStore.fetchUnseenMentionIDs(contactID: contact.id))
            unreadMentionCount = unseenMentionIDs.count
        } catch {
            logger.error("Failed to load unseen mentions: \(error)")
        }
    }

    private func markMentionSeen(messageID: UUID) async {
        guard unseenMentionIDs.contains(messageID),
              let dataStore = appState.services?.dataStore else { return }

        do {
            try await dataStore.markMentionSeen(messageID: messageID)
            try await dataStore.decrementUnreadMentionCount(contactID: contact.id)

            unseenMentionIDs.remove(messageID)
            unreadMentionCount = max(0, unreadMentionCount - 1)

            // Refresh parent's conversation list to update badge in sidebar (important for iPad split view)
            if let parent = parentViewModel, let deviceID = appState.connectedDevice?.id {
                await parent.loadConversations(deviceID: deviceID)
            }
        } catch {
            logger.error("Failed to mark mention seen: \(error)")
        }
    }

    /// Mark a newly arrived mention as seen (for messages not yet in unseenMentionIDs)
    private func markNewArrivalMentionSeen(messageID: UUID) async {
        guard let dataStore = appState.services?.dataStore else { return }

        do {
            try await dataStore.markMentionSeen(messageID: messageID)
            try await dataStore.decrementUnreadMentionCount(contactID: contact.id)

            // Refresh parent's conversation list to update badge in sidebar
            if let parent = parentViewModel, let deviceID = appState.connectedDevice?.id {
                await parent.loadConversations(deviceID: deviceID)
            }
        } catch {
            logger.error("Failed to mark new mention seen: \(error)")
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 0) {
            Text(contact.displayName)
                .font(.headline)

            Text(connectionStatus)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var connectionStatus: String {
        if contact.isFloodRouted {
            return "Flood routing"
        } else if contact.outPathLength >= 0 {
            return "Direct • \(contact.outPathLength) hops"
        }
        return "Unknown route"
    }

    // MARK: - Messages View

    private var messagesView: some View {
        Group {
            if viewModel.isLoading && viewModel.messages.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.messages.isEmpty {
                emptyMessagesView
            } else {
                ChatTableView(
                    items: viewModel.displayItems,
                    cellContent: { displayItem in
                        messageBubble(for: displayItem)
                    },
                    isAtBottom: $isAtBottom,
                    unreadCount: $unreadCount,
                    scrollToBottomRequest: $scrollToBottomRequest,
                    scrollToMentionRequest: $scrollToMentionRequest,
                    isUnseenMention: { displayItem in
                        displayItem.containsSelfMention && !displayItem.mentionSeen && unseenMentionIDs.contains(displayItem.id)
                    },
                    onMentionBecameVisible: { messageID in
                        Task {
                            await markMentionSeen(messageID: messageID)
                        }
                    },
                    mentionTargetID: unseenMentionIDs.first
                )
                .overlay(alignment: .bottomTrailing) {
                    VStack(spacing: 12) {
                        ScrollToMentionFAB(
                            isVisible: unreadMentionCount > 0,
                            unreadMentionCount: unreadMentionCount,
                            onTap: { scrollToMentionRequest += 1 }
                        )

                        ScrollToBottomFAB(
                            isVisible: !isAtBottom,
                            unreadCount: unreadCount,
                            onTap: { scrollToBottomRequest += 1 }
                        )
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    @ViewBuilder
    private func messageBubble(for item: MessageDisplayItem) -> some View {
        if let message = viewModel.message(for: item) {
            UnifiedMessageBubble(
                message: message,
                contactName: contact.displayName,
                contactNodeName: contact.name,
                deviceName: appState.connectedDevice?.nodeName ?? "Me",
                configuration: .directMessage,
                showTimestamp: item.showTimestamp,
                showDirectionGap: item.showDirectionGap,
                previewState: item.previewState,
                loadedPreview: item.loadedPreview,
                onRetry: { retryMessage(message) },
                onReply: { replyText in
                    setReplyText(replyText)
                },
                onDelete: {
                    deleteMessage(message)
                },
                onShowPath: { selectedMessageForPath = $0 },
                onSendAgain: {
                    sendAgain(message)
                },
                onRequestPreviewFetch: {
                    viewModel.requestPreviewFetch(for: message.id)
                },
                onManualPreviewFetch: {
                    Task {
                        await viewModel.manualFetchPreview(for: message.id)
                    }
                }
            )
        } else {
            // ViewModel logs the warning for data inconsistency
            Text("Message unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Message could not be loaded")
        }
    }

    private var emptyMessagesView: some View {
        VStack(spacing: 16) {
            ContactAvatar(contact: contact, size: 80)

            Text(contact.displayName)
                .font(.title2)
                .bold()

            Text("Start a conversation")
                .foregroundStyle(.secondary)

            if contact.hasLocation {
                Label("Has location", systemImage: "location.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func setReplyText(_ text: String) {
        viewModel.composingText = text
        isInputFocused = true
    }

    private func deleteMessage(_ message: MessageDTO) {
        Task {
            await viewModel.deleteMessage(message)
        }
    }

    private func retryMessage(_ message: MessageDTO) {
        logger.info("retryMessage called for message: \(message.id)")
        Task {
            await viewModel.retryMessage(message)
        }
    }

    private func sendAgain(_ message: MessageDTO) {
        Task {
            await viewModel.sendAgain(message)
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        MentionInputBar(
            text: $viewModel.composingText,
            isFocused: $isInputFocused,
            placeholder: "Private Message",
            maxCharacters: ProtocolLimits.maxDirectMessageLength,
            contacts: viewModel.allContacts
        ) {
            // Force scroll to bottom on user send (before message is added)
            scrollToBottomRequest += 1
            Task {
                await viewModel.sendMessage()
            }
        }
    }

    // MARK: - Mention Suggestions

    private var mentionSuggestions: [ContactDTO] {
        guard let query = MentionUtilities.detectActiveMention(in: viewModel.composingText) else {
            return []
        }
        return MentionUtilities.filterContacts(viewModel.allContacts, query: query)
    }

    @ViewBuilder
    private var mentionSuggestionsOverlay: some View {
        Group {
            if !mentionSuggestions.isEmpty {
                VStack {
                    Spacer()
                    MentionSuggestionView(contacts: mentionSuggestions) { contact in
                        insertMention(for: contact)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 60)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .bottom)
                                .combined(with: .opacity)
                                .combined(with: .scale(scale: 0.95, anchor: .bottom)),
                            removal: .move(edge: .bottom).combined(with: .opacity)
                        )
                    )
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: mentionSuggestions.isEmpty)
    }

    private func insertMention(for contact: ContactDTO) {
        guard let query = MentionUtilities.detectActiveMention(in: viewModel.composingText) else { return }

        let searchPattern = "@" + query
        if let range = viewModel.composingText.range(of: searchPattern, options: .backwards) {
            let mention = MentionUtilities.createMention(for: contact.name)
            viewModel.composingText.replaceSubrange(range, with: mention + " ")
        }
    }
}

#Preview {
    NavigationStack {
        ChatView(contact: ContactDTO(from: Contact(
            deviceID: UUID(),
            publicKey: Data(repeating: 0x42, count: 32),
            name: "Alice"
        )))
    }
    .environment(\.appState, AppState())
}
