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
    @State private var addingNodeID: UUID?
    @State private var showClearConfirmation = false

    private var filteredNodes: [DiscoveredNodeDTO] {
        let effectiveSortOrder = (sortOrder == .distance && appState.locationService.currentLocation == nil)
            ? .lastHeard
            : sortOrder

        return viewModel.filteredNodes(
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
            } else if filteredNodes.isEmpty && !isSearching {
                emptyView
            } else if filteredNodes.isEmpty && isSearching {
                searchEmptyView
            } else {
                nodesList
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
            await loadDiscoveredNodes()
        }
        .onChange(of: appState.servicesVersion) { _, _ in
            Task {
                await loadDiscoveredNodes()
            }
        }
        .onChange(of: appState.contactsVersion) { _, _ in
            Task {
                await loadDiscoveredNodes()
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
                    await clearAllDiscoveredNodes()
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

    private var nodesList: some View {
        List {
            Section {
                DiscoverSegmentPicker(selection: $selectedSegment, isSearching: isSearching)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listSectionSeparator(.hidden)

            ForEach(filteredNodes) { node in
                discoveredNodeRow(node)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task {
                                await viewModel.deleteDiscoveredNode(node)
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
            .disabled(viewModel.discoveredNodes.isEmpty)
        } label: {
            Label(L10n.Contacts.Contacts.Discovery.menu, systemImage: "ellipsis.circle")
        }
        .modifier(GlassButtonModifier())
    }

    private func discoveredNodeRow(_ node: DiscoveredNodeDTO) -> some View {
        HStack {
            avatarView(for: node)

            VStack(alignment: .leading, spacing: 2) {
                Text(node.name)
                    .font(.body)
                    .bold()

                HStack(spacing: 4) {
                    Text(nodeTypeLabel(for: node))

                    if node.hasLocation {
                        Text("·")

                        Label(L10n.Contacts.Contacts.Row.location, systemImage: "location.fill")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.green)

                        if let distance = distanceToNode(node) {
                            Text(distance)
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            RelativeTimestampText(timestamp: node.lastAdvertTimestamp)

            if viewModel.isAdded(node) {
                Button(L10n.Contacts.Contacts.Discovery.added) {}
                    .buttonStyle(.bordered)
                    .disabled(true)
                    .accessibilityLabel(L10n.Contacts.Contacts.Discovery.addedAccessibility)
            } else {
                Button(L10n.Contacts.Contacts.Discovery.add) {
                    addNode(node)
                }
                .buttonStyle(.borderedProminent)
                .disabled(addingNodeID == node.id)
            }
        }
        .padding(.vertical, 4)
    }

    private func distanceToNode(_ node: DiscoveredNodeDTO) -> String? {
        guard let userLocation = appState.locationService.currentLocation,
              node.hasLocation else { return nil }

        let nodeLocation = CLLocation(
            latitude: node.latitude,
            longitude: node.longitude
        )
        let meters = userLocation.distance(from: nodeLocation)
        let measurement = Measurement(value: meters, unit: UnitLength.meters)

        let formattedDistance = measurement.formatted(.measurement(
            width: .abbreviated,
            usage: .road
        ))
        return L10n.Contacts.Contacts.Row.away(formattedDistance)
    }

    @ViewBuilder
    private func avatarView(for node: DiscoveredNodeDTO) -> some View {
        switch node.nodeType {
        case .chat:
            DiscoveredNodeAvatar(name: node.name, size: 44)
        case .repeater:
            NodeAvatar(publicKey: node.publicKey, role: .repeater, size: 44)
        case .room:
            NodeAvatar(publicKey: node.publicKey, role: .roomServer, size: 44)
        }
    }

    private func nodeTypeLabel(for node: DiscoveredNodeDTO) -> String {
        switch node.nodeType {
        case .chat: return L10n.Contacts.Contacts.NodeKind.chat
        case .repeater: return L10n.Contacts.Contacts.NodeKind.repeater
        case .room: return L10n.Contacts.Contacts.NodeKind.room
        }
    }

    private func loadDiscoveredNodes() async {
        guard let deviceID = appState.connectedDevice?.id else { return }
        viewModel.configure(appState: appState)
        await viewModel.loadDiscoveredNodes(deviceID: deviceID)
    }

    private func clearAllDiscoveredNodes() async {
        guard let deviceID = appState.connectedDevice?.id else { return }
        await viewModel.clearAllDiscoveredNodes(deviceID: deviceID)

        if UIAccessibility.isVoiceOverRunning {
            UIAccessibility.post(
                notification: .announcement,
                argument: L10n.Contacts.Contacts.Discovery.clearedAllNodes
            )
        }
    }

    private func addNode(_ node: DiscoveredNodeDTO) {
        guard let contactService = appState.services?.contactService else { return }

        addingNodeID = node.id
        Task {
            do {
                let frame = ContactFrame(
                    publicKey: node.publicKey,
                    type: node.nodeType,
                    flags: 0,
                    outPathLength: node.outPathLength,
                    outPath: node.outPath,
                    name: node.name,
                    lastAdvertTimestamp: node.lastAdvertTimestamp,
                    latitude: node.latitude,
                    longitude: node.longitude,
                    lastModified: 0
                )
                try await contactService.addOrUpdateContact(deviceID: node.deviceID, contact: frame)
                await viewModel.loadDiscoveredNodes(deviceID: node.deviceID)
            } catch ContactServiceError.contactTableFull {
                let maxContacts = appState.connectedDevice?.maxContacts
                if let maxContacts {
                    viewModel.errorMessage = L10n.Contacts.Contacts.Add.Error.nodeListFull(Int(maxContacts))
                } else {
                    viewModel.errorMessage = L10n.Contacts.Contacts.Add.Error.nodeListFullSimple
                }
            } catch {
                viewModel.errorMessage = error.localizedDescription
            }
            addingNodeID = nil
        }
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

// MARK: - Discovered Node Avatar

private struct DiscoveredNodeAvatar: View {
    let name: String
    let size: CGFloat

    var body: some View {
        Text(initials)
            .font(.system(size: size * 0.4, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(avatarColor, in: .circle)
    }

    private var initials: String {
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words[0].prefix(1) + words[1].prefix(1)).uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    private var avatarColor: Color {
        AppColors.NameColor.color(for: name)
    }
}

#Preview {
    NavigationStack {
        DiscoveryView()
    }
    .environment(\.appState, AppState())
}
