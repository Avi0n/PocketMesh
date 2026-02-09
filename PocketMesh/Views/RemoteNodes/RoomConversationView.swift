import SwiftUI
import PocketMeshServices

/// Full room chat interface
struct RoomConversationView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var session: RemoteNodeSessionDTO
    @State private var viewModel = RoomConversationViewModel()
    @State private var chatViewModel = ChatViewModel()
    @State private var showingRoomInfo = false
    @State private var roomToAuthenticate: RemoteNodeSessionDTO?
    @State private var isAtBottom = true
    @State private var unreadCount = 0
    @State private var scrollToBottomRequest = 0
    @State private var keyboardObserver = KeyboardObserver()
    @FocusState private var isInputFocused: Bool

    init(session: RemoteNodeSessionDTO) {
        self._session = State(initialValue: session)
    }

    var body: some View {
        messagesView
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !session.isConnected {
                    disconnectedBanner
                } else if session.canPost {
                    inputBar
                        .floatingKeyboardAware()
                } else {
                    readOnlyBanner
                }
            }
            .animation(.default, value: session.isConnected)
            .ignoreKeyboardOnIPad()
            .environment(keyboardObserver)
            .navigationHeader(title: session.name, subtitle: connectionStatus)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.RemoteNodes.RemoteNodes.Room.infoTitle, systemImage: "info.circle") {
                        showingRoomInfo = true
                    }
                }
            }
            .sheet(isPresented: $showingRoomInfo) {
                RoomInfoSheet(session: session)
                    .environment(\.chatViewModel, chatViewModel)
            }
            .sheet(item: $roomToAuthenticate) { sessionToAuth in
                RoomAuthenticationSheet(session: sessionToAuth) { authenticatedSession in
                    roomToAuthenticate = nil
                    session = authenticatedSession
                }
                .presentationSizing(.page)
            }
            .task {
                viewModel.configure(appState: appState)
                chatViewModel.configure(appState: appState)
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

                // Handle status updates and failures
                if let event = appState.messageEventBroadcaster.latestEvent {
                    Task {
                        await viewModel.handleEvent(event)
                    }
                }
            }
            .onChange(of: appState.messageEventBroadcaster.sessionStateChanged) { _, _ in
                Task {
                    await viewModel.refreshSession()
                    if let updated = viewModel.session {
                        session = updated
                    }
                }
            }
            .refreshable {
                await viewModel.refreshMessages()
            }
            .task(id: session.isConnected) {
                guard session.isConnected else { return }
                await appState.services?.remoteNodeService.startSessionKeepAlive(
                    sessionID: session.id, publicKey: session.publicKey
                )
            }
            .onChange(of: session.isConnected) { _, isConnected in
                if isConnected {
                    AccessibilityNotification.Announcement(
                        L10n.RemoteNodes.RemoteNodes.Room.reconnected
                    ).post()
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active, session.isConnected {
                    Task {
                        await appState.services?.remoteNodeService.startSessionKeepAlive(
                            sessionID: session.id, publicKey: session.publicKey
                        )
                    }
                }
            }
            .onDisappear {
                Task {
                    await appState.services?.remoteNodeService.stopSessionKeepAlive(
                        sessionID: session.id
                    )
                }
            }
    }

    private var connectionStatus: String {
        if session.isConnected {
            return session.permissionLevel.displayName
        }
        return L10n.RemoteNodes.RemoteNodes.Room.disconnected
    }

    // MARK: - Messages View

    private var messagesView: some View {
        Group {
            if !viewModel.hasLoadedOnce {
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
                    scrollToBottomRequest: $scrollToBottomRequest,
                    scrollToMentionRequest: .constant(0),
                    initialScrollRequest: .constant(0)
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
            showTimestamp: RoomConversationViewModel.shouldShowTimestamp(at: index, in: viewModel.messages),
            onRetry: message.status == .failed ? {
                Task {
                    await viewModel.retryMessage(id: message.id)
                }
            } : nil
        )
    }

    private var emptyMessagesView: some View {
        VStack(spacing: 16) {
            NodeAvatar(publicKey: session.publicKey, role: .roomServer, size: 80)

            Text(session.name)
                .font(.title2)
                .bold()

            Text(L10n.RemoteNodes.RemoteNodes.Room.noMessagesYet)
                .foregroundStyle(.secondary)

            if session.canPost {
                Text(L10n.RemoteNodes.RemoteNodes.Room.beFirstToPost)
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
            placeholder: L10n.RemoteNodes.RemoteNodes.Room.publicMessage,
            maxBytes: ProtocolLimits.maxDirectMessageLength
        ) {
            // Force scroll to bottom on user send (before message is added)
            scrollToBottomRequest += 1
            Task {
                await viewModel.sendMessage()
            }
        }
    }

    private var readOnlyBanner: some View {
        RoomStatusBanner(
            icon: "eye",
            title: L10n.RemoteNodes.RemoteNodes.Room.viewOnlyBanner,
            hint: L10n.RemoteNodes.RemoteNodes.Room.viewOnlyHint,
            style: AnyShapeStyle(.secondary),
            isBold: false,
            action: { roomToAuthenticate = session }
        )
    }

    private var disconnectedBanner: some View {
        RoomStatusBanner(
            icon: "exclamationmark.triangle.fill",
            title: L10n.RemoteNodes.RemoteNodes.Room.disconnectedBanner,
            hint: L10n.RemoteNodes.RemoteNodes.Room.disconnectedHint,
            style: AnyShapeStyle(.orange),
            isBold: true,
            action: { roomToAuthenticate = session }
        )
    }
}

// MARK: - Room Status Banner

private struct RoomStatusBanner: View {
    let icon: String
    let title: String
    let hint: String
    let style: AnyShapeStyle
    let isBold: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                HStack {
                    Image(systemName: icon)
                    Text(title)
                }
                .bold(isBold)
                Text(hint)
                    .font(.caption)
            }
            .font(.subheadline)
            .foregroundStyle(style)
            .frame(maxWidth: .infinity)
            .padding()
            .background(.bar)
        }
        .accessibilityLabel(title)
        .accessibilityHint(hint)
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
    .environment(\.appState, AppState())
}
