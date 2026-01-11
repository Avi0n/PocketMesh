import SwiftUI
import PocketMeshServices
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh", category: "ChannelChatView")

/// Channel conversation view with broadcast messaging
struct ChannelChatView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let channel: ChannelDTO
    let parentViewModel: ChatViewModel?

    @State private var viewModel = ChatViewModel()
    @State private var showingChannelInfo = false
    @State private var isAtBottom = true
    @State private var unreadCount = 0
    @State private var scrollToBottomRequest = 0
    @State private var selectedMessageForRepeats: MessageDTO?
    @FocusState private var isInputFocused: Bool

    @State private var linkPreviewFetcher = LinkPreviewFetcher()

    init(channel: ChannelDTO, parentViewModel: ChatViewModel? = nil) {
        self.channel = channel
        self.parentViewModel = parentViewModel
    }

    var body: some View {
        messagesView
            .safeAreaInset(edge: .bottom, spacing: 8) {
                inputBar
            }
            .navigationTitle(channel.name.isEmpty ? "Channel \(channel.index)" : channel.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                headerView
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingChannelInfo = true
                } label: {
                    Image(systemName: "info.circle")
                }
            }
        }
        .sheet(isPresented: $showingChannelInfo) {
            ChannelInfoSheet(channel: channel) {
                // Dismiss the chat view when channel is deleted
                dismiss()
            }
        }
        .sheet(item: $selectedMessageForRepeats) { message in
            RepeatDetailsSheet(message: message)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task(id: appState.servicesVersion) {
            logger.info(".task: starting for channel \(channel.index), services=\(appState.services != nil)")
            viewModel.configure(appState: appState)
            await viewModel.loadChannelMessages(for: channel)
            logger.info(".task: completed, messages.count=\(viewModel.messages.count)")
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
                viewModel.appendMessageIfNew(message)
                // Prefetch link preview immediately
                fetchLinkPreviewIfNeeded(for: message)
                Task {
                    await viewModel.loadChannelMessages(for: channel)
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
            case .heardRepeatRecorded(let messageID, _):
                // Reload to update the heard repeats count for the message
                if viewModel.messages.contains(where: { $0.id == messageID }) {
                    Task {
                        await viewModel.loadChannelMessages(for: channel)
                    }
                }
            case .linkPreviewUpdated(let messageID):
                // Reload if this message belongs to the current channel
                if viewModel.messages.contains(where: { $0.id == messageID }) {
                    Task {
                        await viewModel.loadChannelMessages(for: channel)
                    }
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

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 0) {
            Text(channel.name.isEmpty ? "Channel \(channel.index)" : channel.name)
                .font(.headline)

            Text(channel.isPublicChannel || channel.name.hasPrefix("#") ? "Public Channel" : "Private Channel")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
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
                    items: viewModel.messages,
                    cellContent: { message in
                        messageBubble(for: message)
                    },
                    isAtBottom: $isAtBottom,
                    unreadCount: $unreadCount,
                    scrollToBottomRequest: $scrollToBottomRequest
                )
                .overlay(alignment: .bottomTrailing) {
                    ScrollToBottomFAB(
                        isVisible: !isAtBottom,
                        unreadCount: unreadCount,
                        onTap: { scrollToBottomRequest += 1 }
                    )
                    .padding(.trailing, 16)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private func messageBubble(for message: MessageDTO) -> some View {
        let index = viewModel.messages.firstIndex(where: { $0.id == message.id }) ?? 0
        return UnifiedMessageBubble(
            message: message,
            contactName: channel.name.isEmpty ? "Channel \(channel.index)" : channel.name,
            contactNodeName: channel.name.isEmpty ? "Channel \(channel.index)" : channel.name,
            deviceName: appState.connectedDevice?.nodeName ?? "Me",
            configuration: .channel(
                isPublic: channel.isPublicChannel || channel.name.hasPrefix("#"),
                contacts: viewModel.conversations
            ),
            showTimestamp: ChatViewModel.shouldShowTimestamp(at: index, in: viewModel.messages),
            showDirectionGap: ChatViewModel.isDirectionChange(at: index, in: viewModel.messages),
            onRetry: { retryMessage(message) },
            onReply: { replyText in
                setReplyText(replyText)
            },
            onDelete: {
                deleteMessage(message)
            },
            onShowRepeatDetails: { message in
                showRepeatDetails(for: message)
            },
            onManualPreviewFetch: {
                manualFetchLinkPreview(for: message)
            },
            isLoadingPreview: linkPreviewFetcher.isFetching(message.id)
        )
        .onAppear {
            fetchLinkPreviewIfNeeded(for: message)
        }
    }

    private func fetchLinkPreviewIfNeeded(for message: MessageDTO) {
        guard let dataStore = appState.services?.dataStore else { return }
        linkPreviewFetcher.fetchIfNeeded(
            for: message,
            isChannelMessage: true,
            using: dataStore,
            eventBroadcaster: appState.messageEventBroadcaster
        )
    }

    private func manualFetchLinkPreview(for message: MessageDTO) {
        guard let dataStore = appState.services?.dataStore else { return }
        linkPreviewFetcher.manualFetch(
            for: message,
            using: dataStore,
            eventBroadcaster: appState.messageEventBroadcaster
        )
    }

    private var emptyMessagesView: some View {
        VStack(spacing: 16) {
            ChannelAvatar(channel: channel, size: 80)

            Text(channel.name.isEmpty ? "Channel \(channel.index)" : channel.name)
                .font(.title2)
                .bold()

            Text("No messages yet")
                .foregroundStyle(.secondary)

            Text(channel.isPublicChannel || channel.name.hasPrefix("#") ? "This is a public broadcast channel" : "This is a private channel")
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

    // MARK: - Input Bar

    /// Calculate max channel message length based on device's advertised name
    private var maxChannelMessageLength: Int {
        let nodeNameLength = appState.connectedDevice?.nodeName.count ?? 0
        return ProtocolLimits.maxChannelMessageLength(nodeNameLength: nodeNameLength)
    }

    private var inputBar: some View {
        ChatInputBar(
            text: $viewModel.composingText,
            isFocused: $isInputFocused,
            placeholder: channel.isPublicChannel || channel.name.hasPrefix("#") ? "Public Channel" : "Private Channel",
            accentColor: channel.isPublicChannel || channel.name.hasPrefix("#") ? .green : .blue,
            maxCharacters: maxChannelMessageLength
        ) {
            // Force scroll to bottom on user send (before message is added)
            scrollToBottomRequest += 1
            Task {
                await viewModel.sendChannelMessage()
                // Prefetch link preview for newly sent message
                if let message = viewModel.messages.last, message.isOutgoing {
                    fetchLinkPreviewIfNeeded(for: message)
                }
            }
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
    .environment(AppState())
}
