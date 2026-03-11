import SwiftUI
import UIKit  // UIPasteboard for .copy action
import MC1Services
import OSLog

private let logger = Logger(subsystem: "com.mc1", category: "ChatConversationView")

/// Unified chat conversation view supporting both DMs and Channels.
/// Replaces the separate `ChatView` and `ChannelChatView`.
struct ChatConversationView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.linkPreviewCache) private var linkPreviewCache

    @State private var conversationType: ChatConversationType
    let parentViewModel: ChatViewModel?

    @State private var chatViewModel = ChatViewModel()

    // MARK: - Scroll State

    @State private var isAtBottom = true
    @State private var unreadCount = 0
    @State private var scrollToBottomRequest = 0
    @State private var scrollToMentionRequest = 0
    @State private var unseenMentionIDs: [UUID] = []
    @State private var scrollToTargetID: UUID?
    @State private var mentionScrollTask: Task<Void, Never>?
    @State private var scrollToDividerRequest = 0
    @State private var isDividerVisible = false

    // MARK: - Sheet State

    @State private var showingInfo = false
    @State private var selectedMessageForActions: MessageDTO?
    @State private var blockSenderContext: BlockSenderContext?
    @State private var imageViewerData: ImageViewerData?

    // MARK: - Other State

    @State private var recentEmojisStore = RecentEmojisStore()
    @State private var mentionSenderOrder: [String: UInt32]?
    @State private var eventCursor: Int?
    @FocusState private var isInputFocused: Bool

    // MARK: - AppStorage

    @AppStorage("showInlineImages") private var showInlineImages = true
    @AppStorage("autoPlayGIFs") private var autoPlayGIFs = true
    @AppStorage("showIncomingPath") private var showIncomingPath = false
    @AppStorage("showIncomingHopCount") private var showIncomingHopCount = false

    // MARK: - Init

    init(conversationType: ChatConversationType, parentViewModel: ChatViewModel? = nil) {
        self._conversationType = State(initialValue: conversationType)
        self.parentViewModel = parentViewModel
    }

    // MARK: - Body

    var body: some View {
        ChatConversationMessagesContent(
            conversationType: conversationType,
            viewModel: chatViewModel,
            deviceName: appState.connectedDevice?.nodeName ?? "Me",
            recentEmojisStore: recentEmojisStore,
            showInlineImages: showInlineImages,
            autoPlayGIFs: autoPlayGIFs,
            showIncomingPath: showIncomingPath,
            showIncomingHopCount: showIncomingHopCount,
            isAtBottom: $isAtBottom,
            unreadCount: $unreadCount,
            scrollToBottomRequest: $scrollToBottomRequest,
            scrollToMentionRequest: $scrollToMentionRequest,
            scrollToDividerRequest: $scrollToDividerRequest,
            isDividerVisible: $isDividerVisible,
            unseenMentionIDs: unseenMentionIDs,
            scrollToTargetID: scrollToTargetID,
            newMessagesDividerMessageID: chatViewModel.newMessagesDividerMessageID,
            selectedMessageForActions: $selectedMessageForActions,
            imageViewerData: $imageViewerData,
            onMentionSeen: { await markMentionSeen(messageID: $0) },
            onScrollToMention: { scrollToNextMention() },
            onRetryMessage: { retryMessage($0) }
        )
        .safeAreaInset(edge: .bottom, spacing: 8) {
            inputBar
        }
        .overlay(alignment: .bottom) {
            mentionSuggestionsOverlay
        }
        .navigationHeader(
            title: conversationType.navigationTitle,
            subtitle: conversationType.navigationSubtitle
        )
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Info", systemImage: "info.circle") {
                    showingInfo = true
                }
            }
        }
        // Info sheet — type-specific
        .sheet(isPresented: $showingInfo, onDismiss: {
            if case .dm = conversationType {
                Task { await refreshContact() }
            }
        }, content: {
            infoSheet
        })
        // Message actions sheet — shared
        .sheet(item: $selectedMessageForActions) { message in
            messageActionsSheet(for: message)
        }
        // Block sender sheet — channel only
        .sheet(item: $blockSenderContext) { context in
            if case .channel(let channel) = conversationType {
                BlockSenderSheet(
                    senderName: context.senderName,
                    deviceID: channel.deviceID
                ) { blockedContactIDs in
                    Task {
                        await performBlock(
                            channel: channel,
                            senderName: context.senderName,
                            contactIDs: blockedContactIDs
                        )
                    }
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
            await performInitialLoad()
        }
        .onDisappear {
            performCleanup()
        }
        .onChange(of: isMentionActive) { _, isActive in
            if isActive {
                mentionSenderOrder = chatViewModel.channelSenderOrder
            } else {
                mentionSenderOrder = nil
            }
        }
        .onChange(of: appState.messageEventBroadcaster.newMessageCount) { _, _ in
            drainEvents()
        }
        .alert(L10n.Chats.Chats.Alert.UnableToSend.title, isPresented: $chatViewModel.showRetryError) {
            Button(L10n.Chats.Chats.Common.ok, role: .cancel) { }
        } message: {
            Text(L10n.Chats.Chats.Alert.UnableToSend.message)
        }
    }

    // MARK: - Initial Load (.task)

    private func performInitialLoad() async {
        // Capture pending scroll target before loading
        let pendingTarget = appState.navigation.pendingScrollToMessageID
        if pendingTarget != nil {
            appState.navigation.clearPendingScrollToMessage()
        }

        chatViewModel.configure(appState: appState, linkPreviewCache: linkPreviewCache)

        switch conversationType {
        case .dm(let contact):
            await chatViewModel.loadMessages(for: contact)
            await chatViewModel.loadConversations(deviceID: contact.deviceID)
            await chatViewModel.loadAllContacts(deviceID: contact.deviceID)
            chatViewModel.loadDraftIfExists()

        case .channel(let channel):
            // Load contacts first so contactNameSet is populated before buildChannelSenders runs
            await chatViewModel.loadAllContacts(deviceID: channel.deviceID)
            await chatViewModel.loadChannelMessages(for: channel)
            await chatViewModel.loadConversations(deviceID: channel.deviceID)
        }

        await loadUnseenMentions()

        // Trigger scroll to target message if pending (notification deeplink)
        if let targetID = pendingTarget {
            scrollToTargetID = targetID
            scrollToMentionRequest += 1
        }
    }

    // MARK: - Cleanup (.onDisappear)

    private func performCleanup() {
        mentionScrollTask?.cancel()
        mentionScrollTask = nil

        // Clear notification suppression
        switch conversationType {
        case .dm:
            appState.services?.notificationService.activeContactID = nil
        case .channel:
            appState.services?.notificationService.activeChannelIndex = nil
            appState.services?.notificationService.activeChannelDeviceID = nil
        }

        // Refresh parent conversation list when leaving
        if let parent = parentViewModel {
            Task {
                guard let deviceID = appState.connectedDevice?.id else { return }
                await parent.loadConversations(deviceID: deviceID)
                if case .channel = conversationType {
                    await parent.loadChannels(deviceID: deviceID)
                }
                await parent.loadLastMessagePreviews()
            }
        }
    }

    // MARK: - Event Draining

    private func drainEvents() {
        guard let cursor = eventCursor else { return }
        let (events, newCursor, droppedEvents) = appState.messageEventBroadcaster.events(after: cursor)
        eventCursor = newCursor
        var needsReload = droppedEvents
        var needsContactRefresh = false

        switch conversationType {
        case .dm(let contact):
            (needsReload, needsContactRefresh) = drainDMEvents(
                events, contact: contact, needsReload: needsReload
            )
        case .channel(let channel):
            needsReload = drainChannelEvents(events, channel: channel, needsReload: needsReload)
        }

        if needsReload {
            Task {
                switch conversationType {
                case .dm(let contact):
                    await chatViewModel.loadMessages(for: contact)
                case .channel(let channel):
                    await chatViewModel.loadChannelMessages(for: channel)
                }
            }
        }
        if case .dm = conversationType, needsContactRefresh || droppedEvents {
            Task { await refreshContact() }
        }
        if droppedEvents {
            Task { await loadUnseenMentions() }
        }
    }

    private func drainDMEvents(
        _ events: [MessageEvent], contact: ContactDTO, needsReload: Bool
    ) -> (needsReload: Bool, needsContactRefresh: Bool) {
        var needsReload = needsReload
        var needsContactRefresh = false
        for event in events {
            switch event {
            case .directMessageReceived(let message, _) where message.contactID == contact.id:
                chatViewModel.appendMessageIfNew(message)
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
                if chatViewModel.messages.contains(where: { $0.id == messageID }) {
                    needsReload = true
                }
            case .routingChanged(let contactID, _) where contactID == contact.id:
                needsContactRefresh = true
            case .reactionReceived(let messageID, let summary):
                if chatViewModel.messages.contains(where: { $0.id == messageID }) {
                    chatViewModel.updateReactionSummary(for: messageID, summary: summary)
                }
            default:
                break
            }
        }
        return (needsReload, needsContactRefresh)
    }

    private func drainChannelEvents(
        _ events: [MessageEvent], channel: ChannelDTO, needsReload: Bool
    ) -> Bool {
        var needsReload = needsReload
        for event in events {
            switch event {
            case .channelMessageReceived(let message, let channelIndex)
                where channelIndex == channel.index && message.deviceID == channel.deviceID:
                chatViewModel.appendMessageIfNew(message)
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
                if chatViewModel.messages.contains(where: { $0.id == messageID }) {
                    needsReload = true
                }
            case .heardRepeatRecorded(let messageID, _):
                if chatViewModel.messages.contains(where: { $0.id == messageID }) {
                    needsReload = true
                }
            case .reactionReceived(let messageID, let summary):
                if chatViewModel.messages.contains(where: { $0.id == messageID }) {
                    chatViewModel.updateReactionSummary(for: messageID, summary: summary)
                }
            default:
                break
            }
        }
        return needsReload
    }

    // MARK: - Contact Refresh (DM only)

    private func refreshContact() async {
        guard case .dm(let contact) = conversationType else { return }
        if let updated = try? await appState.services?.dataStore.fetchContact(id: contact.id) {
            conversationType.replacing(contact: updated)
        }
    }

    // MARK: - Mention Tracking

    private func loadUnseenMentions() async {
        switch conversationType {
        case .dm(let contact):
            guard let dataStore = appState.services?.dataStore else { return }
            do {
                unseenMentionIDs = try await dataStore.fetchUnseenMentionIDs(contactID: contact.id)
            } catch {
                logger.error("Failed to load unseen mentions: \(error)")
            }

        case .channel(let channel):
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
    }

    private func markMentionSeen(messageID: UUID) async {
        guard unseenMentionIDs.contains(messageID) else { return }
        guard await persistMentionSeen(messageID: messageID) else { return }
        unseenMentionIDs.removeAll { $0 == messageID }
    }

    private func markNewArrivalMentionSeen(messageID: UUID) async {
        _ = await persistMentionSeen(messageID: messageID)
    }

    private func persistMentionSeen(messageID: UUID) async -> Bool {
        guard let dataStore = appState.services?.dataStore else { return false }
        do {
            try await dataStore.markMentionSeen(messageID: messageID)
            switch conversationType {
            case .dm(let contact):
                try await dataStore.decrementUnreadMentionCount(contactID: contact.id)
                if let parent = parentViewModel, let deviceID = appState.connectedDevice?.id {
                    await parent.loadConversations(deviceID: deviceID)
                }
            case .channel(let channel):
                try await dataStore.decrementChannelUnreadMentionCount(channelID: channel.id)
                if let parent = parentViewModel, let deviceID = appState.connectedDevice?.id {
                    await parent.loadChannels(deviceID: deviceID)
                }
            }
            return true
        } catch {
            logger.error("Failed to mark mention seen: \(error)")
            return false
        }
    }

    // MARK: - Mention Navigation

    private func scrollToNextMention() {
        guard let targetID = unseenMentionIDs.first else { return }

        if chatViewModel.displayItems.contains(where: { $0.id == targetID }) {
            scrollToTargetID = targetID
            scrollToMentionRequest += 1
            return
        }

        mentionScrollTask?.cancel()
        mentionScrollTask = Task {
            do {
                let deadline = ContinuousClock.now + .seconds(10)
                while !chatViewModel.displayItems.contains(where: { $0.id == targetID }) {
                    guard chatViewModel.hasMoreMessages else {
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
                    if chatViewModel.isLoadingOlder {
                        try await Task.sleep(for: .milliseconds(50))
                        continue
                    }
                    await chatViewModel.loadOlderMessages()
                    try Task.checkCancellation()
                }
                if chatViewModel.displayItems.contains(where: { $0.id == targetID }) {
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

    // MARK: - Mention Suggestions

    private var isMentionActive: Bool {
        MentionUtilities.detectActiveMention(in: chatViewModel.composingText) != nil
    }

    private var mentionSuggestions: [ContactDTO] {
        guard let query = MentionUtilities.detectActiveMention(in: chatViewModel.composingText) else {
            return []
        }
        switch conversationType {
        case .dm:
            return MentionUtilities.filterContacts(chatViewModel.allContacts, query: query)
        case .channel:
            let combined = chatViewModel.allContacts + chatViewModel.channelSenders
            let order = mentionSenderOrder ?? chatViewModel.channelSenderOrder
            return MentionUtilities.filterContacts(combined, query: query, senderOrder: order)
        }
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
        guard let query = MentionUtilities.detectActiveMention(in: chatViewModel.composingText) else { return }

        let searchPattern = "@" + query
        if let range = chatViewModel.composingText.range(of: searchPattern, options: .backwards) {
            let mention = MentionUtilities.createMention(for: contact.name)
            chatViewModel.composingText.replaceSubrange(range, with: mention + " ")
        }
    }

    // MARK: - Input Bar

    @ViewBuilder
    private var inputBar: some View {
        switch conversationType {
        case .dm:
            ChatInputBar(
                text: $chatViewModel.composingText,
                isFocused: $isInputFocused,
                placeholder: L10n.Chats.Chats.Input.Placeholder.directMessage,
                maxBytes: ProtocolLimits.maxDirectMessageLength,
                isEncrypted: true
            ) { text in
                scrollToBottomRequest += 1
                Task { await chatViewModel.sendMessage(text: text) }
            }

        case .channel(let channel):
            let maxBytes = ProtocolLimits.maxChannelMessageLength(
                nodeNameByteCount: appState.connectedDevice?.nodeName.utf8.count ?? 0
            )
            ChatInputBar(
                text: $chatViewModel.composingText,
                isFocused: $isInputFocused,
                placeholder: conversationType.isPublicStyleChannel
                    ? L10n.Chats.Chats.Channel.typePublic
                    : L10n.Chats.Chats.Channel.typePrivate,
                maxBytes: maxBytes,
                isEncrypted: channel.isEncryptedChannel
            ) { text in
                scrollToBottomRequest += 1
                Task { await chatViewModel.sendChannelMessage(text: text) }
            }
        }
    }

    // MARK: - Info Sheet

    @ViewBuilder
    private var infoSheet: some View {
        switch conversationType {
        case .dm(let contact):
            NavigationStack {
                ContactDetailView(contact: contact, showFromDirectChat: true)
            }

        case .channel(let channel):
            ChannelInfoSheet(
                channel: channel,
                onClearMessages: {
                    Task {
                        await chatViewModel.loadChannelMessages(for: channel)

                        if let parent = parentViewModel {
                            await parent.loadChannels(deviceID: channel.deviceID)
                            await parent.loadLastMessagePreviews()
                        }
                    }
                },
                onDelete: {
                    dismiss()
                }
            )
            .environment(\.chatViewModel, chatViewModel)
        }
    }

    // MARK: - Message Actions Sheet

    private func messageActionsSheet(for message: MessageDTO) -> some View {
        let senderName: String = {
            if message.isOutgoing {
                return appState.connectedDevice?.nodeName ?? "Me"
            }
            switch conversationType {
            case .dm(let contact):
                return contact.displayName
            case .channel:
                return message.senderNodeName ?? L10n.Chats.Chats.Message.Sender.unknown
            }
        }()

        return MessageActionsSheet(
            message: message,
            senderName: senderName,
            recentEmojis: recentEmojisStore.recentEmojis,
            onAction: { action in
                handleMessageAction(action, for: message)
            }
        )
        .environment(\.horizontalSizeClass, horizontalSizeClass)
    }

    // MARK: - Message Action Handling

    private func handleMessageAction(_ action: MessageAction, for message: MessageDTO) {
        switch action {
        case .react(let emoji):
            recentEmojisStore.recordUsage(emoji)
            Task { await chatViewModel.sendReaction(emoji: emoji, to: message) }
        case .reply:
            let replyText = buildReplyText(for: message)
            setReplyText(replyText)
        case .copy:
            UIPasteboard.general.string = message.text
        case .sendAgain:
            sendAgain(message)
        case .blockSender:
            switch conversationType {
            case .dm:
                break  // DMs don't support blocking
            case .channel:
                guard let name = message.senderNodeName else { return }
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    blockSenderContext = BlockSenderContext(senderName: name)
                }
            }
        case .delete:
            deleteMessage(message)
        }
    }

    private func buildReplyText(for message: MessageDTO) -> String {
        let mentionName: String
        switch conversationType {
        case .dm(let contact):
            mentionName = contact.name
        case .channel:
            mentionName = message.senderNodeName ?? L10n.Chats.Chats.Message.Sender.unknown
        }
        return MentionUtilities.buildReplyText(mentionName: mentionName, messageText: message.text)
    }

    private func setReplyText(_ text: String) {
        chatViewModel.composingText = text
        isInputFocused = true
    }

    private func deleteMessage(_ message: MessageDTO) {
        Task {
            await chatViewModel.deleteMessage(message)
        }
    }

    private func sendAgain(_ message: MessageDTO) {
        Task {
            await chatViewModel.sendAgain(message)
        }
    }

    private func retryMessage(_ message: MessageDTO) {
        Task {
            switch conversationType {
            case .dm:
                await chatViewModel.retryMessage(message)
            case .channel:
                await chatViewModel.retryChannelMessage(message)
            }
        }
    }

    // MARK: - Blocking (Channel only)

    private func performBlock(channel: ChannelDTO, senderName: String, contactIDs: Set<UUID>) async {
        guard let services = appState.services else { return }

        let dto = BlockedChannelSenderDTO(name: senderName, deviceID: channel.deviceID)
        do {
            try await services.dataStore.saveBlockedChannelSender(dto)
        } catch {
            logger.error("Failed to save blocked channel sender: \(error)")
            return
        }

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

        await services.syncCoordinator.refreshBlockedContactsCache(
            deviceID: channel.deviceID,
            dataStore: services.dataStore
        )

        if !contactIDs.isEmpty {
            await services.syncCoordinator.notifyContactsChanged()
        }

        await chatViewModel.loadChannelMessages(for: channel)
        await services.syncCoordinator.notifyConversationsChanged()
    }
}

// MARK: - Previews

#Preview("DM") {
    NavigationStack {
        ChatConversationView(
            conversationType: .dm(ContactDTO(from: Contact(
                deviceID: UUID(),
                publicKey: Data(repeating: 0x42, count: 32),
                name: "Alice"
            )))
        )
    }
    .environment(\.appState, AppState())
}

#Preview("Channel") {
    NavigationStack {
        ChatConversationView(
            conversationType: .channel(ChannelDTO(from: Channel(
                deviceID: UUID(),
                index: 1,
                name: "General"
            )))
        )
    }
    .environment(\.appState, AppState())
}
