import SwiftUI
import PocketMeshServices
import OSLog

private let chatsViewLogger = Logger(subsystem: "com.pocketmesh", category: "ChatsView")

struct ChatsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var viewModel = ChatViewModel()
    @State private var searchText = ""
    @State private var selectedFilter: ChatFilter? = nil
    @State private var showingNewChat = false
    @State private var showingChannelOptions = false

    @State private var selectedRoute: ChatRoute?
    @State private var navigationPath = NavigationPath()
    @State private var activeRoute: ChatRoute?
    @State private var lastSelectedRoomIsConnected: Bool?

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
        Group {
            if shouldUseSplitView {
                splitLayout
            } else {
                stackLayout
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == HashtagDeeplinkSupport.scheme else {
                return .systemAction
            }
            guard let channelName = HashtagDeeplinkSupport.channelNameFromURL(url) else {
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
                    navigate(to: .channel(channel))
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingNewChat, onDismiss: {
            if let contact = pendingChatContact {
                pendingChatContact = nil
                navigate(to: .direct(contact))
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
                navigate(to: .room(authenticatedSession))
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
    }

    private var splitLayout: some View {
        NavigationSplitView {
            NavigationStack {
                splitSidebarContent
            }
        } detail: {
            NavigationStack {
                splitDetailContent
            }
        }
    }

    private var splitSidebarContent: some View {
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
                ConversationListContent(
                    viewModel: viewModel,
                    conversations: filteredConversations,
                    selection: $selectedRoute,
                    onDeleteConversation: handleDeleteConversation
                )
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
        .onChange(of: selectedRoute) { oldValue, newValue in
            if oldValue != nil {
                Task {
                    await loadConversations()
                }
            }

            if case .room(let session) = newValue, !session.isConnected {
                roomToAuthenticate = session
                selectedRoute = nil
                lastSelectedRoomIsConnected = nil
                return
            }

            lastSelectedRoomIsConnected = {
                guard case .room(let session) = newValue else { return nil }
                return session.isConnected
            }()
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

    @ViewBuilder
    private var splitDetailContent: some View {
        switch selectedRoute {
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

    private var stackLayout: some View {
        NavigationStack(path: $navigationPath) {
            stackRootContent
                .navigationDestination(for: ChatRoute.self) { route in
                    switch route {
                    case .direct(let contact):
                        ChatView(contact: contact, parentViewModel: viewModel)
                            .id(contact.id)
                            .onAppear {
                                activeRoute = route
                                appState.tabBarVisibility = .hidden
                            }

                    case .channel(let channel):
                        ChannelChatView(channel: channel, parentViewModel: viewModel)
                            .id(channel.id)
                            .onAppear {
                                activeRoute = route
                                appState.tabBarVisibility = .hidden
                            }

                    case .room(let session):
                        RoomConversationView(session: session)
                            .id(session.id)
                            .onAppear {
                                activeRoute = route
                                appState.tabBarVisibility = .hidden
                            }
                    }
                }
                .onChange(of: navigationPath) { _, newPath in
                    if newPath.isEmpty {
                        activeRoute = nil
                        appState.tabBarVisibility = .visible
                        Task {
                            await loadConversations()
                        }
                    }
                }
                .toolbarVisibility(appState.tabBarVisibility, for: .tabBar)
        }
    }

    private var stackRootContent: some View {
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
                ConversationListContent(
                    viewModel: viewModel,
                    conversations: filteredConversations,
                    onNavigate: { route in
                        navigationPath.append(route)
                    },
                    onRequestRoomAuth: { session in
                        roomToAuthenticate = session
                    },
                    onDeleteConversation: handleDeleteConversation
                )
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
        .refreshable {
            await refreshConversations()
        }
        .task {
            viewModel.configure(appState: appState)
            await loadConversations()
            handlePendingNavigation()
            handlePendingRoomNavigation()
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

    private func loadConversations() async {
        guard let deviceID = appState.connectedDevice?.id else { return }
        viewModel.configure(appState: appState)
        await viewModel.loadAllConversations(deviceID: deviceID)

        if let selectedRoute {
            self.selectedRoute = selectedRoute.refreshedPayload(from: viewModel.allConversations)
        }
        if let activeRoute {
            self.activeRoute = activeRoute.refreshedPayload(from: viewModel.allConversations)
        }

        if shouldUseSplitView,
           lastSelectedRoomIsConnected == true,
           case .room(let session) = self.selectedRoute,
           !session.isConnected {
            roomToAuthenticate = session
            self.selectedRoute = nil
        }

        lastSelectedRoomIsConnected = {
            guard case .room(let session) = self.selectedRoute else { return nil }
            return session.isConnected
        }()
    }

    private func refreshConversations() async {
        guard let deviceID = appState.connectedDevice?.id else { return }
        await viewModel.loadAllConversations(deviceID: deviceID)
    }

    private func navigate(to route: ChatRoute) {
        if shouldUseSplitView {
            selectedRoute = route
            return
        }

        if case .room(let session) = route, !session.isConnected {
            roomToAuthenticate = session
            return
        }

        appState.tabBarVisibility = .hidden
        navigationPath.removeLast(navigationPath.count)
        navigationPath.append(route)
    }

    private func closeIfShowing(route: ChatRoute) {
        if shouldUseSplitView {
            if selectedRoute == route {
                selectedRoute = nil
            }
            return
        }

        if activeRoute == route {
            navigationPath.removeLast(navigationPath.count)
            activeRoute = nil
            appState.tabBarVisibility = .visible
        }
    }

    private func handleDeleteConversation(_ conversation: Conversation) {
        switch conversation {
        case .direct(let contact):
            deleteDirectConversation(contact)
        case .channel(let channel):
            deleteChannelConversation(channel)
        case .room(let session):
            roomToDelete = session
            showRoomDeleteAlert = true
        }
    }

    private func deleteDirectConversation(_ contact: ContactDTO) {
        closeIfShowing(route: .direct(contact))
        viewModel.removeConversation(.direct(contact))
        Task {
            try? await viewModel.deleteConversation(for: contact)
        }
    }

    private func deleteChannelConversation(_ channel: ChannelDTO) {
        closeIfShowing(route: .channel(channel))
        viewModel.removeConversation(.channel(channel))
        Task {
            await deleteChannel(channel)
        }
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

            closeIfShowing(route: .room(session))

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

    private func handlePendingNavigation() {
        guard let contact = appState.pendingChatContact else { return }
        navigate(to: .direct(contact))
        appState.clearPendingNavigation()
    }

    private func handlePendingRoomNavigation() {
        guard let session = appState.pendingRoomSession else { return }
        navigate(to: .room(session))
        appState.clearPendingRoomNavigation()
    }

    private func handleHashtagTap(name: String) {
        Task {
            guard let fullName = HashtagDeeplinkSupport.fullChannelName(from: name) else {
                chatsViewLogger.error("Invalid hashtag name in tap: \(name, privacy: .public)")
                return
            }

            guard let deviceID = appState.connectedDevice?.id else {
                await MainActor.run {
                    hashtagToJoin = HashtagJoinRequest(id: fullName)
                }
                return
            }

            do {
                if let channel = try await HashtagDeeplinkSupport.findChannelByName(
                    fullName,
                    deviceID: deviceID,
                    fetchChannels: { deviceID in
                        try await appState.services?.dataStore.fetchChannels(deviceID: deviceID) ?? []
                    }
                ) {
                    await MainActor.run {
                        navigate(to: .channel(channel))
                    }
                } else {
                    await MainActor.run {
                        hashtagToJoin = HashtagJoinRequest(id: fullName)
                    }
                }
            } catch {
                chatsViewLogger.error("Failed to fetch channels for hashtag lookup: \(error)")
                await MainActor.run {
                    hashtagToJoin = HashtagJoinRequest(id: fullName)
                }
            }
        }
    }
}

#Preview {
    ChatsView()
        .environment(AppState())
}
