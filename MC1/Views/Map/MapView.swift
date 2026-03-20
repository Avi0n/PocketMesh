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
            MapCanvasView(
                viewModel: viewModel,
                mapPoints: viewModel.mapPoints,
                colorScheme: colorScheme,
                selectedCalloutContact: $selectedCalloutContact,
                selectedPointScreenPosition: $selectedPointScreenPosition,
                isStyleLoaded: $isStyleLoaded,
                onShowContactDetail: { showContactDetail($0) },
                onNavigateToChat: { navigateToChat(with: $0) },
                onCenterOnUser: { centerOnUserLocation() },
                onClearSelection: { clearSelection() }
            )
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
