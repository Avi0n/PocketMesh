import SwiftUI
import PocketMeshKit

/// List of all contacts discovered on the mesh network
struct ContactsListView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = ContactsViewModel()
    @State private var searchText = ""
    @State private var showFavoritesOnly = false

    private var filteredContacts: [ContactDTO] {
        viewModel.filteredContacts(searchText: searchText, showFavoritesOnly: showFavoritesOnly)
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading && viewModel.contacts.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.contacts.isEmpty {
                    emptyView
                } else {
                    contactsList
                }
            }
            .navigationTitle("Contacts")
            .searchable(text: $searchText, prompt: "Search contacts")
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button {
                            showFavoritesOnly.toggle()
                        } label: {
                            Label(
                                showFavoritesOnly ? "Show All" : "Show Favorites",
                                systemImage: showFavoritesOnly ? "star.slash" : "star.fill"
                            )
                        }

                        Divider()

                        Button {
                            Task {
                                await syncContacts()
                            }
                        } label: {
                            Label("Sync Contacts", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(viewModel.isSyncing)
                    } label: {
                        Label("Options", systemImage: "ellipsis.circle")
                    }
                }
            }
            .overlay {
                if viewModel.isSyncing {
                    syncOverlay
                }
            }
            .refreshable {
                await syncContacts()
            }
            .task {
                viewModel.configure(appState: appState)
                await loadContacts()
            }
            .onChange(of: appState.connectionState) { oldState, newState in
                // Refresh when device reconnects (state changes to .ready)
                if newState == .ready && oldState != .ready {
                    Task {
                        await loadContacts()
                    }
                }
            }
        }
    }

    // MARK: - Views

    private var emptyView: some View {
        ContentUnavailableView(
            "No Contacts",
            systemImage: "person.2",
            description: Text("Contacts will appear when discovered on the mesh network. Pull to refresh or tap Sync.")
        )
    }

    private var contactsList: some View {
        List {
            // Favorites section
            let favorites = filteredContacts.filter(\.isFavorite)
            if !favorites.isEmpty && !showFavoritesOnly {
                Section {
                    ForEach(favorites) { contact in
                        contactRow(contact)
                    }
                } header: {
                    Label("Favorites", systemImage: "star.fill")
                }
            }

            // All contacts section
            let nonFavorites = showFavoritesOnly ? favorites : filteredContacts.filter { !$0.isFavorite }
            if !nonFavorites.isEmpty {
                Section {
                    ForEach(showFavoritesOnly ? favorites : nonFavorites) { contact in
                        contactRow(contact)
                    }
                } header: {
                    if !showFavoritesOnly && !favorites.isEmpty {
                        Text("All Contacts")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func contactRow(_ contact: ContactDTO) -> some View {
        NavigationLink {
            ContactDetailView(contact: contact)
        } label: {
            ContactRowView(contact: contact)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                Task {
                    await viewModel.deleteContact(contact)
                }
            } label: {
                Label("Delete", systemImage: "trash")
            }

            Button {
                Task {
                    await viewModel.toggleBlocked(contact: contact)
                }
            } label: {
                Label(
                    contact.isBlocked ? "Unblock" : "Block",
                    systemImage: contact.isBlocked ? "hand.raised.slash" : "hand.raised"
                )
            }
            .tint(.orange)
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                Task {
                    await viewModel.toggleFavorite(contact: contact)
                }
            } label: {
                Label(
                    contact.isFavorite ? "Unfavorite" : "Favorite",
                    systemImage: contact.isFavorite ? "star.slash" : "star.fill"
                )
            }
            .tint(.yellow)
        }
    }

    private var syncOverlay: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Syncing Contacts...")
                .font(.headline)

            if let progress = viewModel.syncProgress {
                Text("\(progress.0) of \(progress.1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ProgressView(value: Double(progress.0), total: Double(max(progress.1, 1)))
                    .progressViewStyle(.linear)
                    .frame(width: 200)
            }
        }
        .padding(32)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }

    // MARK: - Actions

    private func loadContacts() async {
        guard let deviceID = appState.connectedDevice?.id else { return }
        await viewModel.loadContacts(deviceID: deviceID)
    }

    private func syncContacts() async {
        guard let deviceID = appState.connectedDevice?.id else { return }
        await viewModel.syncContacts(deviceID: deviceID)
    }
}

// MARK: - Contact Row View

struct ContactRowView: View {
    let contact: ContactDTO

    var body: some View {
        HStack(spacing: 12) {
            ContactAvatar(contact: contact, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(contact.displayName)
                        .font(.body)
                        .fontWeight(.medium)

                    if contact.isBlocked {
                        Image(systemName: "hand.raised.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                HStack(spacing: 8) {
                    // Contact type
                    Label(contactTypeLabel, systemImage: contactTypeIcon)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Location indicator
                    if contact.hasLocation {
                        Label("Location", systemImage: "location.fill")
                            .labelStyle(.iconOnly)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }

            Spacer()

            // Route indicator
            VStack(alignment: .trailing, spacing: 2) {
                if contact.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }

                Text(routeLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var contactTypeLabel: String {
        switch contact.type {
        case .chat: return "Chat"
        case .repeater: return "Repeater"
        case .room: return "Room"
        }
    }

    private var contactTypeIcon: String {
        switch contact.type {
        case .chat: return "person.fill"
        case .repeater: return "antenna.radiowaves.left.and.right"
        case .room: return "door.left.hand.open"
        }
    }

    private var routeLabel: String {
        if contact.isFloodRouted {
            return "Flood"
        } else if contact.outPathLength == 0 {
            return "Direct"
        } else if contact.outPathLength > 0 {
            return "\(contact.outPathLength) hops"
        }
        return ""
    }
}

#Preview {
    ContactsListView()
        .environment(AppState())
}
