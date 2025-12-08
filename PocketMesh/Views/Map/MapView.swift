import SwiftUI
import MapKit
import PocketMeshKit
import CoreLocation

/// Handles location permission for the map view
@MainActor
@Observable
final class MapLocationCoordinator: NSObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var showingDeniedAlert = false

    override init() {
        super.init()
        locationManager.delegate = self
        authorizationStatus = locationManager.authorizationStatus
    }

    func handleLocationButtonTap() {
        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            showingDeniedAlert = true
        case .authorizedWhenInUse, .authorizedAlways:
            // Permission granted - MapUserLocationButton handles centering
            break
        @unknown default:
            break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
        }
    }
}

/// Map view displaying contacts with their locations
struct MapView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = MapViewModel()
    @State private var showingContactDetail = false
    @State private var selectedContactForDetail: ContactDTO?
    @Namespace private var mapScope
    @State private var locationCoordinator = MapLocationCoordinator()

    var body: some View {
        NavigationStack {
            ZStack {
                mapContent

                // Floating controls
                VStack {
                    Spacer()
                    mapControls
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    refreshButton
                }
            }
            .task {
                viewModel.configure(appState: appState)
                await viewModel.loadContactsWithLocation()
                viewModel.centerOnAllContacts()
            }
            .sheet(isPresented: $showingContactDetail) {
                if let contact = selectedContactForDetail {
                    ContactDetailSheet(
                        contact: contact,
                        onMessage: { navigateToChat(with: contact) }
                    )
                }
            }
            .alert("Location Access Required", isPresented: $locationCoordinator.showingDeniedAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("PocketMesh needs location access to show your current location on the map. Please enable it in Settings.")
            }
        }
    }

    // MARK: - Map Content

    @ViewBuilder
    private var mapContent: some View {
        if viewModel.contactsWithLocation.isEmpty && !viewModel.isLoading {
            emptyState
        } else {
            Map(position: $viewModel.cameraPosition, scope: mapScope) {
                ForEach(viewModel.contactsWithLocation) { contact in
                    Annotation(
                        contact.displayName,
                        coordinate: contact.coordinate,
                        anchor: .bottom
                    ) {
                        VStack(spacing: 0) {
                            // Callout appears above the pin when selected
                            if viewModel.selectedContact?.id == contact.id {
                                ContactAnnotationCallout(
                                    contact: contact,
                                    onMessageTap: { navigateToChat(with: contact) },
                                    onDetailTap: { showContactDetail(contact) }
                                )
                                .transition(.scale.combined(with: .opacity))
                            }

                            // Pin is always visible
                            ContactAnnotationView(
                                contact: contact,
                                isSelected: viewModel.selectedContact?.id == contact.id
                            )
                        }
                        .animation(.spring(response: 0.3), value: viewModel.selectedContact?.id)
                        .onTapGesture {
                            handleAnnotationTap(contact)
                        }
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapScope(mapScope)
            .mapControls {
                MapCompass(scope: mapScope)
                // Only show system location button if authorized
                if locationCoordinator.authorizationStatus == .authorizedWhenInUse ||
                   locationCoordinator.authorizationStatus == .authorizedAlways {
                    MapUserLocationButton(scope: mapScope)
                }
                MapScaleView(scope: mapScope)
            }
            .overlay(alignment: .topTrailing) {
                // Show custom button only when not authorized
                if locationCoordinator.authorizationStatus != .authorizedWhenInUse &&
                   locationCoordinator.authorizationStatus != .authorizedAlways {
                    Button {
                        locationCoordinator.handleLocationButtonTap()
                    } label: {
                        Image(systemName: "location")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.blue)
                            .frame(width: 44, height: 44)
                            .background(.regularMaterial, in: .circle)
                    }
                    .padding(.trailing, 8)
                    .padding(.top, 52)
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

            VStack(spacing: 12) {
                // Center on all button
                Button {
                    withAnimation {
                        viewModel.clearSelection()
                        viewModel.centerOnAllContacts()
                    }
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: .circle)
                }
                .disabled(viewModel.contactsWithLocation.isEmpty)
            }
            .padding()
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

    private func handleAnnotationTap(_ contact: ContactDTO) {
        withAnimation {
            if viewModel.selectedContact?.id == contact.id {
                viewModel.clearSelection()
            } else {
                viewModel.centerOnContact(contact)
            }
        }
    }

    private func navigateToChat(with contact: ContactDTO) {
        viewModel.clearSelection()
        appState.navigateToChat(with: contact)
    }

    private func showContactDetail(_ contact: ContactDTO) {
        selectedContactForDetail = contact
        showingContactDetail = true
    }
}

// MARK: - Contact Detail Sheet

private struct ContactDetailSheet: View {
    let contact: ContactDTO
    let onMessage: () -> Void
    @Environment(\.dismiss) private var dismiss

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
                    Button {
                        dismiss()
                        onMessage()
                    } label: {
                        Label("Send Message", systemImage: "message.fill")
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
        }
        .presentationDetents([.medium, .large])
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
        .environment(AppState())
}

#Preview("Empty Map") {
    MapView()
        .environment(AppState())
}
