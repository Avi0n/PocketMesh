import SwiftUI
import PocketMeshKit

/// Channel conversation view with broadcast messaging
struct ChannelChatView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let channel: ChannelDTO
    let parentViewModel: ChatViewModel?

    @State private var viewModel = ChatViewModel()
    @State private var showingChannelInfo = false
    @FocusState private var isInputFocused: Bool

    init(channel: ChannelDTO, parentViewModel: ChatViewModel? = nil) {
        self.channel = channel
        self.parentViewModel = parentViewModel
    }

    var body: some View {
        messagesView
            .safeAreaInset(edge: .bottom, spacing: 0) {
                inputBar
            }
            .keyboardAwareScrollEdgeEffect(isFocused: isInputFocused)
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
        .toolbarVisibility(.hidden, for: .tabBar)
        .task {
            viewModel.configure(appState: appState)
            await viewModel.loadChannelMessages(for: channel)
        }
        .onDisappear {
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
                Task {
                    await viewModel.loadChannelMessages(for: channel)
                }
            case .messageStatusUpdated:
                // Reload to pick up status changes (Sent -> Delivered, etc.)
                Task {
                    await viewModel.loadChannelMessages(for: channel)
                }
            default:
                break
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 0) {
            Text(channel.name.isEmpty ? "Channel \(channel.index)" : channel.name)
                .font(.headline)

            Text(channel.isPublicChannel ? "Public Channel" : "Private Channel")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Messages View

    private var messagesView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if viewModel.isLoading && viewModel.messages.isEmpty {
                        ProgressView()
                            .padding()
                    } else if viewModel.messages.isEmpty {
                        emptyMessagesView
                    } else {
                        messagesContent
                    }
                }
                .padding(.vertical)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.count) { _, _ in
                // Scroll to bottom when new messages arrive
                if let lastMessage = viewModel.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var emptyMessagesView: some View {
        VStack(spacing: 16) {
            ChannelAvatar(channel: channel, size: 80)

            Text(channel.name.isEmpty ? "Channel \(channel.index)" : channel.name)
                .font(.title2)
                .bold()

            Text("No messages yet")
                .foregroundStyle(.secondary)

            Text(channel.isPublicChannel ? "This is a public broadcast channel" : "This is a private channel")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var messagesContent: some View {
        ForEach(viewModel.messages.enumeratedElements(), id: \.element.id) { index, message in
            UnifiedMessageBubble(
                message: message,
                contactName: channel.name.isEmpty ? "Channel \(channel.index)" : channel.name,
                deviceName: appState.connectedDevice?.nodeName ?? "Me",
                configuration: .channel(
                    isPublic: channel.isPublicChannel || channel.name.hasPrefix("#"),
                    contacts: viewModel.conversations
                ),
                showTimestamp: ChatViewModel.shouldShowTimestamp(at: index, in: viewModel.messages),
                onRetry: message.hasFailed ? { retryMessage(message) } : nil,
                onReply: { replyText in
                    setReplyText(replyText)
                },
                onDelete: {
                    deleteMessage(message)
                }
            )
            .id(message.id)
        }
    }

    private func setReplyText(_ text: String) {
        viewModel.composingText = text + "\n"
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

    // MARK: - Input Bar

    private var inputBar: some View {
        ChatInputBar(
            text: $viewModel.composingText,
            isFocused: $isInputFocused,
            placeholder: "Broadcast message",
            accentColor: channel.isPublicChannel || channel.name.hasPrefix("#") ? .green : .blue,
            isSending: viewModel.isSending
        ) {
            Task {
                await viewModel.sendChannelMessage()
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
