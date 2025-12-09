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
    @State private var scrollPosition = ScrollPosition(edge: .bottom)
    @FocusState private var isInputFocused: Bool

    init(contact: ContactDTO, parentViewModel: ChatViewModel? = nil) {
        self.contact = contact
        self.parentViewModel = parentViewModel
    }

    var body: some View {
        messagesView
            .safeAreaInset(edge: .bottom, spacing: 0) {
                inputBar
            }
            .keyboardAwareScrollEdgeEffect(isFocused: isInputFocused)
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
        .toolbarVisibility(.hidden, for: .tabBar)
        .task {
            viewModel.configure(appState: appState)
            await viewModel.loadMessages(for: contact)
            viewModel.loadDraftIfExists()
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
            switch appState.messageEventBroadcaster.latestEvent {
            case .directMessageReceived(let message, _) where message.contactID == contact.id:
                Task {
                    await viewModel.loadMessages(for: contact)
                }
            case .messageStatusUpdated:
                // Reload to pick up status changes (Sent -> Delivered, etc.)
                Task {
                    await viewModel.loadMessages(for: contact)
                }
            default:
                break
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
        .defaultScrollAnchor(.bottom)
        .scrollPosition($scrollPosition)
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: viewModel.messages.count) { _, _ in
            // Scroll to bottom when new messages arrive
            scrollPosition.scrollTo(edge: .bottom)
        }
        .onChange(of: isInputFocused) { _, isFocused in
            // Scroll to bottom when keyboard appears
            if isFocused {
                scrollPosition.scrollTo(edge: .bottom)
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
            UnifiedMessageBubble(
                message: message,
                contactName: contact.displayName,
                deviceName: appState.connectedDevice?.nodeName ?? "Me",
                configuration: .directMessage,
                showTimestamp: ChatViewModel.shouldShowTimestamp(at: index, in: viewModel.messages),
                onRetry: message.hasFailed ? { retryMessage(message) } : nil,
                onReply: { replyText in
                    setReplyText(replyText)
                },
                onDelete: {
                    deleteMessage(message)
                }
            )
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
            await viewModel.retryMessage(message)
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        ChatInputBar(
            text: $viewModel.composingText,
            isFocused: $isInputFocused,
            placeholder: "Message",
            accentColor: .blue,
            isSending: viewModel.isSending
        ) {
            Task {
                await viewModel.sendMessage()
            }
        }
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
