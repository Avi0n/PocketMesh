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
                    ContactsSidebarContent(
                        viewModel: viewModel,
                        filteredContacts: filteredContacts,
                        isSearching: isSearching,
                        searchPrompt: searchPrompt,
                        shouldUseSplitView: shouldUseSplitView,
                        selectedSegment: $selectedSegment,
                        selectedContact: $selectedContact,
                        searchText: $searchText,
                        sortOrder: $sortOrder,
                        showDiscovery: $showDiscovery,
                        syncSuccessTrigger: $syncSuccessTrigger,
                        showShareMyContact: $showShareMyContact,
                        showAddContact: $showAddContact,
                        showLocationDeniedAlert: $showLocationDeniedAlert,
                        showOfflineRefreshAlert: $showOfflineRefreshAlert,
                        navigationPath: $navigationPath,
                        showErrorBinding: showErrorBinding,
                        onLoadContacts: loadContacts,
                        onSyncContacts: syncContacts,
                        onAnnounceOfflineStateIfNeeded: announceOfflineStateIfNeeded
                    )
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
                ContactsSidebarContent(
                    viewModel: viewModel,
                    filteredContacts: filteredContacts,
                    isSearching: isSearching,
                    searchPrompt: searchPrompt,
                    shouldUseSplitView: shouldUseSplitView,
                    selectedSegment: $selectedSegment,
                    selectedContact: $selectedContact,
                    searchText: $searchText,
                    sortOrder: $sortOrder,
                    showDiscovery: $showDiscovery,
                    syncSuccessTrigger: $syncSuccessTrigger,
                    showShareMyContact: $showShareMyContact,
                    showAddContact: $showAddContact,
                    showLocationDeniedAlert: $showLocationDeniedAlert,
                    showOfflineRefreshAlert: $showOfflineRefreshAlert,
                    navigationPath: $navigationPath,
                    showErrorBinding: showErrorBinding,
                    onLoadContacts: loadContacts,
                    onSyncContacts: syncContacts,
                    onAnnounceOfflineStateIfNeeded: announceOfflineStateIfNeeded
                )
                .navigationDestination(isPresented: $showDiscovery) {
                    DiscoveryView()
                }
                .navigationDestination(for: ContactDTO.self) { contact in
                    ContactDetailView(contact: contact)
                }
            }
        }
    }

    private var showErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
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

                        Text("\u{00B7}")
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

struct ContactSwipeActionsModifier: ViewModifier {
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

extension View {
    func contactSwipeActions(contact: ContactDTO, viewModel: ContactsViewModel) -> some View {
        modifier(ContactSwipeActionsModifier(contact: contact, viewModel: viewModel))
    }
}

#Preview {
    ContactsListView()
        .environment(\.appState, AppState())
}
