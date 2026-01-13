import SwiftUI
import MapKit
import PocketMeshServices

/// Map view displaying contacts with their locations
struct MapView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = MapViewModel()
    @State private var selectedContactForDetail: ContactDTO?

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
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                }
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
                }
            )
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
        VStack(spacing: 0) {
            // User location button (custom since we can't use MapUserLocationButton without scope)
            Button {
                centerOnUserLocation()
            } label: {
                Image(systemName: "location.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Center on my location")

            Divider()
                .frame(width: 36)

            // Layers button
            Button {
                withAnimation(.spring(response: 0.3)) {
                    viewModel.showingLayersMenu.toggle()
                }
            } label: {
                Image(systemName: "square.3.layers.3d.down.right")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Map layers")

            Divider()
                .frame(width: 36)

            // Labels toggle button
            Button {
                withAnimation {
                    viewModel.showLabels.toggle()
                }
            } label: {
                Image(systemName: "text.rectangle.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(viewModel.showLabels ? .blue : .primary)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(viewModel.showLabels ? "Hide labels" : "Show labels")

            Divider()
                .frame(width: 36)

            // Center on all button
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
        .liquidGlass(in: .rect(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        .padding()
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
        selectedContactForDetail = contact
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
