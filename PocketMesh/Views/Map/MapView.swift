import os
import SwiftUI
import MapKit
import PocketMeshServices

private let logger = Logger(subsystem: "com.pocketmesh", category: "MapView")

/// Map view displaying contacts with their locations
struct MapView: View {
    /// Estimated duration for sheet presentation animation. SwiftUI doesn't provide a completion callback,
    /// so we use this delay before switching to the snapshot to hide the transition from the user.
    private static let sheetPresentationDuration: Duration = .milliseconds(500)

    @Environment(\.appState) private var appState
    @State private var viewModel = MapViewModel()
    @State private var selectedContactForDetail: ContactDTO?
    /// Static snapshot of the map shown while sheets are presented to prevent memory growth from SwiftUI keyboard layout cycles
    @State private var mapSnapshot: UIImage?
    /// Controls when snapshot is shown - delayed until after sheet presents to hide the transition
    @State private var isSnapshotActive = false
    /// Closure to get snapshot parameters directly from MKMapView (camera + bounds, avoids async binding lag)
    @State private var getSnapshotParams: (() -> (camera: MKMapCamera, size: CGSize)?)?

    var body: some View {
        NavigationStack {
            mapCanvas
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        BLEStatusIndicatorView()
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        refreshButton
                    }
                }
                .task {
                    appState.locationService.requestPermissionIfNeeded()
                    appState.locationService.requestLocation()
                    viewModel.configure(appState: appState)
                    await viewModel.loadContactsWithLocation()
                    viewModel.centerOnAllContacts()
                }
                .sheet(item: $selectedContactForDetail, onDismiss: clearMapSnapshot) { contact in
                    ContactDetailSheet(
                        contact: contact,
                        onMessage: { navigateToChat(with: contact) }
                    )
                    .presentationDetents([.large])
                }
                .liquidGlassToolbarBackground()
        }
    }

    // MARK: - Map Canvas

    private var mapCanvas: some View {
        ZStack {
            mapContent
                .ignoresSafeArea()

            // Floating controls
            VStack {
                Spacer()
                mapControls
            }

            // Layers menu overlay
            if viewModel.showingLayersMenu {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation {
                            viewModel.showingLayersMenu = false
                        }
                    }

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        LayersMenu(
                            selection: $viewModel.mapStyleSelection,
                            isPresented: $viewModel.showingLayersMenu
                        )
                        .padding(.trailing, 72)
                        .padding(.bottom)
                    }
                }
            }
        }
    }

    // MARK: - Map Content

    @ViewBuilder
    private var mapContent: some View {
        if viewModel.contactsWithLocation.isEmpty && !viewModel.isLoading {
            emptyState
        } else {
            // Keep MKMapView always in tree to prevent Metal deallocation crashes
            // Hide it with opacity when showing snapshot instead of removing from hierarchy
            let showingSnapshot = isSnapshotActive && mapSnapshot != nil

            ZStack {
                MKMapViewRepresentable(
                    contacts: viewModel.contactsWithLocation,
                    mapType: viewModel.mapStyleSelection.mkMapType,
                    showLabels: viewModel.shouldShowLabels,
                    showsUserLocation: true,
                    selectedContact: $viewModel.selectedContact,
                    cameraRegion: $viewModel.cameraRegion,
                    onDetailTap: { contact in
                        showContactDetail(contact)
                    },
                    onMessageTap: { contact in
                        navigateToChat(with: contact)
                    },
                    onSnapshotParamsGetter: { getter in
                        getSnapshotParams = getter
                    }
                )
                .opacity(showingSnapshot ? 0 : 1)

                if showingSnapshot, let snapshot = mapSnapshot {
                    // Show static snapshot while sheet is presented to prevent memory growth
                    // MKMapView clustering causes unbounded memory growth during keyboard layout cycles
                    // Must ignore safe area to match MKMapView's positioning (UIView fills entire area)
                    Image(uiImage: snapshot)
                        .resizable()
                        .ignoresSafeArea()
                }
            }
            .overlay {
                if viewModel.isLoading {
                    loadingOverlay
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Contacts on Map", systemImage: "map")
        } description: {
            Text("Contacts with location data will appear here once discovered on the mesh network.")
        } actions: {
            Button("Refresh") {
                Task {
                    await viewModel.loadContactsWithLocation()
                }
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Loading Overlay

    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.1)
            ProgressView()
                .padding()
                .background(.regularMaterial, in: .rect(cornerRadius: 8))
        }
    }

    // MARK: - Map Controls

    private var mapControls: some View {
        HStack {
            Spacer()
            mapControlsStack
        }
    }

    private var mapControlsStack: some View {
        MapControlsToolbar(
            onLocationTap: { centerOnUserLocation() },
            showingLayersMenu: $viewModel.showingLayersMenu
        ) {
            labelsToggleButton
            centerAllButton
        }
    }

    private var labelsToggleButton: some View {
        Button {
            withAnimation {
                viewModel.showLabels.toggle()
            }
        } label: {
            Image(systemName: "character.textbox")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(viewModel.showLabels ? .blue : .primary)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.showLabels ? "Hide labels" : "Show labels")
    }

    private var centerAllButton: some View {
        Button {
            clearSelection()
            viewModel.centerOnAllContacts()
        } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(viewModel.contactsWithLocation.isEmpty ? .secondary : .primary)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(viewModel.contactsWithLocation.isEmpty)
        .accessibilityLabel("Center on all contacts")
    }

    // MARK: - Refresh Button

    private var refreshButton: some View {
        Button {
            Task {
                await viewModel.loadContactsWithLocation()
            }
        } label: {
            if viewModel.isLoading {
                ProgressView()
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .disabled(viewModel.isLoading)
    }

    // MARK: - Actions

    private func selectContact(_ contact: ContactDTO) {
        viewModel.centerOnContact(contact)
    }

    private func clearSelection() {
        viewModel.clearSelection()
    }

    private func navigateToChat(with contact: ContactDTO) {
        clearSelection()
        appState.navigateToChat(with: contact)
    }

    private func showContactDetail(_ contact: ContactDTO) {
        // Clear selection to prevent MKSmallCalloutView constraint corruption
        viewModel.selectedContact = nil
        // Present sheet immediately so user sees it animating in
        selectedContactForDetail = contact

        // Capture snapshot after sheet animation completes to hide the transition
        Task {
            try? await Task.sleep(for: Self.sheetPresentationDuration)
            // Guard against race condition if sheet was dismissed during delay
            guard selectedContactForDetail != nil else { return }
            await captureMapSnapshot()
            isSnapshotActive = true
        }
    }

    /// Captures a static snapshot of the current map view to display while sheets are presented
    private func captureMapSnapshot() async {
        // Get camera and bounds directly from MKMapView for pixel-perfect match
        // Using camera instead of region avoids MKMapSnapshotter's automatic aspect ratio adjustment
        guard let params = getSnapshotParams?() else { return }

        let options = MKMapSnapshotter.Options()
        options.camera = params.camera
        options.size = params.size
        options.scale = UIScreen.main.scale
        options.mapType = viewModel.mapStyleSelection.mkMapType
        options.showsBuildings = true

        let snapshotter = MKMapSnapshotter(options: options)
        do {
            let snapshot = try await snapshotter.start()
            mapSnapshot = snapshot.image
        } catch {
            logger.warning("Map snapshot capture failed: \(error.localizedDescription)")
            mapSnapshot = nil
        }
    }

    private func clearMapSnapshot() {
        isSnapshotActive = false
        mapSnapshot = nil
    }

    private func centerOnUserLocation() {
        guard let location = appState.locationService.currentLocation else { return }
        let span = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        viewModel.cameraRegion = MKCoordinateRegion(center: location.coordinate, span: span)
    }
}

// MARK: - Contact Detail Sheet

private struct ContactDetailSheet: View {
    let contact: ContactDTO
    let onMessage: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appState) private var appState

    /// Sheet types for repeater flows
    private enum ActiveSheet: Identifiable, Hashable {
        case telemetryAuth
        case telemetryStatus(RemoteNodeSessionDTO)
        case adminAuth
        case adminSettings(RemoteNodeSessionDTO)
        case roomJoin

        var id: String {
            switch self {
            case .telemetryAuth: "telemetryAuth"
            case .telemetryStatus(let s): "telemetryStatus-\(s.id)"
            case .adminAuth: "adminAuth"
            case .adminSettings(let s): "adminSettings-\(s.id)"
            case .roomJoin: "roomJoin"
            }
        }
    }

    @State private var activeSheet: ActiveSheet?
    @State private var pendingSheet: ActiveSheet?

    var body: some View {
        NavigationStack {
            List {
                // Basic info section
                Section("Contact Info") {
                    LabeledContent("Name", value: contact.displayName)

                    LabeledContent("Type") {
                        HStack {
                            Image(systemName: typeIconName)
                            Text(typeDisplayName)
                        }
                        .foregroundStyle(typeColor)
                    }

                    if contact.isFavorite {
                        LabeledContent("Status") {
                            HStack {
                                Image(systemName: "star.fill")
                                Text("Favorite")
                            }
                            .foregroundStyle(.orange)
                        }
                    }

                    if contact.lastAdvertTimestamp > 0 {
                        LabeledContent("Last Advert") {
                            ConversationTimestamp(date: Date(timeIntervalSince1970: TimeInterval(contact.lastAdvertTimestamp)), font: .body)
                        }
                    }
                }

                // Location section
                Section("Location") {
                    LabeledContent("Latitude") {
                        Text(contact.latitude, format: .number.precision(.fractionLength(6)))
                    }

                    LabeledContent("Longitude") {
                        Text(contact.longitude, format: .number.precision(.fractionLength(6)))
                    }
                }

                // Path info section
                Section("Network Path") {
                    if contact.isFloodRouted {
                        LabeledContent("Routing", value: "Flood")
                    } else {
                        LabeledContent("Path Length", value: "\(contact.outPathLength) hops")
                    }
                }

                // Actions section
                Section {
                    switch contact.type {
                    case .repeater:
                        Button {
                            activeSheet = .telemetryAuth
                        } label: {
                            Label("Telemetry", systemImage: "chart.line.uptrend.xyaxis")
                        }

                        Button {
                            activeSheet = .adminAuth
                        } label: {
                            Label("Admin Access", systemImage: "gearshape.2")
                        }

                    case .room:
                        Button {
                            activeSheet = .roomJoin
                        } label: {
                            Label("Join Room", systemImage: "door.left.hand.open")
                        }

                    case .chat:
                        Button {
                            dismiss()
                            onMessage()
                        } label: {
                            Label("Send Message", systemImage: "message.fill")
                        }
                    }
                }
            }
            .navigationTitle(contact.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(item: $activeSheet, onDismiss: presentPendingSheet) { sheet in
                switch sheet {
                case .telemetryAuth:
                    if let role = RemoteNodeRole(contactType: contact.type) {
                        NodeAuthenticationSheet(
                            contact: contact,
                            role: role,
                            customTitle: "Telemetry Access"
                        ) { session in
                            pendingSheet = .telemetryStatus(session)
                            activeSheet = nil
                        }
                        .presentationSizing(.page)
                    }

                case .telemetryStatus(let session):
                    RepeaterStatusView(session: session)

                case .adminAuth:
                    if let role = RemoteNodeRole(contactType: contact.type) {
                        NodeAuthenticationSheet(contact: contact, role: role) { session in
                            pendingSheet = .adminSettings(session)
                            activeSheet = nil
                        }
                        .presentationSizing(.page)
                    }

                case .adminSettings(let session):
                    NavigationStack {
                        RepeaterSettingsView(session: session)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") {
                                        activeSheet = nil
                                    }
                                }
                            }
                    }
                    .presentationSizing(.page)

                case .roomJoin:
                    if let role = RemoteNodeRole(contactType: contact.type) {
                        NodeAuthenticationSheet(contact: contact, role: role) { session in
                            activeSheet = nil
                            dismiss()
                            appState.navigateToRoom(with: session)
                        }
                        .presentationSizing(.page)
                    }
                }
            }
        }
    }

    // MARK: - Sheet Management

    private func presentPendingSheet() {
        if let next = pendingSheet {
            pendingSheet = nil
            activeSheet = next
        }
    }

    // MARK: - Computed Properties

    private var typeIconName: String {
        switch contact.type {
        case .chat:
            "person.fill"
        case .repeater:
            "antenna.radiowaves.left.and.right"
        case .room:
            "person.3.fill"
        }
    }

    private var typeDisplayName: String {
        switch contact.type {
        case .chat:
            "Chat Contact"
        case .repeater:
            "Repeater"
        case .room:
            "Room"
        }
    }

    private var typeColor: Color {
        switch contact.type {
        case .chat:
            .blue
        case .repeater:
            .green
        case .room:
            .purple
        }
    }
}

// MARK: - Preview

#Preview("Map with Contacts") {
    MapView()
        .environment(\.appState, AppState())
}

#Preview("Empty Map") {
    MapView()
        .environment(\.appState, AppState())
}
