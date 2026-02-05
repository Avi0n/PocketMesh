import SwiftUI
import PocketMeshServices
import OSLog

private let chatsViewLogger = Logger(subsystem: "com.pocketmesh", category: "ChatsView")

struct ChatsView: View {
    @Environment(\.appState) private var appState
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
    @State private var routeBeingDeleted: ChatRoute?

    @State private var roomToAuthenticate: RemoteNodeSessionDTO?
    @State private var roomToDelete: RemoteNodeSessionDTO?
    @State private var showRoomDeleteAlert = false
    @State private var sidebarListID = UUID()
    @State private var pendingChatContact: ContactDTO?
    @State private var pendingChannel: ChannelDTO?
    @State private var hashtagToJoin: HashtagJoinRequest?
    @State private var showOfflineRefreshAlert = false

    private var shouldUseSplitView: Bool {
        horizontalSizeClass == .regular
    }

    private var filteredFavorites: [Conversation] {
        viewModel.favoriteConversations.filtered(by: selectedFilter, searchText: searchText)
    }

    private var filteredOthers: [Conversation] {
        viewModel.nonFavoriteConversations.filtered(by: selectedFilter, searchText: searchText)
    }

    private var filteredConversations: [Conversation] {
        filteredFavorites + filteredOthers
    }

    private var emptyStateMessage: (title: String, description: String, systemImage: String) {
        switch selectedFilter {
        case .none:
            return (L10n.Chats.Chats.EmptyState.NoConversations.title, L10n.Chats.Chats.EmptyState.NoConversations.description, "message")
        case .unread:
            return (L10n.Chats.Chats.EmptyState.NoUnread.title, L10n.Chats.Chats.EmptyState.NoUnread.description, "checkmark.circle")
        case .directMessages:
            return (L10n.Chats.Chats.EmptyState.NoDirectMessages.title, L10n.Chats.Chats.EmptyState.NoDirectMessages.description, "person")
        case .channels:
            return (L10n.Chats.Chats.EmptyState.NoChannels.title, L10n.Chats.Chats.EmptyState.NoChannels.description, "number")
        case .favorites:
            return (L10n.Chats.Chats.EmptyState.NoFavorites.title, L10n.Chats.Chats.EmptyState.NoFavorites.description, "star")
        }
    }

    @ViewBuilder
    private func conversationListState<Content: View>(
        @ViewBuilder listContent: () -> Content
    ) -> some View {
        if !viewModel.hasLoadedOnce {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredConversations.isEmpty {
            ContentUnavailableView {
                Label(emptyStateMessage.title, systemImage: emptyStateMessage.systemImage)
            } description: {
                Text(emptyStateMessage.description)
            } actions: {
                if selectedFilter != nil {
                    Button(L10n.Chats.Chats.Filter.clear) {
                        selectedFilter = nil
                    }
                }
            }
        } else {
            listContent()
        }
    }

    private func applyChatsListModifiers<Content: View>(
        to content: Content,
        onTaskStart: @escaping () async -> Void
    ) -> some View {
        content
            .navigationTitle(L10n.Chats.Chats.title)
            .searchable(text: $searchText, prompt: L10n.Chats.Chats.Search.placeholder)
            .searchScopes($selectedFilter, activation: .onSearchPresentation) {
                Text(L10n.Chats.Chats.Filter.all).tag(nil as ChatFilter?)
                ForEach(ChatFilter.allCases) { filter in
                    Text(filter.localizedName).tag(filter as ChatFilter?)
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
                            Label(L10n.Chats.Chats.Compose.newChat, systemImage: "person")
                        }

                        Button {
                            showingChannelOptions = true
                        } label: {
                            Label(L10n.Chats.Chats.Compose.newChannel, systemImage: "number")
                        }
                    } label: {
                        Label(L10n.Chats.Chats.Compose.newMessage, systemImage: "square.and.pencil")
                    }
                }
            }
            .refreshable {
                if appState.connectionState != .ready {
                    showOfflineRefreshAlert = true
                } else {
                    await refreshConversations()
                }
            }
            .alert(L10n.Chats.Chats.Alert.CannotRefresh.title, isPresented: $showOfflineRefreshAlert) {
                Button(L10n.Chats.Chats.Common.ok, role: .cancel) { }
            } message: {
                Text(L10n.Chats.Chats.Alert.CannotRefresh.message)
            }
            .task {
                await onTaskStart()
            }
            .onChange(of: appState.pendingChatContact) { _, _ in
                handlePendingNavigation()
            }
            .onChange(of: appState.pendingChannel) { _, _ in
                handlePendingChannelNavigation()
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
    private var filterMenu: some View {
        let filterIcon = selectedFilter == nil
            ? "line.3.horizontal.decrease.circle"
            : "line.3.horizontal.decrease.circle.fill"
        let accessibilityLabel = selectedFilter.map { L10n.Chats.Chats.Filter.accessibilityLabelActive($0.localizedName) }
            ?? L10n.Chats.Chats.Filter.accessibilityLabel

        Menu {
            Picker(L10n.Chats.Chats.Filter.title, selection: $selectedFilter) {
                Text(L10n.Chats.Chats.Filter.all).tag(nil as ChatFilter?)
                ForEach(ChatFilter.allCases) { filter in
                    Label(filter.localizedName, systemImage: filter.systemImage)
                        .tag(filter as ChatFilter?)
                }
            }
            .pickerStyle(.inline)
        } label: {
            if selectedFilter == nil {
                Label(L10n.Chats.Chats.Filter.title, systemImage: filterIcon)
                    .accessibilityLabel(accessibilityLabel)
            } else {
                Label(L10n.Chats.Chats.Filter.title, systemImage: filterIcon)
                    .foregroundStyle(.tint)
                    .accessibilityLabel(accessibilityLabel)
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
                if let channel = pendingChannel {
                    pendingChannel = nil
                    navigate(to: .channel(channel))
                }
            }
        }) {
            ChannelOptionsSheet { channel in
                pendingChannel = channel
            }
        }
        .sheet(item: $roomToAuthenticate) { session in
            RoomAuthenticationSheet(session: session) { authenticatedSession in
                roomToAuthenticate = nil
                navigate(to: .room(authenticatedSession))
            }
            .presentationSizing(.page)
        }
        .alert(L10n.Chats.Chats.Alert.LeaveRoom.title, isPresented: $showRoomDeleteAlert) {
            Button(L10n.Chats.Chats.Common.cancel, role: .cancel) {
                roomToDelete = nil
                routeBeingDeleted = nil
            }
            Button(L10n.Chats.Chats.Alert.LeaveRoom.confirm, role: .destructive) {
                Task {
                    if let session = roomToDelete {
                        routeBeingDeleted = .room(session)
                        await deleteRoom(session)
                    }
                    roomToDelete = nil
                    routeBeingDeleted = nil
                }
            }
        } message: {
            Text(L10n.Chats.Chats.Alert.LeaveRoom.message)
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
        .id(sidebarListID)
    }

    private var splitSidebarContent: some View {
        applyChatsListModifiers(
            to: conversationListState {
                ConversationListContent(
                    viewModel: viewModel,
                    favoriteConversations: filteredFavorites,
                    otherConversations: filteredOthers,
                    selection: $selectedRoute,
                    onDeleteConversation: handleDeleteConversation
                )
            },
            onTaskStart: {
                chatsViewLogger.debug("ChatsView: task started, services=\(appState.services != nil)")
                viewModel.configure(appState: appState)
                await loadConversations()
                chatsViewLogger.debug("ChatsView: loaded, conversations=\(viewModel.conversations.count), channels=\(viewModel.channels.count), rooms=\(viewModel.roomSessions.count)")
                announceOfflineStateIfNeeded()
                handlePendingNavigation()
                handlePendingChannelNavigation()
                handlePendingRoomNavigation()
            }
        )
        .onChange(of: selectedRoute) { oldValue, newValue in
            // Reload conversations when navigating away (but not when clearing for deletion)
            if oldValue != nil {
                let didClearSelectionForDeletion = (newValue == nil && oldValue == routeBeingDeleted)
                if !didClearSelectionForDeletion {
                    Task {
                        await loadConversations()
                    }
                }
            }

            if case .room(let session) = newValue, !session.isConnected {
                roomToAuthenticate = session
                selectedRoute = nil
                lastSelectedRoomIsConnected = nil
                routeBeingDeleted = nil
                return
            }

            lastSelectedRoomIsConnected = {
                guard case .room(let session) = newValue else { return nil }
                return session.isConnected
            }()
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
            ContentUnavailableView(L10n.Chats.Chats.EmptyState.selectConversation, systemImage: "message")
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
        applyChatsListModifiers(
            to: conversationListState {
                ConversationListContent(
                    viewModel: viewModel,
                    favoriteConversations: filteredFavorites,
                    otherConversations: filteredOthers,
                    onNavigate: { route in
                        navigationPath.append(route)
                    },
                    onRequestRoomAuth: { session in
                        roomToAuthenticate = session
                    },
                    onDeleteConversation: handleDeleteConversation
                )
            },
            onTaskStart: {
                viewModel.configure(appState: appState)
                await loadConversations()
                announceOfflineStateIfNeeded()
                handlePendingNavigation()
                handlePendingChannelNavigation()
                handlePendingRoomNavigation()
            }
        )
    }

    private func loadConversations() async {
        guard let deviceID = appState.currentDeviceID else { return }
        viewModel.configure(appState: appState)
        await viewModel.loadAllConversations(deviceID: deviceID)

        // If we're in the middle of deleting an item, ensure it stays removed
        // This handles race conditions where a reload happens before DB delete completes
        if let routeBeingDeleted {
            viewModel.removeConversation(routeBeingDeleted.toConversation())
        }

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

    private func announceOfflineStateIfNeeded() {
        guard UIAccessibility.isVoiceOverRunning,
              appState.connectionState == .disconnected,
              appState.currentDeviceID != nil else { return }

        UIAccessibility.post(
            notification: .announcement,
            argument: L10n.Chats.Chats.Accessibility.offlineAnnouncement
        )
    }

    private func refreshConversations() async {
        guard let deviceID = appState.currentDeviceID else { return }
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

    private func handleDeleteConversation(_ conversation: Conversation) {
        switch conversation {
        case .direct(let contact):
            routeBeingDeleted = .direct(contact)
            deleteDirectConversation(contact)

        case .channel(let channel):
            routeBeingDeleted = .channel(channel)
            deleteChannelConversation(channel)

        case .room(let session):
            roomToDelete = session
            showRoomDeleteAlert = true
        }
    }

    private func deleteDirectConversation(_ contact: ContactDTO) {
        if shouldUseSplitView && selectedRoute == .direct(contact) {
            selectedRoute = nil
        }

        viewModel.removeConversation(.direct(contact))
        sidebarListID = UUID()

        if !shouldUseSplitView && activeRoute == .direct(contact) {
            navigationPath.removeLast(navigationPath.count)
            activeRoute = nil
            appState.tabBarVisibility = .visible
        }

        Task {
            try? await viewModel.deleteConversation(for: contact)
            routeBeingDeleted = nil
        }
    }

    private func deleteChannelConversation(_ channel: ChannelDTO) {
        if shouldUseSplitView && selectedRoute == .channel(channel) {
            selectedRoute = nil
        }

        viewModel.removeConversation(.channel(channel))
        sidebarListID = UUID()

        if !shouldUseSplitView && activeRoute == .channel(channel) {
            navigationPath.removeLast(navigationPath.count)
            activeRoute = nil
            appState.tabBarVisibility = .visible
        }

        Task {
            await deleteChannel(channel)
            routeBeingDeleted = nil
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

            await MainActor.run {
                if shouldUseSplitView && selectedRoute == .room(session) {
                    selectedRoute = nil
                }

                viewModel.removeConversation(.room(session))
                sidebarListID = UUID()

                if !shouldUseSplitView && activeRoute == .room(session) {
                    navigationPath.removeLast(navigationPath.count)
                    activeRoute = nil
                    appState.tabBarVisibility = .visible
                }
            }
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
            await appState.services?.notificationService.removeDeliveredNotifications(
                forChannelIndex: channel.index,
                deviceID: channel.deviceID
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

    private func handlePendingChannelNavigation() {
        guard let channel = appState.pendingChannel else { return }
        navigate(to: .channel(channel))
        appState.clearPendingChannelNavigation()
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

            guard let deviceID = appState.currentDeviceID else {
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
                        try await appState.offlineDataStore?.fetchChannels(deviceID: deviceID) ?? []
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
        .environment(\.appState, AppState())
}
