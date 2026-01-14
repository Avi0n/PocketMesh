import SwiftUI
import PocketMeshServices
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh", category: "ChatsListView")

private struct HashtagJoinRequest: Identifiable, Hashable {
    let id: String
}

/// List of active conversations
struct ChatsListView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = ChatViewModel()
    @State private var searchText = ""
    @State private var selectedFilter: ChatFilter? = nil
    @State private var showingNewChat = false
    @State private var showingChannelOptions = false
    @State private var navigationPath = NavigationPath()
    @State private var roomToAuthenticate: RemoteNodeSessionDTO?
    @State private var roomToDelete: RemoteNodeSessionDTO?
    @State private var showRoomDeleteAlert = false
    @State private var pendingChatContact: ContactDTO?
    @State private var hashtagToJoin: HashtagJoinRequest?

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
        NavigationStack(path: $navigationPath) {
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
                    conversationList
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
                    navigationPath.append(contact)
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
            .refreshable {
                await refreshConversations()
            }
            .task {
                viewModel.configure(appState: appState)
                await loadConversations()
                // Handle pending navigation from other tabs (e.g., Map)
                handlePendingNavigation()
            }
            .navigationDestination(for: ContactDTO.self) { contact in
                ChatView(contact: contact, parentViewModel: viewModel)
                    .onAppear { appState.tabBarVisibility = .hidden }
            }
            .navigationDestination(for: ChannelDTO.self) { channel in
                ChannelChatView(channel: channel, parentViewModel: viewModel)
                    .onAppear { appState.tabBarVisibility = .hidden }
            }
            .navigationDestination(for: RemoteNodeSessionDTO.self) { session in
                RoomConversationView(session: session)
                    .onAppear { appState.tabBarVisibility = .hidden }
            }
            .onChange(of: appState.pendingChatContact) { _, _ in
                handlePendingNavigation()
            }
            .onChange(of: appState.servicesVersion) { _, _ in
                // Services changed (device switch, reconnect) - reload conversations
                Task {
                    await loadConversations()
                }
            }
            .onChange(of: appState.conversationsVersion) { _, _ in
                Task {
                    await loadConversations()
                }
            }
            .onChange(of: appState.pendingRoomSession) { _, _ in
                handlePendingRoomNavigation()
            }
            .onChange(of: navigationPath) { _, newPath in
                // Restore tab bar when navigating back to the list
                if newPath.isEmpty {
                    appState.tabBarVisibility = .visible
                }
            }
            .sheet(item: $roomToAuthenticate) { session in
                RoomAuthenticationSheet(session: session) { authenticatedSession in
                    roomToAuthenticate = nil
                    navigationPath.append(authenticatedSession)
                }
                .presentationSizing(.page)
            }
            .alert("Leave Room", isPresented: $showRoomDeleteAlert) {
                Button("Cancel", role: .cancel) {
                    roomToDelete = nil
                }
                Button("Leave Room", role: .destructive) {
                    if let session = roomToDelete {
                        Task {
                            await deleteRoom(session)
                            roomToDelete = nil
                        }
                    }
                }
            } message: {
                Text("This will remove the room from your chat list, delete all room messages, and remove the associated contact.")
            }
            .sheet(item: $hashtagToJoin) { request in
                JoinHashtagFromMessageView(channelName: request.id) { channel in
                    hashtagToJoin = nil
                    if let channel {
                        navigationPath.append(channel)
                    }
                }
                .presentationDetents([.medium])
            }
            .toolbarVisibility(appState.tabBarVisibility, for: .tabBar)
        }
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "pocketmesh-hashtag" else {
                return .systemAction
            }
            guard let channelName = url.host else {
                logger.error("Hashtag URL missing host: \(url.absoluteString, privacy: .public)")
                return .handled
            }
            handleHashtagTap(name: channelName)
            return .handled
        })
    }

    private func handlePendingRoomNavigation() {
        guard let session = appState.pendingRoomSession else { return }
        navigationPath.removeLast(navigationPath.count)
        navigationPath.append(session)
        appState.clearPendingRoomNavigation()
    }

    private var conversationList: some View {
        List {
            ForEach(filteredConversations) { conversation in
                switch conversation {
                case .direct(let contact):
                    NavigationLink(value: contact) {
                        ConversationRow(contact: contact, viewModel: viewModel)
                    }
                    .conversationSwipeActions(conversation: conversation, viewModel: viewModel) {
                        deleteDirectConversation(contact)
                    }
                case .channel(let channel):
                    NavigationLink(value: channel) {
                        ChannelConversationRow(channel: channel, viewModel: viewModel)
                    }
                    .conversationSwipeActions(conversation: conversation, viewModel: viewModel) {
                        deleteChannelConversation(channel)
                    }
                case .room(let session):
                    Button {
                        if session.isConnected {
                            navigationPath.append(session)
                        } else {
                            roomToAuthenticate = session  // Sheet will show automatically
                        }
                    } label: {
                        RoomConversationRow(session: session)
                    }
                    .buttonStyle(.plain)
                    .conversationSwipeActions(conversation: conversation, viewModel: viewModel) {
                        roomToDelete = session
                        showRoomDeleteAlert = true
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private func loadConversations() async {
        guard let deviceID = appState.connectedDevice?.id else { return }
        viewModel.configure(appState: appState)
        await viewModel.loadAllConversations(deviceID: deviceID)
    }

    private func handlePendingNavigation() {
        guard let contact = appState.pendingChatContact else { return }
        // Clear existing navigation and navigate to chat
        navigationPath.removeLast(navigationPath.count)
        navigationPath.append(contact)
        appState.clearPendingNavigation()
    }

    private func refreshConversations() async {
        guard let deviceID = appState.connectedDevice?.id else { return }
        await viewModel.loadAllConversations(deviceID: deviceID)
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

    private func deleteRoom(_ session: RemoteNodeSessionDTO) async {
        do {
            // Leave room (sends logout and removes session)
            try await appState.services?.roomServerService.leaveRoom(
                sessionID: session.id,
                publicKey: session.publicKey
            )

            // Delete associated contact
            try await appState.services?.contactService.removeContact(
                deviceID: session.deviceID,
                publicKey: session.publicKey
            )

            // Recalculate badge after room removed
            await appState.services?.notificationService.updateBadgeCount()

            // Refresh conversation list
            await loadConversations()
        } catch {
            logger.error("Failed to delete room: \(error)")
        }
    }

    private func deleteChannel(_ channel: ChannelDTO) async {
        guard let channelService = appState.services?.channelService else { return }

        do {
            try await channelService.clearChannel(
                deviceID: channel.deviceID,
                index: channel.index
            )
            // Recalculate badge after channel removed
            await appState.services?.notificationService.updateBadgeCount()
        } catch {
            // On failure, reload to restore the channel
            logger.error("Failed to delete channel: \(error)")
            await loadConversations()
        }
    }

    // MARK: - Hashtag Channel Handling

    private func handleHashtagTap(name: String) {
        Task {
            let normalizedName = HashtagUtilities.normalizeHashtagName(name)
            guard HashtagUtilities.isValidHashtagName(normalizedName) else {
                logger.error("Invalid hashtag name in tap: \(name, privacy: .public)")
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
                    navigationPath.append(channel)
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
            logger.error("Failed to fetch channels for hashtag lookup: \(error)")
            return nil
        }
    }
}

// MARK: - Swipe Actions

struct ConversationSwipeActionsModifier: ViewModifier {
    let conversation: Conversation
    let viewModel: ChatViewModel
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }

                Button {
                    Task {
                        await viewModel.toggleMute(conversation)
                    }
                } label: {
                    Label(
                        conversation.isMuted ? "Unmute" : "Mute",
                        systemImage: conversation.isMuted ? "bell" : "bell.slash"
                    )
                }
                .tint(.indigo)
            }
    }
}

extension View {
    func conversationSwipeActions(
        conversation: Conversation,
        viewModel: ChatViewModel,
        onDelete: @escaping () -> Void
    ) -> some View {
        modifier(ConversationSwipeActionsModifier(
            conversation: conversation,
            viewModel: viewModel,
            onDelete: onDelete
        ))
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let contact: ContactDTO
    let viewModel: ChatViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ContactAvatar(contact: contact, size: 44)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(contact.displayName)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    HStack(spacing: 4) {
                        if contact.isMuted {
                            Image(systemName: "bell.slash")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Muted")
                        }
                        if let date = contact.lastMessageDate {
                            ConversationTimestamp(date: date)
                        }
                    }
                }

                HStack {
                    // Last message preview
                    Text(viewModel.lastMessagePreview(for: contact) ?? "No messages yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    // Unread badge
                    if contact.unreadCount > 0 {
                        Text(contact.unreadCount, format: .number)
                            .font(.caption2)
                            .bold()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(contact.isMuted ? Color.secondary : Color.blue, in: .capsule)
                    }
                }
            }
            .alignmentGuide(.listRowSeparatorLeading) { d in
                d[.leading]
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Contact Avatar

struct ContactAvatar: View {
    let contact: ContactDTO
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(avatarColor)

            Text(initials)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }

    private var initials: String {
        let name = contact.displayName
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private var avatarColor: Color {
        // Generate a consistent color based on the public key
        let hash = contact.publicKey.prefix(4).reduce(0) { $0 ^ Int($1) }
        let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .cyan, .indigo, .mint]
        return colors[abs(hash) % colors.count]
    }
}

// MARK: - New Chat View

struct NewChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    let viewModel: ChatViewModel
    /// Callback invoked when user selects a contact. Caller should dismiss the sheet and navigate.
    let onSelectContact: (ContactDTO) -> Void

    @State private var contacts: [ContactDTO] = []
    @State private var searchText = ""
    @State private var isLoading = false

    private var filteredContacts: [ContactDTO] {
        // Filter out blocked contacts and repeaters (repeaters are infrastructure, not chat participants)
        let eligible = contacts.filter { !$0.isBlocked && $0.type != .repeater }
        if searchText.isEmpty {
            return eligible
        }
        return eligible.filter { contact in
            contact.displayName.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if contacts.isEmpty {
                    ContentUnavailableView(
                        "No Contacts",
                        systemImage: "person.2",
                        description: Text("Contacts will appear when discovered")
                    )
                } else {
                    List(filteredContacts) { contact in
                        Button {
                            onSelectContact(contact)
                        } label: {
                            HStack(spacing: 12) {
                                ContactAvatar(contact: contact, size: 40)

                                VStack(alignment: .leading) {
                                    Text(contact.displayName)
                                        .font(.headline)

                                    Text(contactTypeLabel(for: contact))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("New Chat")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search contacts")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadContacts()
            }
        }
    }

    private func loadContacts() async {
        guard let deviceID = appState.connectedDevice?.id else { return }

        isLoading = true
        do {
            contacts = try await appState.services?.dataStore.fetchContacts(deviceID: deviceID) ?? []
        } catch {
            // Silently handle error
        }
        isLoading = false
    }

    private func contactTypeLabel(for contact: ContactDTO) -> String {
        switch contact.type {
        case .chat:
            return contact.isFloodRouted ? "Flood routing" : "Direct"
        case .repeater:
            return "Repeater"
        case .room:
            return "Room"
        }
    }
}

// MARK: - Channel Conversation Row

struct ChannelConversationRow: View {
    let channel: ChannelDTO
    let viewModel: ChatViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Channel avatar
            ChannelAvatar(channel: channel, size: 44)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(channel.name.isEmpty ? "Channel \(channel.index)" : channel.name)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    HStack(spacing: 4) {
                        if channel.isMuted {
                            Image(systemName: "bell.slash")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Muted")
                        }
                        if let date = channel.lastMessageDate {
                            ConversationTimestamp(date: date)
                        }
                    }
                }

                HStack {
                    // Last message preview
                    Text(viewModel.lastMessagePreview(for: channel) ?? "No messages yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    // Unread badge
                    if channel.unreadCount > 0 {
                        Text(channel.unreadCount, format: .number)
                            .font(.caption2)
                            .bold()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(channel.isMuted ? Color.secondary : Color.blue, in: .capsule)
                    }
                }
            }
            .alignmentGuide(.listRowSeparatorLeading) { d in
                d[.leading]
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Channel Avatar

struct ChannelAvatar: View {
    let channel: ChannelDTO
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(avatarColor)

            Image(systemName: channel.isPublicChannel ? "globe" : "number")
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }

    private var avatarColor: Color {
        // Public channel is always green, others get colors based on index
        if channel.isPublicChannel {
            return .green
        }
        let colors: [Color] = [.blue, .orange, .purple, .pink, .cyan, .indigo, .mint]
        return colors[Int(channel.index - 1) % colors.count]
    }
}

// MARK: - Room Conversation Row

struct RoomConversationRow: View {
    let session: RemoteNodeSessionDTO

    var body: some View {
        HStack(spacing: 12) {
            // Room avatar
            NodeAvatar(publicKey: session.publicKey, role: .roomServer, size: 44)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(session.name)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    HStack(spacing: 4) {
                        if session.isMuted {
                            Image(systemName: "bell.slash")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Muted")
                        }
                        if let date = session.lastConnectedDate {
                            ConversationTimestamp(date: date)
                        }
                    }
                }

                HStack {
                    // Status indicator
                    if session.isConnected {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Text("Tap to reconnect")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Unread badge
                    if session.unreadCount > 0 {
                        Text(session.unreadCount, format: .number)
                            .font(.caption2)
                            .bold()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(session.isMuted ? Color.secondary : Color.blue, in: .capsule)
                    }
                }
            }
            .alignmentGuide(.listRowSeparatorLeading) { d in
                d[.leading]
            }

            // Disclosure chevron to match NavigationLink appearance
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }
}

// MARK: - Conversation Timestamp

/// Formats timestamps for the chat list with absolute time display
/// - Today: Time only (e.g., "1:14 PM")
/// - Yesterday: "Yesterday"
/// - Older: Date only (e.g., "Nov 15")
struct ConversationTimestamp: View {
    let date: Date
    var font: Font = .caption

    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(formattedDate(relativeTo: context.date))
                .font(font)
                .foregroundStyle(.secondary)
        }
    }

    private func formattedDate(relativeTo now: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            // Today: show time only (e.g., "1:14 PM")
            return date.formatted(date: .omitted, time: .shortened)
        } else if calendar.isDateInYesterday(date) {
            // Yesterday: just show "Yesterday"
            return "Yesterday"
        } else {
            // Older: show date only (e.g., "Nov 15")
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}

// MARK: - Room Authentication Sheet

/// Helper sheet for re-authenticating to a disconnected room from the chat list
struct RoomAuthenticationSheet: View {
    @Environment(AppState.self) private var appState
    let session: RemoteNodeSessionDTO
    let onSuccess: (RemoteNodeSessionDTO) -> Void

    @State private var contact: ContactDTO?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let contact {
                NodeAuthenticationSheet(
                    contact: contact,
                    role: .roomServer,
                    hideNodeDetails: true,
                    onSuccess: onSuccess
                )
            } else {
                ContentUnavailableView(
                    "Room Not Found",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Could not find the room contact")
                )
            }
        }
        .task {
            // Fetch the contact associated with this room session
            contact = try? await appState.services?.dataStore.fetchContact(
                deviceID: session.deviceID,
                publicKey: session.publicKey
            )
            isLoading = false
        }
    }
}

#Preview {
    ChatsListView()
        .environment(AppState())
}

