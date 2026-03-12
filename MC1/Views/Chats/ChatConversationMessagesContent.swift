import SwiftUI
import MC1Services
import OSLog

private let logger = Logger(subsystem: "com.mc1", category: "ChatConversationMessagesContent")

/// Unified inner content view for both DM and Channel conversations.
/// Handles loading state, empty state, message table, bubble construction, and overlay buttons.
struct ChatConversationMessagesContent: View {
    // MARK: - Identity

    let conversationType: ChatConversationType
    @Bindable var viewModel: ChatViewModel
    let deviceName: String
    let recentEmojisStore: RecentEmojisStore

    // MARK: - Display Preferences

    let showInlineImages: Bool
    let autoPlayGIFs: Bool
    let showIncomingPath: Bool
    let showIncomingHopCount: Bool

    // MARK: - Scroll State Bindings

    @Binding var isAtBottom: Bool
    @Binding var unreadCount: Int
    @Binding var scrollToBottomRequest: Int
    @Binding var scrollToMentionRequest: Int
    @Binding var scrollToDividerRequest: Int
    @Binding var isDividerVisible: Bool

    // MARK: - Mention State (read-only)

    let unseenMentionIDs: [UUID]
    let scrollToTargetID: UUID?
    let newMessagesDividerMessageID: UUID?

    // MARK: - Sheet State Bindings

    @Binding var selectedMessageForActions: MessageDTO?
    @Binding var imageViewerData: ImageViewerData?

    // MARK: - Callbacks

    let onMentionSeen: (UUID) async -> Void
    let onScrollToMention: () -> Void
    let onRetryMessage: (MessageDTO) -> Void

    // MARK: - Private State

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @State private var hasDismissedDividerFAB = false

    private var showDividerFAB: Bool {
        newMessagesDividerMessageID != nil && !isDividerVisible && !hasDismissedDividerFAB
    }

    // MARK: - Body

    var body: some View {
        Group {
            if !viewModel.hasLoadedOnce {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.messages.isEmpty {
                emptyState
            } else {
                messagesTable
            }
        }
    }

    // MARK: - Empty State

    @ViewBuilder
    private var emptyState: some View {
        switch conversationType {
        case .dm(let contact):
            DMEmptyMessagesView(contact: contact)
        case .channel(let channel):
            ChannelEmptyMessagesView(
                channel: channel,
                displayName: conversationType.navigationTitle,
                isPublicStyle: conversationType.isPublicStyleChannel
            )
        }
    }

    // MARK: - Messages Table + Overlays

    private var messagesTable: some View {
        let mentionIDSet = Set(unseenMentionIDs)
        let contactName = conversationType.navigationTitle
        let configuration = bubbleConfiguration
        return ChatTableView(
            items: viewModel.displayItems,
            cellContent: { item in messageBubble(for: item, contactName: contactName, configuration: configuration) },
            isAtBottom: $isAtBottom,
            unreadCount: $unreadCount,
            scrollToBottomRequest: $scrollToBottomRequest,
            scrollToMentionRequest: $scrollToMentionRequest,
            isUnseenMention: { item in
                item.containsSelfMention && !item.mentionSeen && mentionIDSet.contains(item.id)
            },
            onMentionBecameVisible: { id in
                Task {
                    await onMentionSeen(id)
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

    // MARK: - Message Bubble Construction

    private var bubbleConfiguration: MessageBubbleConfiguration {
        switch conversationType {
        case .dm:
            .directMessage
        case .channel:
            .channel(
                isPublic: conversationType.isPublicStyleChannel,
                contacts: viewModel.conversations
            )
        }
    }

    private func onReaction(for message: MessageDTO) -> ((String) -> Void) {
        { emoji in
            recentEmojisStore.recordUsage(emoji)
            Task { await viewModel.sendReaction(emoji: emoji, to: message) }
        }
    }

    @ViewBuilder
    private func messageBubble(
        for item: MessageDisplayItem,
        contactName: String,
        configuration: MessageBubbleConfiguration
    ) -> some View {
        if let message = viewModel.message(for: item) {
            UnifiedMessageBubble(
                message: message,
                contactName: contactName,
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
                    onReaction: onReaction(for: message),
                    onLongPress: { selectedMessageForActions = message },
                    onImageTap: {
                        if let data = viewModel.imageData(for: message.id) {
                            imageViewerData = ImageViewerData(
                                imageData: data,
                                isGIF: viewModel.isGIFImage(for: message.id)
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

// MARK: - DM Empty Messages View

private struct DMEmptyMessagesView: View {
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

// MARK: - Channel Empty Messages View

private struct ChannelEmptyMessagesView: View {
    let channel: ChannelDTO
    let displayName: String
    let isPublicStyle: Bool

    var body: some View {
        VStack(spacing: 16) {
            ChannelAvatar(channel: channel, size: 80)

            Text(displayName)
                .font(.title2)
                .bold()

            Text(L10n.Chats.Chats.Channel.EmptyState.noMessages)
                .foregroundStyle(.secondary)

            Text(isPublicStyle
                ? L10n.Chats.Chats.Channel.EmptyState.publicDescription
                : L10n.Chats.Chats.Channel.EmptyState.privateDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Previews

#Preview("DM Conversation") {
    NavigationStack {
        ChatConversationMessagesContent(
            conversationType: .dm(ContactDTO(from: Contact(
                deviceID: UUID(),
                publicKey: Data(repeating: 0x42, count: 32),
                name: "Alice"
            ))),
            viewModel: ChatViewModel(),
            deviceName: "My Device",
            recentEmojisStore: RecentEmojisStore(),
            showInlineImages: true,
            autoPlayGIFs: true,
            showIncomingPath: false,
            showIncomingHopCount: false,
            isAtBottom: .constant(true),
            unreadCount: .constant(0),
            scrollToBottomRequest: .constant(0),
            scrollToMentionRequest: .constant(0),
            scrollToDividerRequest: .constant(0),
            isDividerVisible: .constant(false),
            unseenMentionIDs: [],
            scrollToTargetID: nil,
            newMessagesDividerMessageID: nil,
            selectedMessageForActions: .constant(nil),
            imageViewerData: .constant(nil),
            onMentionSeen: { _ in },
            onScrollToMention: {},
            onRetryMessage: { _ in }
        )
    }
    .environment(\.appState, AppState())
}

#Preview("Channel Conversation") {
    NavigationStack {
        ChatConversationMessagesContent(
            conversationType: .channel(ChannelDTO(from: Channel(
                deviceID: UUID(),
                index: 1,
                name: "General"
            ))),
            viewModel: ChatViewModel(),
            deviceName: "My Device",
            recentEmojisStore: RecentEmojisStore(),
            showInlineImages: true,
            autoPlayGIFs: true,
            showIncomingPath: false,
            showIncomingHopCount: false,
            isAtBottom: .constant(true),
            unreadCount: .constant(0),
            scrollToBottomRequest: .constant(0),
            scrollToMentionRequest: .constant(0),
            scrollToDividerRequest: .constant(0),
            isDividerVisible: .constant(false),
            unseenMentionIDs: [],
            scrollToTargetID: nil,
            newMessagesDividerMessageID: nil,
            selectedMessageForActions: .constant(nil),
            imageViewerData: .constant(nil),
            onMentionSeen: { _ in },
            onScrollToMention: {},
            onRetryMessage: { _ in }
        )
    }
    .environment(\.appState, AppState())
}
