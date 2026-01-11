import SwiftUI
import PocketMeshServices
import CoreLocation
import OSLog

private let nodesListLogger = Logger(subsystem: "com.pocketmesh", category: "NodesListView")

/// List of all contacts discovered on the mesh network
struct ContactsListView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var viewModel = ContactsViewModel()
    @State private var navigationPath = NavigationPath()
    @State private var selectedContact: ContactDTO?
    @State private var searchText = ""
    @State private var selectedSegment: NodeSegment = .contacts
    @AppStorage("nodesSortOrder") private var sortOrder: NodeSortOrder = .lastHeard
    @State private var showDiscovery = false
    @State private var syncSuccessTrigger = false
    @State private var showShareMyContact = false
    @State private var showAddContact = false
    @State private var userLocation: CLLocation?

    private let locationManager = CLLocationManager()

    private var filteredContacts: [ContactDTO] {
        viewModel.filteredContacts(
            searchText: searchText,
            segment: selectedSegment,
            sortOrder: sortOrder,
            userLocation: userLocation
        )
    }

    private var isSearching: Bool {
        !searchText.isEmpty
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
                        ContentUnavailableView("Select a node", systemImage: "flipphone")
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
            } else if filteredContacts.isEmpty && !isSearching {
                emptyView
            } else if filteredContacts.isEmpty && isSearching {
                searchEmptyView
            } else {
                if shouldUseSplitView {
                    contactsSplitList
                } else {
                    contactsList
                }
            }
        }
        .navigationTitle("Nodes")
        .searchable(text: $searchText, prompt: "Search contacts")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                BLEStatusIndicatorView()
            }

            ToolbarItem(placement: .automatic) {
                Menu {
                    ForEach(NodeSortOrder.allCases, id: \.self) { order in
                        Button {
                            sortOrder = order
                        } label: {
                            if sortOrder == order {
                                Label(order.rawValue, systemImage: "checkmark")
                            } else {
                                Text(order.rawValue)
                            }
                        }
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
            }

            ToolbarItem(placement: .automatic) {
                Menu {
                    NavigationLink {
                        BlockedContactsView()
                    } label: {
                        Label("Blocked Contacts", systemImage: "hand.raised.fill")
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
                        Label("Sync Nodes", systemImage: "arrow.triangle.2.circlepath")
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
            nodesListLogger.info("NodesListView: task started, services=\(appState.services != nil)")
            viewModel.configure(appState: appState)
            await loadContacts()
            nodesListLogger.info("NodesListView: loaded, contacts=\(viewModel.contacts.count)")
        }
        .task(id: sortOrder) {
            if sortOrder == .distance {
                if let location = locationManager.location {
                    userLocation = location
                } else {
                    nodesListLogger.debug("Distance sorting requested but device location unavailable")
                }
            }
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
        VStack {
            NodeSegmentPicker(selection: $selectedSegment, isSearching: isSearching)

            Spacer()

            switch selectedSegment {
            case .favorites:
                ContentUnavailableView(
                    "No Favorites Yet",
                    systemImage: "star",
                    description: Text("Swipe right on any node to add it to your favorites.")
                )
            case .contacts:
                ContentUnavailableView(
                    "No Contacts",
                    systemImage: "person.2",
                    description: Text("Contacts appear when discovered on the mesh network. If auto-add contacts is off, check Discovery in the top right menu.")
                )
            case .network:
                ContentUnavailableView(
                    "No Network Nodes",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text("Repeaters and room servers will appear when discovered on the mesh.")
                )
            }

            Spacer()
        }
    }

    private var searchEmptyView: some View {
        VStack {
            NodeSegmentPicker(selection: $selectedSegment, isSearching: isSearching)

            Spacer()

            ContentUnavailableView(
                "No Results",
                systemImage: "magnifyingglass",
                description: Text("No nodes match '\(searchText)'")
            )

            Spacer()
        }
    }

    private var contactsList: some View {
        List {
            Section {
                NodeSegmentPicker(selection: $selectedSegment, isSearching: isSearching)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            ForEach(filteredContacts) { contact in
                contactRow(contact)
            }
        }
        .listStyle(.plain)
    }

    private var contactsSplitList: some View {
        List(selection: $selectedContact) {
            Section {
                NodeSegmentPicker(selection: $selectedSegment, isSearching: isSearching)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            ForEach(filteredContacts) { contact in
                contactSplitRow(contact)
                    .tag(contact)
            }
        }
        .listStyle(.plain)
    }

    private func contactRow(_ contact: ContactDTO) -> some View {
        NavigationLink(value: contact) {
            ContactRowView(contact: contact, showTypeLabel: isSearching)
        }
        .contactSwipeActions(contact: contact, viewModel: viewModel)
    }

    private func contactSplitRow(_ contact: ContactDTO) -> some View {
        ContactRowView(contact: contact, showTypeLabel: isSearching)
            .contactSwipeActions(contact: contact, viewModel: viewModel)
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

// MARK: - Node Segment Picker

struct NodeSegmentPicker: View {
    @Binding var selection: NodeSegment
    let isSearching: Bool

    var body: some View {
        Picker("Segment", selection: $selection) {
            ForEach(NodeSegment.allCases, id: \.self) { segment in
                Text(segment.rawValue).tag(segment)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .opacity(isSearching ? 0.5 : 1.0)
        .disabled(isSearching)
    }
}

// MARK: - Contact Row View

struct ContactRowView: View {
    let contact: ContactDTO
    let showTypeLabel: Bool

    init(contact: ContactDTO, showTypeLabel: Bool = false) {
        self.contact = contact
        self.showTypeLabel = showTypeLabel
    }

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
                            .accessibilityLabel("Blocked")
                    }
                }

                HStack(spacing: 8) {
                    // Show type label only in search results
                    if showTypeLabel {
                        Text(contactTypeLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Route indicator
                    Text(routeLabel)
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

            VStack(alignment: .trailing, spacing: 2) {
                if contact.isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                }

                RelativeTimestampText(timestamp: contact.lastAdvertTimestamp)
            }
        }
        .padding(.vertical, 4)
    }

    private var contactTypeLabel: String {
        switch contact.type {
        case .chat: return "Contact"
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

// MARK: - Contact Swipe Actions

private struct ContactSwipeActionsModifier: ViewModifier {
    let contact: ContactDTO
    let viewModel: ContactsViewModel

    func body(content: Content) -> some View {
        content
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
}

private extension View {
    func contactSwipeActions(contact: ContactDTO, viewModel: ContactsViewModel) -> some View {
        modifier(ContactSwipeActionsModifier(contact: contact, viewModel: viewModel))
    }
}

#Preview {
    ContactsListView()
        .environment(AppState())
}
