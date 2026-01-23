import SwiftUI
import PocketMeshServices
import CoreLocation
import OSLog

private let nodesListLogger = Logger(subsystem: "com.pocketmesh", category: "NodesListView")

/// List of all contacts discovered on the mesh network
struct ContactsListView: View {
    @Environment(\.appState) private var appState
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
    @State private var showLocationDeniedAlert = false
    @State private var showOfflineRefreshAlert = false

    private var filteredContacts: [ContactDTO] {
        // Fall back to lastHeard sort when distance is selected but location unavailable
        let effectiveSortOrder = (sortOrder == .distance && appState.locationService.currentLocation == nil)
            ? .lastHeard
            : sortOrder

        return viewModel.filteredContacts(
            searchText: searchText,
            segment: selectedSegment,
            sortOrder: effectiveSortOrder,
            userLocation: appState.locationService.currentLocation
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
            if !viewModel.hasLoadedOnce {
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
        .searchable(text: $searchText, prompt: "Search nodes")
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
                        Label("Discover", systemImage: "antenna.radiowaves.left.and.right")
                    }

                    Divider()

                    Button {
                        Task {
                            if appState.connectionState != .ready {
                                showOfflineRefreshAlert = true
                            } else {
                                await syncContacts()
                            }
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
            if appState.connectionState != .ready {
                showOfflineRefreshAlert = true
            } else {
                await syncContacts()
            }
        }
        .alert("Cannot Refresh", isPresented: $showOfflineRefreshAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Connect to your device to sync contacts.")
        }
        .sensoryFeedback(.success, trigger: syncSuccessTrigger)
        .task {
            nodesListLogger.info("NodesListView: task started, services=\(appState.services != nil)")
            viewModel.configure(appState: appState)
            await loadContacts()
            nodesListLogger.info("NodesListView: loaded, contacts=\(viewModel.contacts.count)")
            announceOfflineStateIfNeeded()

            // Request location for distance display (only if already authorized)
            if appState.locationService.isAuthorized {
                appState.locationService.requestLocation()
            }
        }
        .task(id: sortOrder) {
            if sortOrder == .distance {
                if appState.locationService.isAuthorized {
                    appState.locationService.requestLocation()
                } else if appState.locationService.isLocationDenied {
                    showLocationDeniedAlert = true
                } else {
                    appState.locationService.requestPermissionIfNeeded()
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
        .onChange(of: appState.locationService.authorizationStatus) { _, status in
            if sortOrder == .distance {
                switch status {
                case .authorizedWhenInUse, .authorizedAlways:
                    appState.locationService.requestLocation()
                case .denied, .restricted:
                    showLocationDeniedAlert = true
                default:
                    break
                }
            }
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
        .alert("Location Unavailable", isPresented: $showLocationDeniedAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Distance sorting requires location access.")
        }
        .alert("Error", isPresented: showErrorBinding) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "An error occurred")
        }
    }

    private var showErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
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
            .listSectionSeparator(.hidden)

            ForEach(Array(filteredContacts.enumerated()), id: \.element.id) { index, contact in
                contactRow(contact, index: index)
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
            .listSectionSeparator(.hidden)

            ForEach(Array(filteredContacts.enumerated()), id: \.element.id) { index, contact in
                contactSplitRow(contact, index: index)
                    .tag(contact)
            }
        }
        .listStyle(.plain)
    }

    private func contactRow(_ contact: ContactDTO, index: Int) -> some View {
        NavigationLink(value: contact) {
            ContactRowView(
                contact: contact,
                showTypeLabel: isSearching,
                userLocation: appState.locationService.currentLocation,
                index: index
            )
        }
        .contactSwipeActions(contact: contact, viewModel: viewModel)
    }

    private func contactSplitRow(_ contact: ContactDTO, index: Int) -> some View {
        ContactRowView(
            contact: contact,
            showTypeLabel: isSearching,
            userLocation: appState.locationService.currentLocation,
            index: index
        )
        .contactSwipeActions(contact: contact, viewModel: viewModel)
    }

    // MARK: - Actions

    private func loadContacts() async {
        guard let deviceID = appState.currentDeviceID else { return }
        viewModel.configure(appState: appState)
        await viewModel.loadContacts(deviceID: deviceID)
    }

    private func announceOfflineStateIfNeeded() {
        guard UIAccessibility.isVoiceOverRunning,
              appState.connectionState == .disconnected,
              appState.currentDeviceID != nil else { return }

        UIAccessibility.post(
            notification: .announcement,
            argument: "Viewing cached contacts. Connect to device for updates."
        )
    }

    private func syncContacts() async {
        guard let deviceID = appState.currentDeviceID else { return }
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
    let userLocation: CLLocation?
    let index: Int

    init(contact: ContactDTO, showTypeLabel: Bool = false, userLocation: CLLocation? = nil, index: Int = 0) {
        self.contact = contact
        self.showTypeLabel = showTypeLabel
        self.userLocation = userLocation
        self.index = index
    }

    var body: some View {
        HStack(spacing: 12) {
            avatarView

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(contact.displayName)
                        .font(.body)
                        .fontWeight(.medium)

                    if contact.isBlocked {
                        Image(systemName: "hand.raised.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Blocked")
                    }

                    Spacer()

                    if contact.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("Favorite")
                    }

                    RelativeTimestampText(timestamp: contact.lastAdvertTimestamp)
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

                    // Location indicator with optional distance
                    if contact.hasLocation {
                        Label("Location", systemImage: "location.fill")
                            .labelStyle(.iconOnly)
                            .font(.caption)
                            .foregroundStyle(.green)

                        if let distance = distanceToContact {
                            Text(distance)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .alignmentGuide(.listRowSeparatorLeading) { d in
                d[.leading]
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var avatarView: some View {
        switch contact.type {
        case .chat:
            ContactAvatar(contact: contact, size: 44)
        case .repeater:
            NodeAvatar(publicKey: contact.publicKey, role: .repeater, size: 44, index: index)
        case .room:
            NodeAvatar(publicKey: contact.publicKey, role: .roomServer, size: 44)
        }
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

    private var distanceToContact: String? {
        guard let userLocation, contact.hasLocation else { return nil }

        let contactLocation = CLLocation(
            latitude: contact.latitude,
            longitude: contact.longitude
        )
        let meters = userLocation.distance(from: contactLocation)
        let measurement = Measurement(value: meters, unit: UnitLength.meters)

        return measurement.formatted(.measurement(
            width: .abbreviated,
            usage: .road
        )) + " away"
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
        .environment(\.appState, AppState())
}
