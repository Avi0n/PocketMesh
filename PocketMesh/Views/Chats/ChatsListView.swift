import SwiftUI
import PocketMeshKit

/// List of active conversations
struct ChatsListView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = ChatViewModel()
    @State private var searchText = ""
    @State private var showingNewChat = false
    @State private var navigationPath = NavigationPath()

    private var filteredConversations: [ContactDTO] {
        if searchText.isEmpty {
            return viewModel.conversations
        }
        return viewModel.conversations.filter { contact in
            contact.displayName.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if viewModel.isLoading && viewModel.conversations.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.conversations.isEmpty {
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
                ToolbarItem(placement: .automatic) {
                    Button {
                        showingNewChat = true
                    } label: {
                        Label("New Chat", systemImage: "square.and.pencil")
                    }
                }
            }
            .sheet(isPresented: $showingNewChat) {
                NewChatView(viewModel: viewModel)
            }
            .refreshable {
                await refreshConversations()
            }
            .task {
                viewModel.configure(appState: appState)
                await loadConversations()
            }
            .navigationDestination(for: ContactDTO.self) { contact in
                ChatView(contact: contact, parentViewModel: viewModel)
            }
            .onChange(of: appState.pendingChatContact) { _, newContact in
                if let contact = newContact {
                    // Clear existing navigation and navigate to chat
                    navigationPath.removeLast(navigationPath.count)
                    navigationPath.append(contact)
                    appState.clearPendingNavigation()
                }
            }
            .onChange(of: appState.messageEventBroadcaster.newMessageCount) { _, _ in
                Task {
                    await loadConversations()
                }
            }
        }
    }

    private var conversationList: some View {
        List {
            ForEach(filteredConversations) { contact in
                NavigationLink {
                    ChatView(contact: contact, parentViewModel: viewModel)
                } label: {
                    ConversationRow(contact: contact, viewModel: viewModel)
                }
            }
            .onDelete(perform: deleteConversations)
        }
        .listStyle(.plain)
    }

    private func loadConversations() async {
        guard let deviceID = appState.connectedDevice?.id else { return }
        await viewModel.loadConversations(deviceID: deviceID)
        await viewModel.loadLastMessagePreviews()
    }

    private func refreshConversations() async {
        guard let deviceID = appState.connectedDevice?.id else { return }
        await viewModel.loadConversations(deviceID: deviceID)
        await viewModel.loadLastMessagePreviews()
    }

    private func deleteConversations(at offsets: IndexSet) {
        let contactsToDelete = offsets.map { filteredConversations[$0] }
        Task {
            for contact in contactsToDelete {
                try? await viewModel.deleteConversation(for: contact)
            }
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
            ContactAvatar(contact: contact, size: 50)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(contact.displayName)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    if let date = contact.lastMessageDate {
                        Text(date, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

            // Contact type indicator
            if contact.type == .repeater {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: size * 0.25))
                    .foregroundStyle(.white)
                    .padding(4)
                    .background(.blue, in: .circle)
                    .offset(x: size * 0.35, y: size * 0.35)
            }
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
        let nonBlocked = contacts.filter { !$0.isBlocked }
        if searchText.isEmpty {
            return nonBlocked
        }
        return nonBlocked.filter { contact in
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
            contacts = try await appState.dataStore.fetchContacts(deviceID: deviceID)
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

#Preview {
    ChatsListView()
        .environment(AppState())
}
