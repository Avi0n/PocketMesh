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
        Button(viewModel.showLabels ? L10n.Map.Map.Controls.hideLabels : L10n.Map.Map.Controls.showLabels, systemImage: "character.textbox") {
            withAnimation {
                viewModel.showLabels.toggle()
            }
        }
        .font(.body.weight(.medium))
        .foregroundStyle(viewModel.showLabels ? .blue : .primary)
        .frame(width: 44, height: 44)
        .contentShape(.rect)
        .buttonStyle(.plain)
        .labelStyle(.iconOnly)
    }

    private var centerAllButton: some View {
        Button(L10n.Map.Map.Controls.centerAll, systemImage: "arrow.up.left.and.arrow.down.right") {
            clearSelection()
            viewModel.centerOnAllContacts()
        }
        .font(.body.weight(.medium))
        .foregroundStyle(viewModel.contactsWithLocation.isEmpty ? .secondary : .primary)
        .frame(width: 44, height: 44)
        .contentShape(.rect)
        .buttonStyle(.plain)
        .disabled(viewModel.contactsWithLocation.isEmpty)
        .labelStyle(.iconOnly)
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

// MARK: - Preview

#Preview("Map with Contacts") {
    MapView()
        .environment(\.appState, AppState())
}

#Preview("Empty Map") {
    MapView()
        .environment(\.appState, AppState())
}
