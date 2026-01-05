import SwiftUI
import PocketMeshServices

/// Full room chat interface
struct RoomConversationView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var session: RemoteNodeSessionDTO
    @State private var viewModel = RoomConversationViewModel()
    @State private var showingRoomInfo = false
    @State private var isAtBottom = true
    @State private var unreadCount = 0
    @State private var scrollToBottomRequest = 0
    @FocusState private var isInputFocused: Bool

    init(session: RemoteNodeSessionDTO) {
        self._session = State(initialValue: session)
    }

    var body: some View {
        messagesView
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if session.canPost {
                    inputBar
                } else {
                    readOnlyBanner
                }
            }
            .navigationTitle(session.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    headerView
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingRoomInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                }
            }
            .sheet(isPresented: $showingRoomInfo) {
                RoomInfoSheet(session: session)
            }
            .task {
                viewModel.configure(appState: appState)
                await viewModel.loadMessages(for: session)
            }
            .onChange(of: appState.messageEventBroadcaster.newMessageCount) { _, _ in
                // Reload messages when a new room message arrives for this session
                if case .roomMessageReceived(let message, let sessionID) = appState.messageEventBroadcaster.latestEvent,
                   sessionID == session.id {
                    // Optimistic insert: add message immediately so ChatTableView sees new count
                    viewModel.appendMessageIfNew(message)
                    Task {
                        await viewModel.loadMessages(for: session)
                    }
                }
            }
            .refreshable {
                await viewModel.refreshMessages()
            }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: 0) {
            Text(session.name)
                .font(.headline)

            Text(connectionStatus)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var connectionStatus: String {
        if session.isConnected {
            return session.permissionLevel.displayName
        }
        return "Disconnected"
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

    private func messageBubble(for message: RoomMessageDTO) -> some View {
        let index = viewModel.messages.firstIndex(where: { $0.id == message.id }) ?? 0
        return RoomMessageBubble(
            message: message,
            showTimestamp: RoomConversationViewModel.shouldShowTimestamp(at: index, in: viewModel.messages)
        )
    }

    private var emptyMessagesView: some View {
        VStack(spacing: 16) {
            NodeAvatar(publicKey: session.publicKey, role: .roomServer, size: 80)

            Text(session.name)
                .font(.title2)
                .bold()

            Text("No public messages yet")
                .foregroundStyle(.secondary)

            if session.canPost {
                Text("Be the first to post")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        ChatInputBar(
            text: $viewModel.composingText,
            isFocused: $isInputFocused,
            placeholder: "Public Message",
            accentColor: .orange,
            maxCharacters: ProtocolLimits.maxDirectMessageLength
        ) {
            // Force scroll to bottom on user send (before message is added)
            scrollToBottomRequest += 1
            Task {
                await viewModel.sendMessage()
            }
        }
    }

    private var readOnlyBanner: some View {
        HStack {
            Image(systemName: "eye")
            Text("View only - join as member to post")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding()
        .background(.bar)
    }
}

// MARK: - Room Info Sheet

private struct RoomInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    let session: RemoteNodeSessionDTO

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Spacer()
                        NodeAvatar(publicKey: session.publicKey, role: .roomServer, size: 80)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section("Details") {
                    LabeledContent("Name", value: session.name)
                    LabeledContent("Permission", value: session.permissionLevel.displayName)
                    if session.isConnected {
                        LabeledContent("Status", value: "Connected")
                    }
                }

                if let lastConnected = session.lastConnectedDate {
                    Section("Activity") {
                        LabeledContent("Last Connected") {
                            Text(lastConnected, format: .relative(presentation: .named))
                        }
                    }
                }

                Section("Identification") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Public Key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(session.publicKeyHex)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Room Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    NavigationStack {
        RoomConversationView(
            session: RemoteNodeSessionDTO(
                deviceID: UUID(),
                publicKey: Data(repeating: 0x42, count: 32),
                name: "Test Room",
                role: .roomServer,
                isConnected: true,
                permissionLevel: .readWrite
            )
        )
    }
    .environment(AppState())
}
