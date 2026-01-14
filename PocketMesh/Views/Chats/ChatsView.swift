import SwiftUI
import PocketMeshServices
import OSLog

private let chatsViewLogger = Logger(subsystem: "com.pocketmesh", category: "ChatsView")

private struct HashtagJoinRequest: Identifiable, Hashable {
    let id: String
}

struct ChatsView: View {
    private enum ChatDestination: Hashable {
        case direct(ContactDTO)
        case channel(ChannelDTO)
        case room(RemoteNodeSessionDTO)
    }

    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var viewModel = ChatViewModel()
    @State private var searchText = ""
    @State private var selectedFilter: ChatFilter? = nil
    @State private var showingNewChat = false
    @State private var showingChannelOptions = false

    @State private var selectedDestination: ChatDestination?

    @State private var roomToAuthenticate: RemoteNodeSessionDTO?
    @State private var roomToDelete: RemoteNodeSessionDTO?
    @State private var showRoomDeleteAlert = false
    @State private var pendingChatContact: ContactDTO?
    @State private var hashtagToJoin: HashtagJoinRequest?

    private var shouldUseSplitView: Bool {
        horizontalSizeClass == .regular
    }

    private var filteredConversations: [Conversation] {
        viewModel.allConversations.filtered(by: selectedFilter, searchText: searchText)
    }

    private var filterAccessibilityLabel: String {
        if let filter = selectedFilter {
            return "Filter conversations, currently showing \(filter.rawValue)"
        }
        return "Filter conversations"
    }

    private var emptyStateMessage: (title: String, description: String, systemImage: String) {
        switch selectedFilter {
        case .none:
            return ("No Conversations", "Start a conversation from Contacts", "message")
        case .unread:
            return ("No Unread Messages", "You're all caught up", "checkmark.circle")
        case .directMessages:
            return ("No Direct Messages", "Start a chat from Contacts", "person")
        case .channels:
            return ("No Channels", "Join or create a channel", "number")
        case .favorites:
            return ("No Favorites", "Mark contacts as favorites to see them here", "star")
        }
    }

    private var filterIcon: String {
        selectedFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
    }

    @ViewBuilder
    private var filterMenu: some View {
        Menu {
            Picker("Filter", selection: $selectedFilter) {
                Text("All").tag(nil as ChatFilter?)
                ForEach(ChatFilter.allCases) { filter in
                    Label(filter.rawValue, systemImage: filter.systemImage)
                        .tag(filter as ChatFilter?)
                }
            }
            .pickerStyle(.inline)
        } label: {
            if selectedFilter == nil {
                Label("Filter", systemImage: filterIcon)
                    .accessibilityLabel(filterAccessibilityLabel)
            } else {
                Label("Filter", systemImage: filterIcon)
                    .foregroundStyle(.tint)
                    .accessibilityLabel(filterAccessibilityLabel)
            }
        }
    }

    var body: some View {
        if shouldUseSplitView {
            NavigationSplitView {
                NavigationStack {
                    sidebarContent
                }
            } detail: {
                NavigationStack {
                    detailContent
                }
            }
            .environment(\.openURL, OpenURLAction { url in
                guard url.scheme == "pocketmesh-hashtag" else {
                    return .systemAction
                }
                guard let channelName = url.host else {
                    chatsViewLogger.error("Hashtag URL missing host: \(url.absoluteString, privacy: .public)")
                    return .handled
                }
                handleHashtagTap(name: channelName)
                return .handled
            })
            .sheet(item: $hashtagToJoin) { request in
                JoinHashtagFromMessageView(channelName: request.id) { channel in
                    hashtagToJoin = nil
                    if let channel {
                        selectedDestination = .channel(channel)
                    }
                }
                .presentationDetents([.medium])
            }
        } else {
            ChatsListView()
        }
    }

    private var sidebarContent: some View {
        Group {
            if viewModel.isLoading && viewModel.allConversations.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredConversations.isEmpty {
                ContentUnavailableView {
                    Label(emptyStateMessage.title, systemImage: emptyStateMessage.systemImage)
                } description: {
                    Text(emptyStateMessage.description)
                } actions: {
                    if selectedFilter != nil {
                        Button("Clear Filter") {
                            selectedFilter = nil
                        }
                    }
                }
            } else {
                conversationSplitList
            }
        }
        .navigationTitle("Chats")
        .searchable(text: $searchText, prompt: "Search conversations")
        .searchScopes($selectedFilter, activation: .onSearchPresentation) {
            Text("All").tag(nil as ChatFilter?)
            ForEach(ChatFilter.allCases) { filter in
                Text(filter.rawValue).tag(filter as ChatFilter?)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                BLEStatusIndicatorView()
            }
            ToolbarItem(placement: .topBarTrailing) {
                filterMenu
            }
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button {
                        showingNewChat = true
                    } label: {
                        Label("New Chat", systemImage: "person")
                    }

                    Button {
                        showingChannelOptions = true
                    } label: {
                        Label("New Channel", systemImage: "number")
                    }
                } label: {
                    Label("New Message", systemImage: "square.and.pencil")
                }
            }
        }
        .sheet(isPresented: $showingNewChat, onDismiss: {
            if let contact = pendingChatContact {
                pendingChatContact = nil
                selectedDestination = .direct(contact)
            }
        }) {
            NewChatView(viewModel: viewModel) { contact in
                pendingChatContact = contact
                showingNewChat = false
            }
        }
        .sheet(isPresented: $showingChannelOptions, onDismiss: {
            Task {
                await loadConversations()
            }
        }) {
            ChannelOptionsSheet()
        }
        .sheet(item: $roomToAuthenticate) { session in
            RoomAuthenticationSheet(session: session) { authenticatedSession in
                roomToAuthenticate = nil
                selectedDestination = .room(authenticatedSession)
            }
            .presentationSizing(.page)
        }
        .alert("Leave Room", isPresented: $showRoomDeleteAlert) {
            Button("Cancel", role: .cancel) {
                roomToDelete = nil
            }
            Button("Leave", role: .destructive) {
                Task {
                    if let session = roomToDelete {
                        await deleteRoom(session)
                    }
                    roomToDelete = nil
                }
            }
        } message: {
            Text("This will remove the room from your chat list, delete all room messages, and remove the associated contact.")
        }
        .refreshable {
            await refreshConversations()
        }
        .task {
            chatsViewLogger.info("ChatsView: task started, services=\(appState.services != nil)")
            viewModel.configure(appState: appState)
            await loadConversations()
            chatsViewLogger.info("ChatsView: loaded, conversations=\(viewModel.conversations.count), channels=\(viewModel.channels.count), rooms=\(viewModel.roomSessions.count)")
            handlePendingNavigation()
            handlePendingRoomNavigation()
        }
        .onChange(of: selectedDestination) { _, newValue in
            guard let newValue else { return }
            if case .room(let session) = newValue, !session.isConnected {
                roomToAuthenticate = session
                selectedDestination = nil
            }
        }
        .onChange(of: appState.pendingChatContact) { _, _ in
            handlePendingNavigation()
        }
        .onChange(of: appState.pendingRoomSession) { _, _ in
            handlePendingRoomNavigation()
        }
        .onChange(of: appState.servicesVersion) { _, _ in
            Task {
                await loadConversations()
            }
        }
        .onChange(of: appState.conversationsVersion) { _, _ in
            Task {
                await loadConversations()
            }
        }
    }

    private var conversationSplitList: some View {
        List(selection: $selectedDestination) {
            ForEach(filteredConversations) { conversation in
                switch conversation {
                case .direct(let contact):
                    ConversationRow(contact: contact, viewModel: viewModel)
                        .tag(ChatDestination.direct(contact))
                        .conversationSwipeActions(conversation: conversation, viewModel: viewModel) {
                            deleteDirectConversation(contact)
                        }

                case .channel(let channel):
                    ChannelConversationRow(channel: channel, viewModel: viewModel)
                        .tag(ChatDestination.channel(channel))
                        .conversationSwipeActions(conversation: conversation, viewModel: viewModel) {
                            deleteChannelConversation(channel)
                        }

                case .room(let session):
                    RoomConversationRow(session: session)
                        .tag(ChatDestination.room(session))
                        .conversationSwipeActions(conversation: conversation, viewModel: viewModel) {
                            roomToDelete = session
                            showRoomDeleteAlert = true
                        }
                }
            }
        }
        .listStyle(.plain)
    }

    private func deleteDirectConversation(_ contact: ContactDTO) {
        viewModel.removeConversation(.direct(contact))
        Task {
            try? await viewModel.deleteConversation(for: contact)
        }
    }

    private func deleteChannelConversation(_ channel: ChannelDTO) {
        viewModel.removeConversation(.channel(channel))
        Task {
            await deleteChannel(channel)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedDestination {
        case .direct(let contact):
            ChatView(contact: contact, parentViewModel: viewModel)
                .id(contact.id)
        case .channel(let channel):
            ChannelChatView(channel: channel, parentViewModel: viewModel)
                .id(channel.id)
        case .room(let session):
            RoomConversationView(session: session)
                .id(session.id)
        case .none:
            ContentUnavailableView("Select a conversation", systemImage: "message")
        }
    }

    private func loadConversations() async {
        guard let deviceID = appState.connectedDevice?.id else { return }
        viewModel.configure(appState: appState)
        await viewModel.loadAllConversations(deviceID: deviceID)
    }

    private func refreshConversations() async {
        guard let deviceID = appState.connectedDevice?.id else { return }
        await viewModel.loadAllConversations(deviceID: deviceID)
    }

    private func handlePendingNavigation() {
        guard let contact = appState.pendingChatContact else { return }
        selectedDestination = .direct(contact)
        appState.clearPendingNavigation()
    }

    private func handlePendingRoomNavigation() {
        guard let session = appState.pendingRoomSession else { return }
        selectedDestination = .room(session)
        appState.clearPendingRoomNavigation()
    }

    private func deleteRoom(_ session: RemoteNodeSessionDTO) async {
        do {
            try await appState.services?.roomServerService.leaveRoom(
                sessionID: session.id,
                publicKey: session.publicKey
            )

            try await appState.services?.contactService.removeContact(
                deviceID: session.deviceID,
                publicKey: session.publicKey
            )

            await appState.services?.notificationService.updateBadgeCount()

            if selectedDestination == .room(session) {
                selectedDestination = nil
            }

            await loadConversations()
        } catch {
            chatsViewLogger.error("Failed to delete room: \(error)")
        }
    }

    private func deleteChannel(_ channel: ChannelDTO) async {
        guard let channelService = appState.services?.channelService else { return }

        do {
            try await channelService.clearChannel(
                deviceID: channel.deviceID,
                index: channel.index
            )
            await appState.services?.notificationService.updateBadgeCount()
        } catch {
            chatsViewLogger.error("Failed to delete channel: \(error)")
            await loadConversations()
        }
    }

    // MARK: - Hashtag Channel Handling

    private func handleHashtagTap(name: String) {
        Task {
            let normalizedName = HashtagUtilities.normalizeHashtagName(name)
            guard HashtagUtilities.isValidHashtagName(normalizedName) else {
                chatsViewLogger.error("Invalid hashtag name in tap: \(name, privacy: .public)")
                return
            }

            let fullName = "#\(normalizedName)"

            guard let deviceID = appState.connectedDevice?.id else {
                await MainActor.run {
                    hashtagToJoin = HashtagJoinRequest(id: fullName)
                }
                return
            }

            if let channel = await findChannelByName(fullName, deviceID: deviceID) {
                await MainActor.run {
                    selectedDestination = .channel(channel)
                }
            } else {
                await MainActor.run {
                    hashtagToJoin = HashtagJoinRequest(id: fullName)
                }
            }
        }
    }

    private func findChannelByName(_ name: String, deviceID: UUID) async -> ChannelDTO? {
        do {
            let channels = try await appState.services?.dataStore.fetchChannels(deviceID: deviceID) ?? []
            return channels.first { channel in
                channel.name.localizedCaseInsensitiveCompare(name) == .orderedSame
            }
        } catch {
            chatsViewLogger.error("Failed to fetch channels for hashtag lookup: \(error)")
            return nil
        }
    }
}

#Preview {
    ChatsView()
        .environment(AppState())
}
