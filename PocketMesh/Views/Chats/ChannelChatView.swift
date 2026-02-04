import SwiftUI
import UIKit
import PocketMeshServices
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh", category: "ChannelChatView")

/// Channel conversation view with broadcast messaging
struct ChannelChatView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.linkPreviewCache) private var linkPreviewCache

    let channel: ChannelDTO
    let parentViewModel: ChatViewModel?

    @State private var viewModel = ChatViewModel()
    @State private var keyboardObserver = KeyboardObserver()
    @State private var showingChannelInfo = false
    @State private var isAtBottom = true
    @State private var unreadCount = 0
    @State private var scrollToBottomRequest = 0
    @State private var scrollToMentionRequest = 0
    @State private var unseenMentionIDs: Set<UUID> = []
    @State private var scrollToTargetID: UUID?

    /// Mention IDs that are both unseen AND present in loaded messages
    private var reachableMentionIDs: Set<UUID> {
        let loadedIDs = Set(viewModel.displayItems.map(\.id))
        return unseenMentionIDs.intersection(loadedIDs)
    }

    /// Target message ID for scrolling (notification target takes priority over mentions)
    private var scrollTargetID: UUID? {
        if let targetID = scrollToTargetID,
           viewModel.displayItems.contains(where: { $0.id == targetID }) {
            return targetID
        }
        return reachableMentionIDs.first
    }

    @State private var selectedMessageForRepeats: MessageDTO?
    @State private var selectedMessageForPath: MessageDTO?
    @State private var selectedMessageForActions: MessageDTO?
    @State private var recentEmojisStore = RecentEmojisStore()
    @FocusState private var isInputFocused: Bool

    init(channel: ChannelDTO, parentViewModel: ChatViewModel? = nil) {
        self.channel = channel
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
            .navigationHeader(title: channelDisplayName, subtitle: channelTypeLabel)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingChannelInfo = true
                } label: {
                    Image(systemName: "info.circle")
                }
            }
        }
        .sheet(isPresented: $showingChannelInfo) {
            ChannelInfoSheet(
                channel: channel,
                onClearMessages: {
                    Task {
                        // Reload messages for this channel (now empty)
                        await viewModel.loadChannelMessages(for: channel)

                        // Refresh parent's channel list and clear cached message preview
                        if let parent = parentViewModel {
                            await parent.loadChannels(deviceID: channel.deviceID)
                            await parent.loadLastMessagePreviews()
                        }
                    }
                },
                onDelete: {
                    // Dismiss the chat view when channel is deleted
                    dismiss()
                }
            )
            .environment(\.chatViewModel, viewModel)
        }
        .sheet(item: $selectedMessageForRepeats) { message in
            RepeatDetailsSheet(message: message)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedMessageForPath) { message in
            MessagePathSheet(message: message)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedMessageForActions) { message in
            MessageActionsSheet(
                message: message,
                senderName: message.isOutgoing
                    ? (appState.connectedDevice?.nodeName ?? "Me")
                    : (message.senderNodeName ?? L10n.Chats.Chats.Message.Sender.unknown),
                recentEmojis: recentEmojisStore.recentEmojis,
                onAction: { action in
                    handleMessageAction(action, for: message)
                }
            )
        }
        .task(id: appState.servicesVersion) {
            // Capture pending scroll target before loading
            let pendingTarget = appState.pendingScrollToMessageID
            if pendingTarget != nil {
                appState.clearPendingScrollToMessage()
            }

            viewModel.configure(appState: appState, linkPreviewCache: linkPreviewCache)
            // Load contacts first so contactNameSet is populated before buildChannelSenders runs
            await viewModel.loadAllContacts(deviceID: channel.deviceID)
            await viewModel.loadChannelMessages(for: channel)
            await viewModel.loadConversations(deviceID: channel.deviceID)
            await loadUnseenMentions()

            // Trigger scroll to target message if pending
            if let targetID = pendingTarget {
                scrollToTargetID = targetID
                scrollToMentionRequest += 1
            }
        }
        .onDisappear {
            // Clear active channel for notification suppression
            appState.services?.notificationService.activeChannelIndex = nil
            appState.services?.notificationService.activeChannelDeviceID = nil

            // Refresh parent conversation list when leaving
            if let parent = parentViewModel {
                Task {
                    if let deviceID = appState.connectedDevice?.id {
                        await parent.loadConversations(deviceID: deviceID)
                        await parent.loadChannels(deviceID: deviceID)
                        await parent.loadLastMessagePreviews()
                    }
                }
            }
        }
        .onChange(of: appState.messageEventBroadcaster.newMessageCount) { _, _ in
            switch appState.messageEventBroadcaster.latestEvent {
            case .channelMessageReceived(let message, let channelIndex)
                where channelIndex == channel.index && message.deviceID == channel.deviceID:
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
                    await viewModel.loadChannelMessages(for: channel)
                }
            case .messageFailed(let messageID):
                // Only reload if this message belongs to the current channel
                // This prevents multiple reloads when several messages fail at once
                if viewModel.messages.contains(where: { $0.id == messageID }) {
                    Task {
                        await viewModel.loadChannelMessages(for: channel)
                    }
                }
            case .heardRepeatRecorded(let messageID, let count):
                // Reload to update the heard repeats count for the message
                logger.info("[REPEAT-DEBUG] ChannelChatView received heardRepeatRecorded: messageID=\(messageID), count=\(count)")
                let messageExists = viewModel.messages.contains(where: { $0.id == messageID })
                logger.info("[REPEAT-DEBUG] Message exists in viewModel.messages: \(messageExists), total messages: \(viewModel.messages.count)")
                if messageExists {
                    Task {
                        logger.info("[REPEAT-DEBUG] Reloading channel messages")
                        await viewModel.loadChannelMessages(for: channel)
                        logger.info("[REPEAT-DEBUG] Reload complete, messages count: \(viewModel.messages.count)")
                    }
                }
            case .reactionReceived(let messageID, let summary):
                if viewModel.messages.contains(where: { $0.id == messageID }) {
                    viewModel.updateReactionSummary(for: messageID, summary: summary)
                }
            default:
                break
            }
        }
        .alert(L10n.Chats.Chats.Alert.UnableToSend.title, isPresented: $viewModel.showRetryError) {
            Button(L10n.Chats.Chats.Common.ok, role: .cancel) { }
        } message: {
            Text(L10n.Chats.Chats.Alert.UnableToSend.message)
        }
    }

    // MARK: - Header

    private var channelDisplayName: String {
        channel.name.isEmpty ? L10n.Chats.Chats.Channel.defaultName(Int(channel.index)) : channel.name
    }

    private var channelTypeLabel: String {
        channel.isPublicChannel || channel.name.hasPrefix("#") ? L10n.Chats.Chats.Channel.typePublic : L10n.Chats.Chats.Channel.typePrivate
    }

    // MARK: - Mention Tracking

    private func loadUnseenMentions() async {
        guard let dataStore = appState.services?.dataStore else { return }
        do {
            unseenMentionIDs = Set(try await dataStore.fetchUnseenChannelMentionIDs(
                deviceID: channel.deviceID,
                channelIndex: channel.index
            ))
        } catch {
            logger.error("Failed to load unseen channel mentions: \(error)")
        }
    }

    private func markMentionSeen(messageID: UUID) async {
        guard unseenMentionIDs.contains(messageID),
              let dataStore = appState.services?.dataStore else { return }

        do {
            try await dataStore.markMentionSeen(messageID: messageID)
            try await dataStore.decrementChannelUnreadMentionCount(channelID: channel.id)

            unseenMentionIDs.remove(messageID)

            // Refresh parent's channel list to update badge in sidebar (important for iPad split view)
            if let parent = parentViewModel, let deviceID = appState.connectedDevice?.id {
                await parent.loadChannels(deviceID: deviceID)
            }
        } catch {
            logger.error("Failed to mark channel mention seen: \(error)")
        }
    }

    /// Mark a newly arrived mention as seen (for messages not yet in unseenMentionIDs)
    private func markNewArrivalMentionSeen(messageID: UUID) async {
        guard let dataStore = appState.services?.dataStore else { return }

        do {
            try await dataStore.markMentionSeen(messageID: messageID)
            try await dataStore.decrementChannelUnreadMentionCount(channelID: channel.id)

            // Refresh parent's channel list to update badge in sidebar
            if let parent = parentViewModel, let deviceID = appState.connectedDevice?.id {
                await parent.loadChannels(deviceID: deviceID)
            }
        } catch {
            logger.error("Failed to mark new channel mention seen: \(error)")
        }
    }

    // MARK: - Messages View

    private var messagesView: some View {
        Group {
            if !viewModel.hasLoadedOnce {
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
                    mentionTargetID: scrollTargetID,
                    onNearTop: {
                        Task {
                            await viewModel.loadOlderMessages()
                        }
                    },
                    isLoadingOlderMessages: viewModel.isLoadingOlder
                )
                .overlay(alignment: .bottomTrailing) {
                    VStack(spacing: 12) {
                        ScrollToMentionFAB(
                            isVisible: !reachableMentionIDs.isEmpty,
                            unreadMentionCount: reachableMentionIDs.count,
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
                contactName: channel.name.isEmpty ? L10n.Chats.Chats.Channel.defaultName(Int(channel.index)) : channel.name,
                contactNodeName: channel.name.isEmpty ? L10n.Chats.Chats.Channel.defaultName(Int(channel.index)) : channel.name,
                deviceName: appState.connectedDevice?.nodeName ?? "Me",
                configuration: .channel(
                    isPublic: channel.isPublicChannel || channel.name.hasPrefix("#"),
                    contacts: viewModel.conversations
                ),
                showTimestamp: item.showTimestamp,
                showDirectionGap: item.showDirectionGap,
                showSenderName: item.showSenderName,
                previewState: item.previewState,
                loadedPreview: item.loadedPreview,
                onRetry: { retryMessage(message) },
                onReaction: { emoji in
                    recentEmojisStore.recordUsage(emoji)
                    Task { await viewModel.sendReaction(emoji: emoji, to: message) }
                },
                onLongPress: { selectedMessageForActions = message },
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
            Text(L10n.Chats.Chats.Message.unavailable)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel(L10n.Chats.Chats.Message.unavailableAccessibility)
        }
    }

    private var emptyMessagesView: some View {
        VStack(spacing: 16) {
            ChannelAvatar(channel: channel, size: 80)

            Text(channel.name.isEmpty ? L10n.Chats.Chats.Channel.defaultName(Int(channel.index)) : channel.name)
                .font(.title2)
                .bold()

            Text(L10n.Chats.Chats.Channel.EmptyState.noMessages)
                .foregroundStyle(.secondary)

            Text(channel.isPublicChannel || channel.name.hasPrefix("#") ? L10n.Chats.Chats.Channel.EmptyState.publicDescription : L10n.Chats.Chats.Channel.EmptyState.privateDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .onAppear {
            logger.info("emptyMessagesView: appeared for channel \(channel.index), isLoading=\(viewModel.isLoading)")
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

    private func showRepeatDetails(for message: MessageDTO) {
        selectedMessageForRepeats = message
    }

    private func retryMessage(_ message: MessageDTO) {
        Task {
            await viewModel.retryChannelMessage(message)
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
        case .repeatDetails:
            showRepeatDetails(for: message)
        case .viewPath:
            selectedMessageForPath = message
        case .delete:
            deleteMessage(message)
        }
    }

    private func buildReplyText(for message: MessageDTO) -> String {
        let mentionName = message.senderNodeName ?? L10n.Chats.Chats.Message.Sender.unknown
        let preview = String(message.text.prefix(20))
        let hasMore = message.text.count > 20
        let suffix = hasMore ? ".." : ""
        let mention = MentionUtilities.createMention(for: mentionName)
        return "\(mention)\"\(preview)\(suffix)\"\n"
    }

    // MARK: - Input Bar

    /// Calculate max channel message length based on device's advertised name
    private var maxChannelMessageLength: Int {
        let nodeNameLength = appState.connectedDevice?.nodeName.count ?? 0
        return ProtocolLimits.maxChannelMessageLength(nodeNameLength: nodeNameLength)
    }

    private var inputBar: some View {
        MentionInputBar(
            text: $viewModel.composingText,
            isFocused: $isInputFocused,
            placeholder: channel.isPublicChannel || channel.name.hasPrefix("#") ? L10n.Chats.Chats.Channel.typePublic : L10n.Chats.Chats.Channel.typePrivate,
            maxCharacters: maxChannelMessageLength,
            contacts: viewModel.allContacts
        ) {
            // Force scroll to bottom on user send (before message is added)
            scrollToBottomRequest += 1
            Task {
                await viewModel.sendChannelMessage()
            }
        }
    }

    // MARK: - Mention Suggestions

    private var mentionSuggestions: [ContactDTO] {
        guard let query = MentionUtilities.detectActiveMention(in: viewModel.composingText) else {
            return []
        }
        let combined = viewModel.allContacts + viewModel.channelSenders
        return MentionUtilities.filterContacts(combined, query: query)
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
        ChannelChatView(channel: ChannelDTO(from: Channel(
            deviceID: UUID(),
            index: 1,
            name: "General"
        )))
    }
    .environment(\.appState, AppState())
}
