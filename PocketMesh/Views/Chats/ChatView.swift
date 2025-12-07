import SwiftUI
import PocketMeshKit

/// Individual chat conversation view with iMessage-style UI
struct ChatView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let contact: ContactDTO
    let parentViewModel: ChatViewModel?

    @State private var viewModel = ChatViewModel()
    @State private var showingContactInfo = false
    @FocusState private var isInputFocused: Bool

    init(contact: ContactDTO, parentViewModel: ChatViewModel? = nil) {
        self.contact = contact
        self.parentViewModel = parentViewModel
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            messagesView

            // Input bar
            inputBar
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
                    ContactAvatar(contact: contact, size: 32)
                }
            }
        }
        .sheet(isPresented: $showingContactInfo) {
            NavigationStack {
                ContactDetailView(contact: contact)
            }
        }
        .task {
            viewModel.configure(appState: appState)
            await viewModel.loadMessages(for: contact)
        }
        .onDisappear {
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
            // Check if the new message is for this contact
            if case .directMessageReceived(let message, _) = appState.messageEventBroadcaster.latestEvent,
               message.contactID == contact.id {
                Task {
                    await viewModel.loadMessages(for: contact)
                }
            }
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

    private var messagesContent: some View {
        ForEach(viewModel.messages.enumeratedElements(), id: \.element.id) { index, message in
            MessageBubbleView(
                message: message,
                contactName: contact.displayName,
                deviceName: appState.connectedDevice?.nodeName ?? "Me",
                showTimestamp: shouldShowTimestamp(at: index),
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

    private func shouldShowTimestamp(at index: Int) -> Bool {
        // Show timestamp for first message or when there's a gap
        guard index > 0 else { return true }

        let currentMessage = viewModel.messages[index]
        let previousMessage = viewModel.messages[index - 1]

        // Show if more than 5 minutes apart
        let gap = abs(Int(currentMessage.timestamp) - Int(previousMessage.timestamp))
        return gap > 300
    }

    private func retryMessage(_ message: MessageDTO) {
        Task {
            await viewModel.retryMessage(message)
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 12) {
            // Text field
            TextField("Message", text: $viewModel.composingText, axis: .vertical)
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
                    await viewModel.sendMessage()
                }
            } label: {
                Image(systemName: viewModel.isSending ? "hourglass" : "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? .blue : .secondary)
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

// MARK: - Array Enumerated Extension

extension Array {
    func enumeratedElements() -> [(offset: Int, element: Element)] {
        Array<(offset: Int, element: Element)>(enumerated())
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
    .environment(AppState())
}
