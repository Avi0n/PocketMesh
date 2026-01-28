import CoreLocation
import SwiftUI
import PocketMeshServices

/// Shows contacts discovered via advertisement that haven't been added to the device
struct DiscoveryView: View {
    @Environment(\.appState) private var appState
    @State private var viewModel = DiscoveryViewModel()
    @State private var searchText = ""
    @State private var selectedSegment: DiscoverSegment = .all
    @AppStorage("discoverySortOrder") private var sortOrder: NodeSortOrder = .lastHeard
    @State private var addingContactID: UUID?
    @State private var showClearConfirmation = false

    private var filteredContacts: [ContactDTO] {
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

    private var showErrorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }

    var body: some View {
        Group {
            if !viewModel.hasLoadedOnce {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredContacts.isEmpty && !isSearching {
                emptyView
            } else if filteredContacts.isEmpty && isSearching {
                searchEmptyView
            } else {
                contactsList
            }
        }
        .navigationTitle(L10n.Contacts.Contacts.Discovery.title)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                sortMenu
            }

            ToolbarItem(placement: .automatic) {
                moreMenu
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: L10n.Contacts.Contacts.Discovery.searchPrompt
        )
        .onChange(of: searchText) { _, newValue in
            if !newValue.isEmpty && UIAccessibility.isVoiceOverRunning {
                UIAccessibility.post(
                    notification: .announcement,
                    argument: L10n.Contacts.Contacts.Discovery.searchingAllTypes
                )
            }
        }
        .task {
            viewModel.configure(appState: appState)
            await loadDiscoveredContacts()
        }
        .onChange(of: appState.servicesVersion) { _, _ in
            Task {
                await loadDiscoveredContacts()
            }
        }
        .onChange(of: appState.contactsVersion) { _, _ in
            Task {
                await loadDiscoveredContacts()
            }
        }
        .alert(L10n.Contacts.Contacts.Common.error, isPresented: showErrorBinding) {
            Button(L10n.Contacts.Contacts.Common.ok) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .confirmationDialog(
            L10n.Contacts.Contacts.Discovery.Clear.title,
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.Contacts.Contacts.Discovery.Clear.confirm, role: .destructive) {
                Task {
                    await clearAllDiscoveredContacts()
                }
            }
        } message: {
            Text(L10n.Contacts.Contacts.Discovery.Clear.message)
        }
    }

    private var emptyView: some View {
        VStack {
            DiscoverSegmentPicker(selection: $selectedSegment, isSearching: isSearching)

            Spacer()

            ContentUnavailableView(
                L10n.Contacts.Contacts.Discovery.Empty.title,
                systemImage: "antenna.radiowaves.left.and.right",
                description: Text(L10n.Contacts.Contacts.Discovery.Empty.description)
            )

            Spacer()
        }
    }

    private var searchEmptyView: some View {
        VStack {
            DiscoverSegmentPicker(selection: $selectedSegment, isSearching: isSearching)

            Spacer()

            ContentUnavailableView(
                L10n.Contacts.Contacts.Discovery.Empty.Search.title,
                systemImage: "magnifyingglass",
                description: Text(L10n.Contacts.Contacts.Discovery.Empty.Search.description(searchText))
            )

            Spacer()
        }
    }

    private var contactsList: some View {
        List {
            Section {
                DiscoverSegmentPicker(selection: $selectedSegment, isSearching: isSearching)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden)

            ForEach(filteredContacts) { contact in
                discoveredContactRow(contact)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task {
                                await viewModel.deleteDiscoveredContact(contact)
                            }
                        } label: {
                            Label(L10n.Contacts.Contacts.Discovery.remove, systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
    }

    private var sortMenu: some View {
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
        .modifier(GlassButtonModifier())
        .accessibilityLabel(L10n.Contacts.Contacts.Discovery.sortMenu)
        .accessibilityHint(L10n.Contacts.Contacts.Discovery.sortMenuHint)
    }

    private var moreMenu: some View {
        Menu {
            Button(role: .destructive) {
                showClearConfirmation = true
            } label: {
                Label(L10n.Contacts.Contacts.Discovery.clear, systemImage: "trash")
            }
            .disabled(viewModel.discoveredContacts.isEmpty)
        } label: {
            Label(L10n.Contacts.Contacts.Discovery.menu, systemImage: "ellipsis.circle")
        }
        .modifier(GlassButtonModifier())
    }

    private func discoveredContactRow(_ contact: ContactDTO) -> some View {
        HStack {
            avatarView(for: contact)

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.displayName)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 4) {
                    Text(contactTypeLabel(for: contact))

                    if contact.hasLocation {
                        Text("·")

                        Label(L10n.Contacts.Contacts.Row.location, systemImage: "location.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.green)

                        if let distance = distanceToContact(contact) {
                            Text(distance)
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            RelativeTimestampText(timestamp: contact.lastAdvertTimestamp)

            Button {
                Task {
                    await addContact(contact)
                }
            } label: {
                if addingContactID == contact.id {
                    ProgressView()
                        .frame(width: 60)
                } else {
                    Text(L10n.Contacts.Contacts.Discovery.add)
                        .frame(width: 60)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(addingContactID != nil)
        }
        .padding(.vertical, 4)
    }

    private func distanceToContact(_ contact: ContactDTO) -> String? {
        guard let userLocation = appState.locationService.currentLocation,
              contact.hasLocation else { return nil }

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

    @ViewBuilder
    private func avatarView(for contact: ContactDTO) -> some View {
        switch contact.type {
        case .chat:
            ContactAvatar(contact: contact, size: 44)
        case .repeater:
            NodeAvatar(publicKey: contact.publicKey, role: .repeater, size: 44)
        case .room:
            NodeAvatar(publicKey: contact.publicKey, role: .roomServer, size: 44)
        }
    }

    private func contactTypeLabel(for contact: ContactDTO) -> String {
        switch contact.type {
        case .chat: return L10n.Contacts.Contacts.NodeKind.chat
        case .repeater: return L10n.Contacts.Contacts.NodeKind.repeater
        case .room: return L10n.Contacts.Contacts.NodeKind.room
        }
    }

    private func loadDiscoveredContacts() async {
        guard let deviceID = appState.connectedDevice?.id else { return }
        viewModel.configure(appState: appState)
        await viewModel.loadDiscoveredContacts(deviceID: deviceID)
    }

    private func clearAllDiscoveredContacts() async {
        guard let deviceID = appState.connectedDevice?.id else { return }
        await viewModel.clearAllDiscoveredContacts(deviceID: deviceID)

        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(
                notification: .announcement,
                argument: L10n.Contacts.Contacts.Discovery.clearedAllNodes
            )
        }
    }

    private func addContact(_ contact: ContactDTO) async {
        guard let contactService = appState.services?.contactService,
              let dataStore = appState.services?.dataStore else {
            viewModel.errorMessage = L10n.Contacts.Contacts.Discovery.Error.servicesUnavailable
            return
        }

        let maxContacts = appState.connectedDevice?.maxContacts
        addingContactID = contact.id

        do {
            // Send to device
            try await contactService.addOrUpdateContact(
                deviceID: contact.deviceID,
                contact: contact.toContactFrame()
            )

            // Mark as confirmed locally
            try await dataStore.confirmContact(id: contact.id)

            // Remove from local list
            viewModel.discoveredContacts.removeAll { $0.id == contact.id }
        } catch ContactServiceError.contactTableFull {
            if let maxContacts {
                viewModel.errorMessage = L10n.Contacts.Contacts.Add.Error.nodeListFull(Int(maxContacts))
            } else {
                viewModel.errorMessage = L10n.Contacts.Contacts.Add.Error.nodeListFullSimple
            }
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }

        addingContactID = nil
    }
}

// MARK: - Discover Segment Picker

struct DiscoverSegmentPicker: View {
    @Binding var selection: DiscoverSegment
    let isSearching: Bool

    var body: some View {
        Picker(L10n.Contacts.Contacts.Discovery.Segment.all, selection: $selection) {
            ForEach(DiscoverSegment.allCases, id: \.self) { segment in
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

// MARK: - Glass Effect Modifier

private struct GlassButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content
        }
    }
}

#Preview {
    NavigationStack {
        DiscoveryView()
    }
    .environment(\.appState, AppState())
}
