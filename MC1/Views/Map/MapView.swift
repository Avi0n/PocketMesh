import SwiftUI
import MapKit
import MC1Services

/// Map view displaying contacts with their locations
struct MapView: View {
    @Environment(\.appState) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @State private var viewModel = MapViewModel()
    @State private var selectedCalloutContact: ContactDTO?
    @State private var selectedPointScreenPosition: CGPoint?
    @State private var selectedContactForDetail: ContactDTO?
    @State private var isStyleLoaded = false

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
                .sheet(item: $selectedContactForDetail) { contact in
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

            // Offline badge
            if !appState.offlineMapService.isNetworkAvailable {
                OfflineBadge()
            }

            // Floating controls
            VStack {
                Spacer()
                mapControls
            }

            // Layers menu overlay
            if viewModel.showingLayersMenu {
                Button {
                    withAnimation {
                        viewModel.showingLayersMenu = false
                    }
                } label: {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                }
                .buttonStyle(.plain)

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
            MC1MapView(
                points: mapPoints,
                lines: [],
                mapStyle: viewModel.mapStyleSelection,
                isDarkMode: colorScheme == .dark,
                showLabels: viewModel.showLabels,
                showsUserLocation: true,
                isInteractive: true,
                showsScale: true,
                cameraRegion: $viewModel.cameraRegion,
                cameraRegionVersion: viewModel.cameraRegionVersion,
                onPointTap: { point, screenPosition in
                    selectedCalloutContact = viewModel.contactsWithLocation.first { $0.id == point.id }
                    selectedPointScreenPosition = screenPosition
                },
                onMapTap: { _ in
                    selectedCalloutContact = nil
                    selectedPointScreenPosition = nil
                },
                onCameraRegionChange: { region in
                    viewModel.cameraRegion = region
                    selectedCalloutContact = nil
                    selectedPointScreenPosition = nil
                },
                isStyleLoaded: $isStyleLoaded
            )
            .popover(
                item: $selectedCalloutContact,
                attachmentAnchor: .rect(.rect(CGRect(
                    origin: selectedPointScreenPosition ?? .zero,
                    size: CGSize(width: 1, height: 1)
                ))),
                arrowEdge: .bottom
            ) { contact in
                ContactCalloutContent(
                    contact: contact,
                    onDetail: { showContactDetail(contact) },
                    onMessage: { navigateToChat(with: contact) }
                )
                .presentationCompactAdaptation(.popover)
            }
            .overlay {
                if !isStyleLoaded {
                    ProgressView()
                        .scaleEffect(1.5)
                } else if viewModel.isLoading {
                    loadingOverlay
                }
            }
        }
    }

    private var mapPoints: [MapPoint] {
        viewModel.contactsWithLocation.map { contact in
            MapPoint(
                id: contact.id,
                coordinate: contact.coordinate,
                pinStyle: pinStyle(for: contact),
                label: contact.displayName,
                isClusterable: true,
                hopIndex: nil,
                badgeText: nil
            )
        }
    }

    private func pinStyle(for contact: ContactDTO) -> MapPoint.PinStyle {
        switch contact.type {
        case .chat: .contactChat
        case .repeater: .contactRepeater
        case .room: .contactRoom
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label(L10n.Map.Map.EmptyState.title, systemImage: "map")
        } description: {
            Text(L10n.Map.Map.EmptyState.description)
        } actions: {
            Button(L10n.Map.Map.Common.refresh) {
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
        .accessibilityLabel(viewModel.showLabels ? L10n.Map.Map.Controls.hideLabels : L10n.Map.Map.Controls.showLabels)
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
        .accessibilityLabel(L10n.Map.Map.Controls.centerAll)
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

    private func clearSelection() {
        selectedCalloutContact = nil
        selectedPointScreenPosition = nil
    }

    private func navigateToChat(with contact: ContactDTO) {
        clearSelection()
        appState.navigation.navigateToChat(with: contact)
    }

    private func showContactDetail(_ contact: ContactDTO) {
        selectedCalloutContact = nil
        selectedPointScreenPosition = nil
        selectedContactForDetail = contact
    }

    private func centerOnUserLocation() {
        guard let location = appState.locationService.currentLocation else { return }
        let span = MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
        viewModel.cameraRegion = MKCoordinateRegion(center: location.coordinate, span: span)
        viewModel.cameraRegionVersion += 1
    }
}

// MARK: - Offline Badge

private struct OfflineBadge: View {
    var body: some View {
        VStack {
            HStack {
                Text(L10n.Map.Map.OfflineBadge.label)
                    .font(.caption)
                    .bold()
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: .capsule)
                Spacer()
            }
            .padding(.leading)
            Spacer()
        }
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
                Section(L10n.Map.Map.Detail.Section.contactInfo) {
                    LabeledContent(L10n.Map.Map.Detail.name, value: contact.displayName)

                    LabeledContent(L10n.Map.Map.Detail.type) {
                        HStack {
                            Image(systemName: typeIconName)
                            Text(typeDisplayName)
                        }
                        .foregroundStyle(typeColor)
                    }

                    if contact.isFavorite {
                        LabeledContent(L10n.Map.Map.Detail.status) {
                            HStack {
                                Image(systemName: "star.fill")
                                Text(L10n.Map.Map.Detail.favorite)
                            }
                            .foregroundStyle(.orange)
                        }
                    }

                    if contact.lastAdvertTimestamp > 0 {
                        LabeledContent(L10n.Map.Map.Detail.lastAdvert) {
                            ConversationTimestamp(date: Date(timeIntervalSince1970: TimeInterval(contact.lastAdvertTimestamp)), font: .body)
                        }
                    }
                }

                // Location section
                Section(L10n.Map.Map.Detail.Section.location) {
                    LabeledContent(L10n.Map.Map.Detail.latitude) {
                        Text(contact.latitude, format: .number.precision(.fractionLength(6)))
                    }

                    LabeledContent(L10n.Map.Map.Detail.longitude) {
                        Text(contact.longitude, format: .number.precision(.fractionLength(6)))
                    }
                }

                // Path info section
                Section(L10n.Map.Map.Detail.Section.networkPath) {
                    if contact.isFloodRouted {
                        LabeledContent(L10n.Map.Map.Detail.routing, value: L10n.Map.Map.Detail.routingFlood)
                    } else {
                        let hopCount = contact.pathHopCount
                        LabeledContent(L10n.Map.Map.Detail.pathLength, value: hopCount == 1 ? L10n.Map.Map.Detail.hopSingular : L10n.Map.Map.Detail.hops(hopCount))
                    }
                }

                // Actions section
                Section {
                    switch contact.type {
                    case .repeater:
                        Button {
                            activeSheet = .telemetryAuth
                        } label: {
                            Label(L10n.Map.Map.Detail.Action.telemetry, systemImage: "chart.line.uptrend.xyaxis")
                        }

                        Button {
                            activeSheet = .adminAuth
                        } label: {
                            Label(L10n.Map.Map.Detail.Action.management, systemImage: "gearshape.2")
                        }

                    case .room:
                        Button {
                            activeSheet = .roomJoin
                        } label: {
                            Label(L10n.Map.Map.Detail.Action.joinRoom, systemImage: "door.left.hand.open")
                        }

                    case .chat:
                        Button {
                            dismiss()
                            onMessage()
                        } label: {
                            Label(L10n.Map.Map.Detail.Action.sendMessage, systemImage: "message.fill")
                        }
                        .radioDisabled(for: appState.connectionState)
                    }
                }
            }
            .navigationTitle(contact.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Map.Map.Common.done) {
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
                            customTitle: L10n.Map.Map.Detail.Action.telemetryAccessTitle
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
                            if session.isAdmin {
                                pendingSheet = .adminSettings(session)
                            } else {
                                pendingSheet = .telemetryStatus(session)
                            }
                            activeSheet = nil
                        }
                        .presentationSizing(.page)
                    }

                case .adminSettings(let session):
                    NavigationStack {
                        RepeaterSettingsView(session: session)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button(L10n.Map.Map.Common.done) {
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
                            appState.navigation.navigateToRoom(with: session)
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
            L10n.Map.Map.NodeKind.chatContact
        case .repeater:
            L10n.Map.Map.NodeKind.repeater
        case .room:
            L10n.Map.Map.NodeKind.room
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
