import SwiftUI
import PocketMeshServices

/// List of all contacts discovered on the mesh network
struct ContactsListView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var viewModel = ContactsViewModel()
    @State private var navigationPath = NavigationPath()
    @State private var selectedContact: ContactDTO?
    @State private var searchText = ""
    @State private var showFavoritesOnly = false
    @State private var showDiscovery = false
    @State private var syncSuccessTrigger = false
    @State private var showShareMyContact = false
    @State private var showAddContact = false

    private var filteredContacts: [ContactDTO] {
        viewModel.filteredContacts(searchText: searchText, showFavoritesOnly: showFavoritesOnly)
    }

    private var shouldUseSplitView: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        if shouldUseSplitView {
            NavigationSplitView {
                NavigationStack {
                    contactsSidebarContent
                        .navigationDestination(isPresented: $showDiscovery) {
                            DiscoveryView()
                        }
                }
            } detail: {
                NavigationStack {
                    if let selectedContact {
                        ContactDetailView(contact: selectedContact)
                            .id(selectedContact.id)
                    } else {
                        ContentUnavailableView("Select a contact", systemImage: "person.2")
                    }
                }
            }
        } else {
            NavigationStack(path: $navigationPath) {
                contactsSidebarContent
                    .navigationDestination(isPresented: $showDiscovery) {
                        DiscoveryView()
                    }
                    .navigationDestination(for: ContactDTO.self) { contact in
                        ContactDetailView(contact: contact)
                    }
            }
        }
    }

    private var contactsSidebarContent: some View {
        Group {
            if viewModel.isLoading && viewModel.contacts.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.contacts.isEmpty {
                emptyView
            } else {
                if shouldUseSplitView {
                    contactsSplitList
                } else {
                    contactsList
                }
            }
        }
        .navigationTitle("Contacts")
        .searchable(text: $searchText, prompt: "Search contacts")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                BLEStatusIndicatorView()
            }
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
                        showShareMyContact = true
                    } label: {
                        Label("Share My Contact", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        showAddContact = true
                    } label: {
                        Label("Add Contact", systemImage: "plus")
                    }

                    Divider()

                    NavigationLink {
                        DiscoveryView()
                    } label: {
                        Label("Discovery", systemImage: "antenna.radiowaves.left.and.right")
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
        .refreshable {
            await syncContacts()
        }
        .sensoryFeedback(.success, trigger: syncSuccessTrigger)
        .task {
            viewModel.configure(appState: appState)
            await loadContacts()
        }
        .onChange(of: appState.servicesVersion) { _, _ in
            // Services changed (device switch, reconnect) - reload contacts
            Task {
                await loadContacts()
            }
        }
        .onChange(of: appState.contactsVersion) { _, _ in
            Task {
                await loadContacts()
            }
        }
        .onChange(of: appState.pendingDiscoveryNavigation) { _, shouldNavigate in
            if shouldNavigate {
                showDiscovery = true
                appState.clearPendingDiscoveryNavigation()
            }
        }
        .onChange(of: appState.pendingContactDetail) { _, contact in
            guard let contact else { return }

            if shouldUseSplitView {
                selectedContact = contact
            } else {
                navigationPath.removeLast(navigationPath.count)
                navigationPath.append(contact)
            }

            appState.clearPendingContactDetailNavigation()
        }
        .sheet(isPresented: $showShareMyContact) {
            if let device = appState.connectedDevice {
                ContactQRShareSheet(
                    contactName: device.nodeName,
                    publicKey: device.publicKey,
                    contactType: .chat
                )
            }
        }
        .sheet(isPresented: $showAddContact) {
            AddContactSheet()
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
            ForEach(filteredContacts) { contact in
                contactRow(contact)
            }
        }
        .listStyle(.plain)
    }

    private var contactsSplitList: some View {
        List(selection: $selectedContact) {
            ForEach(filteredContacts) { contact in
                contactSplitRow(contact)
                    .tag(contact)
            }
        }
        .listStyle(.plain)
    }

    private func contactRow(_ contact: ContactDTO) -> some View {
        NavigationLink(value: contact) {
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

    private func contactSplitRow(_ contact: ContactDTO) -> some View {
        ContactRowView(contact: contact)
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

    // MARK: - Actions

    private func loadContacts() async {
        guard let deviceID = appState.connectedDevice?.id else { return }
        viewModel.configure(appState: appState)
        await viewModel.loadContacts(deviceID: deviceID)
    }

    private func syncContacts() async {
        guard let deviceID = appState.connectedDevice?.id else { return }
        await viewModel.syncContacts(deviceID: deviceID)
        syncSuccessTrigger.toggle()
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
                    Text(contactTypeLabel)
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
            .alignmentGuide(.listRowSeparatorLeading) { d in
                d[.leading]
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
