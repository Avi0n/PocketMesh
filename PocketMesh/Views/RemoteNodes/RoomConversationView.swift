import SwiftUI
import PocketMeshServices

/// Full room chat interface
struct RoomConversationView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var session: RemoteNodeSessionDTO
    @State private var viewModel = RoomConversationViewModel()
    @State private var showingRoomInfo = false
    @State private var scrollPosition = ScrollPosition(edge: .bottom)
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
                if case .roomMessageReceived(_, let sessionID) = appState.messageEventBroadcaster.latestEvent,
                   sessionID == session.id {
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
        .defaultScrollAnchor(.bottom, for: .initialOffset)
        .defaultScrollAnchor(.bottom, for: .alignment)
        .scrollPosition($scrollPosition)
        .scrollDismissesKeyboard(.interactively)
        .onChange(of: viewModel.messages.count) { _, _ in
            scrollPosition.scrollTo(edge: .bottom)
        }
        .onChange(of: isInputFocused) { _, isFocused in
            if isFocused {
                scrollPosition.scrollTo(edge: .bottom)
            }
        }
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

    private var messagesContent: some View {
        ForEach(viewModel.messages.enumeratedElements(), id: \.element.id) { index, message in
            RoomMessageBubble(
                message: message,
                showTimestamp: RoomConversationViewModel.shouldShowTimestamp(at: index, in: viewModel.messages)
            )
        }
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
