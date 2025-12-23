import SwiftUI
import PocketMeshServices
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh", category: "ChatsListView")

/// List of active conversations
struct ChatsListView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = ChatViewModel()
    @State private var searchText = ""
    @State private var showingNewChat = false
    @State private var showingChannelOptions = false
    @State private var navigationPath = NavigationPath()
    @State private var roomToAuthenticate: RemoteNodeSessionDTO?
    @State private var roomToDelete: RemoteNodeSessionDTO?
    @State private var showRoomDeleteAlert = false
    @State private var tabBarVisibility: Visibility = .visible

    private var filteredConversations: [Conversation] {
        let conversations = viewModel.allConversations
        if searchText.isEmpty {
            return conversations
        }
        return conversations.filter { conversation in
            conversation.displayName.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if viewModel.isLoading && viewModel.allConversations.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.allConversations.isEmpty {
                    ContentUnavailableView(
                        "No Conversations",
                        systemImage: "message",
                        description: Text("Start a conversation from Contacts")
                    )
                } else {
                    conversationList
                }
            }
            .navigationTitle("Chats")
            .searchable(text: $searchText, prompt: "Search conversations")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    BLEStatusIndicatorView()
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
            .sheet(isPresented: $showingNewChat) {
                NewChatView(viewModel: viewModel)
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
                handlePendingNavigation()
            }
            .navigationDestination(for: ContactDTO.self) { contact in
                ChatView(contact: contact, parentViewModel: viewModel)
                    .onAppear { tabBarVisibility = .hidden }
            }
            .navigationDestination(for: ChannelDTO.self) { channel in
                ChannelChatView(channel: channel, parentViewModel: viewModel)
                    .onAppear { tabBarVisibility = .hidden }
            }
            .navigationDestination(for: RemoteNodeSessionDTO.self) { session in
                RoomConversationView(session: session)
                    .onAppear { tabBarVisibility = .hidden }
            }
            .onChange(of: appState.pendingChatContact) { _, _ in
                handlePendingNavigation()
            }
            // Runs on initial appearance AND when conversationsVersion changes
            .task(id: appState.conversationsVersion) {
                await loadConversations()
            }
            .onChange(of: appState.pendingRoomSession) { _, _ in
                handlePendingRoomNavigation()
            }
            .sheet(item: $roomToAuthenticate) { session in
                RoomAuthenticationSheet(session: session) { authenticatedSession in
                    roomToAuthenticate = nil
                    navigationPath.append(authenticatedSession)
                }
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
            .toolbarVisibility(tabBarVisibility, for: .tabBar)
        }
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
                    .onAppear { tabBarVisibility = .visible }
                case .channel(let channel):
                    NavigationLink(value: channel) {
                        ChannelConversationRow(channel: channel, viewModel: viewModel)
                    }
                    .onAppear { tabBarVisibility = .visible }
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
                    .onAppear { tabBarVisibility = .visible }
                }
            }
            .onDelete(perform: deleteConversations)
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

    private func deleteConversations(at offsets: IndexSet) {
        let conversationsToDelete = offsets.map { filteredConversations[$0] }

        for conversation in conversationsToDelete {
            switch conversation {
            case .direct(let contact):
                Task {
                    try? await viewModel.deleteConversation(for: contact)
                }
            case .room(let session):
                // Show confirmation alert for room deletion
                roomToDelete = session
                showRoomDeleteAlert = true
            case .channel:
                // Channel deletion is handled via ChannelInfoSheet, not swipe-to-delete
                break
            }
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

            // Refresh conversation list
            await loadConversations()
        } catch {
            logger.error("Failed to delete room: \(error)")
        }
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

                    if let date = contact.lastMessageDate {
                        ConversationTimestamp(date: date)
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
                            .background(.blue, in: .capsule)
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
                        NavigationLink {
                            ChatView(contact: contact, parentViewModel: viewModel)
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
                            }
                        }
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

                    if let date = channel.lastMessageDate {
                        ConversationTimestamp(date: date)
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
                            .background(.green, in: .capsule)
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

                    if let date = session.lastConnectedDate {
                        ConversationTimestamp(date: date)
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
                            .background(.orange, in: .capsule)
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

    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(formattedDate(relativeTo: context.date))
                .font(.caption)
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
