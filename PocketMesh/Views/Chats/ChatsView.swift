import SwiftUI
import PocketMeshServices
import OSLog

private let chatsViewLogger = Logger(subsystem: "com.pocketmesh", category: "ChatsView")

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
            viewModel.configure(appState: appState)
            await loadConversations()
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

                case .channel(let channel):
                    ChannelConversationRow(channel: channel, viewModel: viewModel)
                        .tag(ChatDestination.channel(channel))

                case .room(let session):
                    RoomConversationRow(session: session)
                        .tag(ChatDestination.room(session))
                }
            }
            .onDelete(perform: deleteConversations)
        }
        .listStyle(.plain)
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

    private func deleteConversations(at offsets: IndexSet) {
        let conversationsToDelete = offsets.map { filteredConversations[$0] }

        for conversation in conversationsToDelete {
            switch conversation {
            case .room(let session):
                roomToDelete = session
                showRoomDeleteAlert = true

            case .direct(let contact):
                viewModel.removeConversation(conversation)
                Task {
                    try? await viewModel.deleteConversation(for: contact)
                }

            case .channel(let channel):
                viewModel.removeConversation(conversation)
                Task {
                    await deleteChannel(channel)
                }
            }
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
}

#Preview {
    ChatsView()
        .environment(AppState())
}
