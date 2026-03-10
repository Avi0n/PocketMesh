import SwiftUI
import UIKit
import PocketMeshServices
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh", category: "ChannelChatView")

private struct BlockSenderContext: Identifiable {
    let id = UUID()
    let senderName: String
}

/// Channel conversation view with broadcast messaging
struct ChannelChatView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.linkPreviewCache) private var linkPreviewCache

    let channel: ChannelDTO
    let parentViewModel: ChatViewModel?

    @State private var viewModel = ChatViewModel()
    @State private var showingChannelInfo = false
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
    @State private var blockSenderContext: BlockSenderContext?
    @State private var recentEmojisStore = RecentEmojisStore()
    @State private var imageViewerData: ImageViewerData?
    @State private var mentionSenderOrder: [String: UInt32]?
    @State private var eventCursor: Int?
    @FocusState private var isInputFocused: Bool

    @AppStorage("showInlineImages") private var showInlineImages = true
    @AppStorage("autoPlayGIFs") private var autoPlayGIFs = true
    @AppStorage("showIncomingPath") private var showIncomingPath = false
    @AppStorage("showIncomingHopCount") private var showIncomingHopCount = false

    init(channel: ChannelDTO, parentViewModel: ChatViewModel? = nil) {
        self.channel = channel
        self.parentViewModel = parentViewModel
    }

    var body: some View {
        messagesView
            .safeAreaInset(edge: .bottom, spacing: 8) {
                inputBar
            }
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
            .environment(\.horizontalSizeClass, horizontalSizeClass)
        }
        .sheet(item: $blockSenderContext) { context in
            BlockSenderSheet(
                senderName: context.senderName,
                deviceID: channel.deviceID
            ) { blockedContactIDs in
                Task {
                    await performBlock(senderName: context.senderName, contactIDs: blockedContactIDs)
                }
            }
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
            // Load contacts first so contactNameSet is populated before buildChannelSenders runs
            await viewModel.loadAllContacts(deviceID: channel.deviceID)
            await viewModel.loadChannelMessages(for: channel)
            await viewModel.loadConversations(deviceID: channel.deviceID)
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
        .onChange(of: isMentionActive) { _, isActive in
            if isActive {
                mentionSenderOrder = viewModel.channelSenderOrder
            } else {
                mentionSenderOrder = nil
            }
        }
        .onChange(of: appState.messageEventBroadcaster.newMessageCount) { _, _ in
            guard let cursor = eventCursor else { return }
            let (events, newCursor, droppedEvents) = appState.messageEventBroadcaster.events(after: cursor)
            eventCursor = newCursor
            var needsReload = droppedEvents
            for event in events {
                switch event {
                case .channelMessageReceived(let message, let channelIndex)
                    where channelIndex == channel.index && message.deviceID == channel.deviceID:
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
                case .messageStatusUpdated:
                    needsReload = true
                case .messageFailed(let messageID):
                    if viewModel.messages.contains(where: { $0.id == messageID }) {
                        needsReload = true
                    }
                case .heardRepeatRecorded(let messageID, _):
                    if viewModel.messages.contains(where: { $0.id == messageID }) {
                        needsReload = true
                    }
                case .reactionReceived(let messageID, let summary):
                    if viewModel.messages.contains(where: { $0.id == messageID }) {
                        viewModel.updateReactionSummary(for: messageID, summary: summary)
                    }
                default:
                    break
                }
            }
            if needsReload {
                Task { await viewModel.loadChannelMessages(for: channel) }
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

    // MARK: - Header

    private var channelDisplayName: String {
        channel.name.isEmpty ? L10n.Chats.Chats.Channel.defaultName(Int(channel.index)) : channel.name
    }

    private var channelTypeLabel: String {
        channel.isPublicChannel || channel.name.hasPrefix("#") ? L10n.Chats.Chats.Channel.typePublic : L10n.Chats.Chats.Channel.typePrivate
    }

    // MARK: - Mention Tracking

    private func loadUnseenMentions() async {
        guard let services = appState.services else { return }
        do {
            let allIDs = try await services.dataStore.fetchUnseenChannelMentionIDs(
                deviceID: channel.deviceID,
                channelIndex: channel.index
            )

            let blockedNames = await services.syncCoordinator.blockedSenderNames()
            if blockedNames.isEmpty {
                unseenMentionIDs = allIDs
                return
            }

            var filteredIDs: [UUID] = []
            for id in allIDs {
                do {
                    if let message = try await services.dataStore.fetchMessage(id: id),
                       let senderName = message.senderNodeName,
                       blockedNames.contains(senderName) {
                        try await services.dataStore.markMentionSeen(messageID: id)
                        continue
                    }
                } catch {
                    logger.error("Failed to check/filter mention \(id): \(error)")
                }
                filteredIDs.append(id)
            }
            unseenMentionIDs = filteredIDs
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

            unseenMentionIDs.removeAll { $0 == messageID }

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

    // MARK: - Mention Navigation

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

    // MARK: - Messages View

    private var messagesView: some View {
        ChannelMessagesContent(
            viewModel: viewModel,
            channel: channel,
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
            recentEmojisStore: recentEmojisStore,
            imageViewerData: $imageViewerData,
            onMentionSeen: { await markMentionSeen(messageID: $0) },
            onScrollToMention: { scrollToNextMention() },
            onRetryMessage: { retryMessage($0) }
        )
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
        Task {
            await viewModel.retryChannelMessage(message)
        }
    }

    private func sendAgain(_ message: MessageDTO) {
        Task {
            await viewModel.sendAgain(message)
        }
    }

    // MARK: - Blocking

    private func performBlock(senderName: String, contactIDs: Set<UUID>) async {
        guard let services = appState.services else { return }

        // Save the blocked channel sender name
        let dto = BlockedChannelSenderDTO(name: senderName, deviceID: channel.deviceID)
        do {
            try await services.dataStore.saveBlockedChannelSender(dto)
        } catch {
            logger.error("Failed to save blocked channel sender: \(error)")
            return
        }

        // Block selected contacts
        for contactID in contactIDs {
            do {
                try await services.contactService.updateContactPreferences(
                    contactID: contactID,
                    isBlocked: true
                )
            } catch {
                logger.error("Failed to block contact \(contactID): \(error)")
            }
        }

        // Refresh cache so SyncCoordinator has updated blocked names for real-time filtering
        await services.syncCoordinator.refreshBlockedContactsCache(
            deviceID: channel.deviceID,
            dataStore: services.dataStore
        )

        // Refresh contacts if any were blocked
        if !contactIDs.isEmpty {
            await services.syncCoordinator.notifyContactsChanged()
        }

        // Reload messages to apply filter
        await viewModel.loadChannelMessages(for: channel)

        // Refresh chat list previews
        await services.syncCoordinator.notifyConversationsChanged()
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
            guard let name = message.senderNodeName else { return }
            // Delay to let the message actions sheet dismiss before presenting the block sheet
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                blockSenderContext = BlockSenderContext(senderName: name)
            }
        case .delete:
            deleteMessage(message)
        }
    }

    private func buildReplyText(for message: MessageDTO) -> String {
        let mentionName = message.senderNodeName ?? L10n.Chats.Chats.Message.Sender.unknown
        return MentionUtilities.buildReplyText(mentionName: mentionName, messageText: message.text)
    }

    // MARK: - Input Bar

    private var maxChannelMessageLength: Int {
        let nodeNameByteCount = appState.connectedDevice?.nodeName.utf8.count ?? 0
        return ProtocolLimits.maxChannelMessageLength(nodeNameByteCount: nodeNameByteCount)
    }

    private var inputBar: some View {
        ChatInputBar(
            text: $viewModel.composingText,
            isFocused: $isInputFocused,
            placeholder: channel.isPublicChannel || channel.name.hasPrefix("#") ? L10n.Chats.Chats.Channel.typePublic : L10n.Chats.Chats.Channel.typePrivate,
            maxBytes: maxChannelMessageLength,
            isEncrypted: channel.isEncryptedChannel
        ) { text in
            scrollToBottomRequest += 1
            Task { await viewModel.sendChannelMessage(text: text) }
        }
    }

    // MARK: - Mention Suggestions

    private var isMentionActive: Bool {
        MentionUtilities.detectActiveMention(in: viewModel.composingText) != nil
    }

    private var mentionSuggestions: [ContactDTO] {
        guard let query = MentionUtilities.detectActiveMention(in: viewModel.composingText) else {
            return []
        }
        let combined = viewModel.allContacts + viewModel.channelSenders
        let order = mentionSenderOrder ?? viewModel.channelSenderOrder
        return MentionUtilities.filterContacts(combined, query: query, senderOrder: order)
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

// MARK: - Channel Messages Content

private struct ChannelMessagesContent: View {
    @Bindable var viewModel: ChatViewModel
    let channel: ChannelDTO
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
    let recentEmojisStore: RecentEmojisStore
    @Binding var imageViewerData: ImageViewerData?
    let onMentionSeen: (UUID) async -> Void
    let onScrollToMention: () -> Void
    let onRetryMessage: (MessageDTO) -> Void

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
                ChannelEmptyMessagesView(channel: channel)
            } else {
                let mentionIDSet = Set(unseenMentionIDs)
                let channelConfig = MessageBubbleConfiguration.channel(
                    isPublic: channel.isPublicChannel || channel.name.hasPrefix("#"),
                    contacts: viewModel.conversations
                )
                ChatTableView(
                    items: viewModel.displayItems,
                    cellContent: { displayItem in
                        messageBubble(for: displayItem, configuration: channelConfig)
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
    private func messageBubble(for item: MessageDisplayItem, configuration: MessageBubbleConfiguration) -> some View {
        if let message = viewModel.message(for: item) {
            UnifiedMessageBubble(
                message: message,
                contactName: channel.name.isEmpty ? L10n.Chats.Chats.Channel.defaultName(Int(channel.index)) : channel.name,
                deviceName: deviceName,
                configuration: configuration,
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
                    onRetry: { onRetryMessage(message) },
                    onReaction: { emoji in
                        recentEmojisStore.recordUsage(emoji)
                        Task { await viewModel.sendReaction(emoji: emoji, to: message) }
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

// MARK: - Channel Empty Messages View

private struct ChannelEmptyMessagesView: View {
    let channel: ChannelDTO

    var body: some View {
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
