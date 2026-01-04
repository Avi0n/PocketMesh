import SwiftUI
import MapKit
import PocketMeshServices

/// Map view displaying contacts with their locations
struct MapView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = MapViewModel()
    @State private var selectedContactForDetail: ContactDTO?
    @Namespace private var mapScope

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
                ToolbarItem(placement: .topBarLeading) {
                    BLEStatusIndicatorView()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    refreshButton
                }
            }
            .task {
                appState.locationService.requestPermissionIfNeeded()
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
                MapUserLocationButton(scope: mapScope)
                MapScaleView(scope: mapScope)
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
