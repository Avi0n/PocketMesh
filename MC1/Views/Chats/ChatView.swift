import SwiftUI
import UIKit
import PocketMeshServices
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh", category: "ChatView")

/// Individual chat conversation view with iMessage-style UI
struct ChatView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.linkPreviewCache) private var linkPreviewCache

    @State private var contact: ContactDTO
    let parentViewModel: ChatViewModel?

    @State private var viewModel = ChatViewModel()
    @State private var showingContactInfo = false
    @State private var isAtBottom = true
    @State private var unreadCount = 0
    @State private var scrollToBottomRequest = 0
    @State private var scrollToMentionRequest = 0
    @State private var unseenMentionIDs: [UUID] = []
    @State private var scrollToTargetID: UUID?
    @State private var mentionScrollTask: Task<Void, Never>?
    @State private var scrollToDividerRequest = 0
    @State private var isDividerVisible = false

    @State private var selectedMessageForActions: MessageDTO?
    @State private var recentEmojisStore = RecentEmojisStore()
    @State private var imageViewerData: ImageViewerData?
    @State private var eventCursor: Int?
    @FocusState private var isInputFocused: Bool

    @AppStorage("showInlineImages") private var showInlineImages = true
    @AppStorage("autoPlayGIFs") private var autoPlayGIFs = true
    @AppStorage("showIncomingPath") private var showIncomingPath = false
    @AppStorage("showIncomingHopCount") private var showIncomingHopCount = false

    init(contact: ContactDTO, parentViewModel: ChatViewModel? = nil) {
        self._contact = State(initialValue: contact)
        self.parentViewModel = parentViewModel
    }

    var body: some View {
        ChatMessagesContent(
            viewModel: viewModel,
            contact: contact,
            deviceName: appState.connectedDevice?.nodeName ?? "Me",
            showInlineImages: showInlineImages,
            autoPlayGIFs: autoPlayGIFs,
            showIncomingPath: showIncomingPath,
            showIncomingHopCount: showIncomingHopCount,
            isAtBottom: $isAtBottom,
            unreadCount: $unreadCount,
            scrollToBottomRequest: $scrollToBottomRequest,
            scrollToMentionRequest: $scrollToMentionRequest,
            unseenMentionIDs: unseenMentionIDs,
            scrollToTargetID: scrollToTargetID,
            newMessagesDividerMessageID: viewModel.newMessagesDividerMessageID,
            scrollToDividerRequest: $scrollToDividerRequest,
            isDividerVisible: $isDividerVisible,
            selectedMessageForActions: $selectedMessageForActions,
            imageViewerData: $imageViewerData,
            onMentionSeen: { await markMentionSeen(messageID: $0) },
            onScrollToMention: { scrollToNextMention() }
        )
            .safeAreaInset(edge: .bottom, spacing: 8) {
                inputBar
            }
            .overlay(alignment: .bottom) {
                mentionSuggestionsOverlay
            }
            .navigationHeader(title: contact.displayName, subtitle: connectionStatus)
        .toolbar {
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
        .sheet(item: $selectedMessageForActions) { message in
            MessageActionsSheet(
                message: message,
                senderName: message.isOutgoing
                    ? (appState.connectedDevice?.nodeName ?? "Me")
                    : contact.displayName,
                recentEmojis: recentEmojisStore.recentEmojis,
                onAction: { action in
                    handleMessageAction(action, for: message)
                }
            )
            .environment(\.horizontalSizeClass, horizontalSizeClass)
        }
        .fullScreenCover(item: $imageViewerData) { data in
            FullScreenImageViewer(data: data)
        }
        .onAppear {
            eventCursor = appState.messageEventBroadcaster.currentEventSequence
        }
        .task(id: appState.servicesVersion) {
            // Capture pending scroll target before loading
            let pendingTarget = appState.navigation.pendingScrollToMessageID
            if pendingTarget != nil {
                appState.navigation.clearPendingScrollToMessage()
            }

            viewModel.configure(appState: appState, linkPreviewCache: linkPreviewCache)
            await viewModel.loadMessages(for: contact)
            await viewModel.loadConversations(deviceID: contact.deviceID)
            await viewModel.loadAllContacts(deviceID: contact.deviceID)
            viewModel.loadDraftIfExists()
            await loadUnseenMentions()

            // Trigger scroll to target message if pending (notification deeplink)
            if let targetID = pendingTarget {
                scrollToTargetID = targetID
                scrollToMentionRequest += 1
            }
        }
        .onDisappear {
            mentionScrollTask?.cancel()
            mentionScrollTask = nil

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
            guard let cursor = eventCursor else { return }
            let (events, newCursor, droppedEvents) = appState.messageEventBroadcaster.events(after: cursor)
            eventCursor = newCursor
            var needsReload = droppedEvents
            var needsContactRefresh = false
            for event in events {
                switch event {
                case .directMessageReceived(let message, _) where message.contactID == contact.id:
                    viewModel.appendMessageIfNew(message)
                    if message.containsSelfMention {
                        Task {
                            if isAtBottom {
                                await markNewArrivalMentionSeen(messageID: message.id)
                            } else {
                                await loadUnseenMentions()
                            }
                        }
                    }
                case .messageStatusUpdated, .messageRetrying:
                    needsReload = true
                case .messageFailed(let messageID):
                    if viewModel.messages.contains(where: { $0.id == messageID }) {
                        needsReload = true
                    }
                case .routingChanged(let contactID, _) where contactID == contact.id:
                    needsContactRefresh = true
                case .reactionReceived(let messageID, let summary):
                    if viewModel.messages.contains(where: { $0.id == messageID }) {
                        viewModel.updateReactionSummary(for: messageID, summary: summary)
                    }
                default:
                    break
                }
            }
            if needsReload {
                Task { await viewModel.loadMessages(for: contact) }
            }
            if needsContactRefresh || droppedEvents {
                Task { await refreshContact() }
            }
            if droppedEvents {
                Task { await loadUnseenMentions() }
            }
        }
        .alert(L10n.Chats.Chats.Alert.UnableToSend.title, isPresented: $viewModel.showRetryError) {
            Button(L10n.Chats.Chats.Common.ok, role: .cancel) { }
        } message: {
            Text(L10n.Chats.Chats.Alert.UnableToSend.message)
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
            unseenMentionIDs = try await dataStore.fetchUnseenMentionIDs(contactID: contact.id)
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

            unseenMentionIDs.removeAll { $0 == messageID }

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

    private func scrollToNextMention() {
        guard let targetID = unseenMentionIDs.first else { return }

        if viewModel.displayItems.contains(where: { $0.id == targetID }) {
            scrollToTargetID = targetID
            scrollToMentionRequest += 1
            return
        }

        mentionScrollTask?.cancel()
        mentionScrollTask = Task {
            do {
                let deadline = ContinuousClock.now + .seconds(10)
                while !viewModel.displayItems.contains(where: { $0.id == targetID }) {
                    guard viewModel.hasMoreMessages else {
                        logger.warning("Mention \(targetID) not found after exhausting history, removing")
                        if let dataStore = appState.services?.dataStore {
                            try? await dataStore.markMentionSeen(messageID: targetID)
                        }
                        unseenMentionIDs.removeAll { $0 == targetID }
                        break
                    }
                    guard unseenMentionIDs.contains(targetID) else { break }
                    guard ContinuousClock.now < deadline else {
                        logger.warning("Mention \(targetID) paging timed out")
                        break
                    }
                    if viewModel.isLoadingOlder {
                        try await Task.sleep(for: .milliseconds(50))
                        continue
                    }
                    await viewModel.loadOlderMessages()
                    try Task.checkCancellation()
                }
                if viewModel.displayItems.contains(where: { $0.id == targetID }) {
                    scrollToTargetID = targetID
                    scrollToMentionRequest += 1
                }
            } catch is CancellationError {
                // Expected when view disappears during paging
            } catch {
                logger.error("Failed to scroll to mention: \(error)")
            }
        }
    }

    private var connectionStatus: String {
        if contact.isFloodRouted {
            return L10n.Chats.Chats.ConnectionStatus.floodRouting
        } else {
            return L10n.Chats.Chats.ConnectionStatus.direct(contact.pathHopCount)
        }
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

    private func sendAgain(_ message: MessageDTO) {
        Task {
            await viewModel.sendAgain(message)
        }
    }

    // MARK: - Message Actions

    private func handleMessageAction(_ action: MessageAction, for message: MessageDTO) {
        switch action {
        case .react(let emoji):
            recentEmojisStore.recordUsage(emoji)
            Task { await viewModel.sendReaction(emoji: emoji, to: message) }
        case .reply:
            let replyText = buildReplyText(for: message)
            setReplyText(replyText)
        case .copy:
            UIPasteboard.general.string = message.text
        case .sendAgain:
            sendAgain(message)
        case .blockSender:
            break  // DMs don't support blocking
        case .delete:
            deleteMessage(message)
        }
    }

    private func buildReplyText(for message: MessageDTO) -> String {
        MentionUtilities.buildReplyText(mentionName: contact.name, messageText: message.text)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        ChatInputBar(
            text: $viewModel.composingText,
            isFocused: $isInputFocused,
            placeholder: L10n.Chats.Chats.Input.Placeholder.directMessage,
            maxBytes: ProtocolLimits.maxDirectMessageLength,
            isEncrypted: true
        ) { text in
            scrollToBottomRequest += 1
            Task { await viewModel.sendMessage(text: text) }
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

// MARK: - Chat Messages Content

private struct ChatMessagesContent: View {
    @Bindable var viewModel: ChatViewModel
    let contact: ContactDTO
    let deviceName: String
    let showInlineImages: Bool
    let autoPlayGIFs: Bool
    let showIncomingPath: Bool
    let showIncomingHopCount: Bool
    @Binding var isAtBottom: Bool
    @Binding var unreadCount: Int
    @Binding var scrollToBottomRequest: Int
    @Binding var scrollToMentionRequest: Int
    let unseenMentionIDs: [UUID]
    let scrollToTargetID: UUID?
    let newMessagesDividerMessageID: UUID?
    @Binding var scrollToDividerRequest: Int
    @Binding var isDividerVisible: Bool
    @Binding var selectedMessageForActions: MessageDTO?
    @Binding var imageViewerData: ImageViewerData?
    let onMentionSeen: (UUID) async -> Void
    let onScrollToMention: () -> Void

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @State private var hasDismissedDividerFAB = false

    private var showDividerFAB: Bool {
        newMessagesDividerMessageID != nil && !isDividerVisible && !hasDismissedDividerFAB
    }

    var body: some View {
        Group {
            if !viewModel.hasLoadedOnce {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.messages.isEmpty {
                ChatEmptyMessagesView(contact: contact)
            } else {
                let mentionIDSet = Set(unseenMentionIDs)
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
                        displayItem.containsSelfMention && !displayItem.mentionSeen && mentionIDSet.contains(displayItem.id)
                    },
                    onMentionBecameVisible: { messageID in
                        Task {
                            await onMentionSeen(messageID)
                        }
                    },
                    mentionTargetID: scrollToTargetID,
                    scrollToDividerRequest: $scrollToDividerRequest,
                    dividerItemID: newMessagesDividerMessageID,
                    isDividerVisible: $isDividerVisible,
                    onNearTop: {
                        Task {
                            await viewModel.loadOlderMessages()
                        }
                    },
                    isLoadingOlderMessages: viewModel.isLoadingOlder
                )
                .overlay(alignment: .bottomTrailing) {
                    VStack(spacing: 12) {
                        if showDividerFAB {
                            ScrollToDividerButton(
                                onTap: {
                                    scrollToDividerRequest += 1
                                    hasDismissedDividerFAB = true
                                }
                            )
                            .transition(.scale.combined(with: .opacity))
                        }

                        if !unseenMentionIDs.isEmpty {
                            ScrollToMentionButton(
                                unreadMentionCount: unseenMentionIDs.count,
                                onTap: { onScrollToMention() }
                            )
                            .transition(.scale.combined(with: .opacity))
                        }

                        ScrollToBottomButton(
                            isVisible: !isAtBottom,
                            unreadCount: unreadCount,
                            onTap: { scrollToBottomRequest += 1 }
                        )
                    }
                    .animation(.snappy(duration: 0.2), value: showDividerFAB)
                    .animation(.snappy(duration: 0.2), value: unseenMentionIDs.isEmpty)
                    .padding(.trailing, 16)
                    .padding(.bottom, 8)
                }
                .onChange(of: newMessagesDividerMessageID) { _, _ in
                    hasDismissedDividerFAB = false
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
                deviceName: deviceName,
                configuration: .directMessage,
                displayState: MessageDisplayState(
                    showTimestamp: item.showTimestamp,
                    showDirectionGap: item.showDirectionGap,
                    showSenderName: item.showSenderName,
                    showNewMessagesDivider: item.showNewMessagesDivider,
                    detectedURL: item.detectedURL,
                    previewState: item.previewState,
                    loadedPreview: item.loadedPreview,
                    isImageURL: item.isImageURL,
                    decodedImage: viewModel.decodedImage(for: message.id),
                    decodedPreviewImage: viewModel.decodedPreviewImage(for: message.id),
                    decodedPreviewIcon: viewModel.decodedPreviewIcon(for: message.id),
                    isGIF: viewModel.isGIFImage(for: message.id),
                    showInlineImages: showInlineImages,
                    autoPlayGIFs: autoPlayGIFs,
                    showIncomingPath: showIncomingPath,
                    showIncomingHopCount: showIncomingHopCount,
                    formattedText: viewModel.formattedText(
                        for: message.id,
                        text: message.text,
                        isOutgoing: message.isOutgoing,
                        currentUserName: deviceName,
                        isHighContrast: colorSchemeContrast == .increased
                    )
                ),
                callbacks: MessageBubbleCallbacks(
                    onRetry: {
                        logger.info("retryMessage called for message: \(message.id)")
                        Task { await viewModel.retryMessage(message) }
                    },
                    onLongPress: { selectedMessageForActions = message },
                    onImageTap: {
                        if let data = viewModel.imageData(for: message.id) {
                            imageViewerData = ImageViewerData(
                                imageData: data,
                                isGIF: false
                            )
                        }
                    },
                    onRetryImageFetch: {
                        Task { await viewModel.retryImageFetch(for: message.id) }
                    },
                    onRequestPreviewFetch: {
                        if item.isImageURL && showInlineImages {
                            viewModel.requestImageFetch(for: message.id, showInlineImages: showInlineImages)
                        } else {
                            viewModel.requestPreviewFetch(for: message.id)
                        }
                    },
                    onManualPreviewFetch: {
                        Task {
                            await viewModel.manualFetchPreview(for: message.id)
                        }
                    }
                )
            )
        } else {
            Text(L10n.Chats.Chats.Message.unavailable)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(L10n.Chats.Chats.Message.unavailableAccessibility)
        }
    }
}

// MARK: - Chat Empty Messages View

private struct ChatEmptyMessagesView: View {
    let contact: ContactDTO

    var body: some View {
        VStack(spacing: 16) {
            ContactAvatar(contact: contact, size: 80)

            Text(contact.displayName)
                .font(.title2)
                .bold()

            Text(L10n.Chats.Chats.EmptyState.startConversation)
                .foregroundStyle(.secondary)

            if contact.hasLocation {
                Label(L10n.Chats.Chats.ContactInfo.hasLocation, systemImage: "location.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
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
