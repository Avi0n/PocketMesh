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

    private var searchPrompt: String {
        let count = viewModel.contacts.count
        if count > 0 {
            return L10n.Contacts.Contacts.List.searchPromptWithCount(count)
        }
        return L10n.Contacts.Contacts.List.searchPrompt
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
                        ContentUnavailableView(L10n.Contacts.Contacts.List.selectNode, systemImage: "flipphone")
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
        .navigationTitle(L10n.Contacts.Contacts.List.title)
        .searchable(text: $searchText, prompt: searchPrompt)
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
                                Label(order.localizedTitle, systemImage: "checkmark")
                            } else {
                                Text(order.localizedTitle)
                            }
                        }
                    }
                } label: {
                    Label(L10n.Contacts.Contacts.List.sort, systemImage: "arrow.up.arrow.down")
                }
            }

            ToolbarItem(placement: .automatic) {
                Menu {
                    NavigationLink {
                        BlockedContactsView()
                    } label: {
                        Label(L10n.Contacts.Contacts.List.blockedContacts, systemImage: "hand.raised.fill")
                    }

                    Divider()

                    Button {
                        showShareMyContact = true
                    } label: {
                        Label(L10n.Contacts.Contacts.List.shareMyContact, systemImage: "square.and.arrow.up")
                    }

                    Button {
                        showAddContact = true
                    } label: {
                        Label(L10n.Contacts.Contacts.List.addContact, systemImage: "plus")
                    }

                    Divider()

                    NavigationLink {
                        DiscoveryView()
                    } label: {
                        Label(L10n.Contacts.Contacts.List.discover, systemImage: "antenna.radiowaves.left.and.right")
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
                        Label(L10n.Contacts.Contacts.List.syncNodes, systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(viewModel.isSyncing)
                } label: {
                    Label(L10n.Contacts.Contacts.List.options, systemImage: "ellipsis.circle")
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
        .alert(L10n.Contacts.Contacts.List.cannotRefresh, isPresented: $showOfflineRefreshAlert) {
            Button(L10n.Contacts.Contacts.Common.ok, role: .cancel) { }
        } message: {
            Text(L10n.Contacts.Contacts.List.connectToSync)
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
        .alert(L10n.Contacts.Contacts.List.locationUnavailable, isPresented: $showLocationDeniedAlert) {
            Button(L10n.Contacts.Contacts.List.openSettings) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button(L10n.Contacts.Contacts.Common.cancel, role: .cancel) { }
        } message: {
            Text(L10n.Contacts.Contacts.List.distanceRequiresLocation)
        }
        .alert(L10n.Contacts.Contacts.Common.error, isPresented: showErrorBinding) {
            Button(L10n.Contacts.Contacts.Common.ok, role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? L10n.Contacts.Contacts.Common.errorOccurred)
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
                    L10n.Contacts.Contacts.List.Empty.Favorites.title,
                    systemImage: "star",
                    description: Text(L10n.Contacts.Contacts.List.Empty.Favorites.description)
                )
            case .contacts:
                ContentUnavailableView(
                    L10n.Contacts.Contacts.List.Empty.Contacts.title,
                    systemImage: "person.2",
                    description: Text(L10n.Contacts.Contacts.List.Empty.Contacts.description)
                )
            case .network:
                ContentUnavailableView(
                    L10n.Contacts.Contacts.List.Empty.Network.title,
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text(L10n.Contacts.Contacts.List.Empty.Network.description)
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
                L10n.Contacts.Contacts.List.Empty.Search.title,
                systemImage: "magnifyingglass",
                description: Text(L10n.Contacts.Contacts.List.Empty.Search.description(searchText))
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
                index: index,
                isTogglingFavorite: viewModel.togglingFavoriteID == contact.id
            )
        }
        .contactSwipeActions(contact: contact, viewModel: viewModel)
    }

    private func contactSplitRow(_ contact: ContactDTO, index: Int) -> some View {
        ContactRowView(
            contact: contact,
            showTypeLabel: isSearching,
            userLocation: appState.locationService.currentLocation,
            index: index,
            isTogglingFavorite: viewModel.togglingFavoriteID == contact.id
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
            argument: L10n.Contacts.Contacts.List.offlineAnnouncement
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
        Picker(L10n.Contacts.Contacts.Segment.contacts, selection: $selection) {
            ForEach(NodeSegment.allCases, id: \.self) { segment in
                Text(segment.localizedTitle).tag(segment)
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
    let isTogglingFavorite: Bool

    init(
        contact: ContactDTO,
        showTypeLabel: Bool = false,
        userLocation: CLLocation? = nil,
        index: Int = 0,
        isTogglingFavorite: Bool = false
    ) {
        self.contact = contact
        self.showTypeLabel = showTypeLabel
        self.userLocation = userLocation
        self.index = index
        self.isTogglingFavorite = isTogglingFavorite
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
                            .accessibilityLabel(L10n.Contacts.Contacts.Row.blocked)
                    }

                    Spacer()

                    if isTogglingFavorite {
                        ProgressView()
                            .controlSize(.small)
                    } else if contact.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .accessibilityLabel(L10n.Contacts.Contacts.Row.favorite)
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
                        Label(L10n.Contacts.Contacts.Row.location, systemImage: "location.fill")
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
            .alignmentGuide(.listRowSeparatorLeading) { dimensions in
                dimensions[.leading]
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
        case .chat: return L10n.Contacts.Contacts.NodeKind.contact
        case .repeater: return L10n.Contacts.Contacts.NodeKind.repeater
        case .room: return L10n.Contacts.Contacts.NodeKind.room
        }
    }

    private var routeLabel: String {
        if contact.isFloodRouted {
            return L10n.Contacts.Contacts.Route.flood
        } else if contact.outPathLength == 0 {
            return L10n.Contacts.Contacts.Route.direct
        } else if contact.outPathLength > 0 {
            return L10n.Contacts.Contacts.Route.hops(Int(contact.outPathLength))
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

        let formattedDistance = measurement.formatted(.measurement(
            width: .abbreviated,
            usage: .road
        ))
        return L10n.Contacts.Contacts.Row.away(formattedDistance)
    }
}

// MARK: - Contact Swipe Actions

private struct ContactSwipeActionsModifier: ViewModifier {
    @Environment(\.appState) private var appState

    let contact: ContactDTO
    let viewModel: ContactsViewModel

    private var isConnected: Bool {
        appState.connectionState == .ready
    }

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    Task {
                        await viewModel.deleteContact(contact)
                    }
                } label: {
                    Label(L10n.Contacts.Contacts.Common.delete, systemImage: "trash")
                }
                .disabled(!isConnected)

                Button {
                    Task {
                        await viewModel.toggleBlocked(contact: contact)
                    }
                } label: {
                    Label(
                        contact.isBlocked ? L10n.Contacts.Contacts.Swipe.unblock : L10n.Contacts.Contacts.Swipe.block,
                        systemImage: contact.isBlocked ? "hand.raised.slash" : "hand.raised"
                    )
                }
                .tint(.orange)
                .disabled(!isConnected)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    Task {
                        await viewModel.toggleFavorite(contact: contact)
                    }
                } label: {
                    Label(
                        contact.isFavorite ? L10n.Contacts.Contacts.Swipe.unfavorite : L10n.Contacts.Contacts.Row.favorite,
                        systemImage: contact.isFavorite ? "star.slash" : "star.fill"
                    )
                }
                .tint(.yellow)
                .disabled(!isConnected || viewModel.togglingFavoriteID == contact.id)
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
