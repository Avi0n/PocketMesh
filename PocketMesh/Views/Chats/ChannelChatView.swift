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
        VStack(spacing: 0) {
            // Messages
            messagesView

            // Input bar
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
            // Check if the new message is for this channel (verify both deviceID and channelIndex)
            if case .channelMessageReceived(let message, let channelIndex) = appState.messageEventBroadcaster.latestEvent,
               channelIndex == channel.index,
               message.deviceID == channel.deviceID {
                Task {
                    await viewModel.loadChannelMessages(for: channel)
                }
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
        ForEach(viewModel.messages.indices, id: \.self) { index in
            let message = viewModel.messages[index]
            ChannelMessageBubbleView(
                message: message,
                contacts: viewModel.conversations, // For sender name resolution
                deviceName: appState.connectedDevice?.nodeName ?? "Me",
                showTimestamp: shouldShowTimestamp(at: index)
            )
            .id(message.id)
        }
    }

    private func shouldShowTimestamp(at index: Int) -> Bool {
        // Show timestamp for first message or when there's a gap
        guard index > 0 else { return true }

        let currentMessage = viewModel.messages[index]
        let previousMessage = viewModel.messages[index - 1]

        // Show if more than 5 minutes apart
        let gap = abs(Int(currentMessage.timestamp) - Int(previousMessage.timestamp))
        return gap > 300
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 12) {
            // Text field
            TextField("Broadcast message", text: $viewModel.composingText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6))
                .clipShape(.rect(cornerRadius: 20))
                .lineLimit(1...5)
                .focused($isInputFocused)

            // Send button
            Button {
                Task {
                    await viewModel.sendChannelMessage()
                }
            } label: {
                Image(systemName: viewModel.isSending ? "hourglass" : "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? .green : .secondary)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var canSend: Bool {
        !viewModel.composingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !viewModel.isSending
    }
}

// MARK: - Channel Message Bubble

struct ChannelMessageBubbleView: View {
    let message: MessageDTO
    let contacts: [ContactDTO] // For sender name resolution
    let deviceName: String
    let showTimestamp: Bool

    var body: some View {
        VStack(spacing: 4) {
            if showTimestamp {
                Text(message.date, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }

            HStack {
                if message.isOutgoing {
                    Spacer(minLength: 60)
                }

                VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 2) {
                    if !message.isOutgoing {
                        // Show sender name (resolved from contacts) or key prefix
                        Text(senderLabel)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(message.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(message.isOutgoing ? Color.green : Color(.systemGray5))
                        .foregroundStyle(message.isOutgoing ? .white : .primary)
                        .clipShape(.rect(cornerRadius: 16))
                }

                if !message.isOutgoing {
                    Spacer(minLength: 60)
                }
            }
            .padding(.horizontal)
        }
    }

    /// Resolve sender name from known contacts, fallback to hex key prefix
    private var senderLabel: String {
        guard let prefix = message.senderKeyPrefix else {
            return "Unknown"
        }

        // Try to find matching contact by public key prefix
        if let contact = contacts.first(where: { contact in
            contact.publicKey.count >= prefix.count &&
            Array(contact.publicKey.prefix(prefix.count)) == Array(prefix)
        }) {
            return contact.displayName
        }

        // Fallback to hex representation of key prefix
        if prefix.count >= 2 {
            return prefix.prefix(2).map { String(format: "%02X", $0) }.joined()
        }
        return "Unknown"
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
