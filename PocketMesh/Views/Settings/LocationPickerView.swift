import SwiftUI
import MapKit
import CoreLocation
import PocketMeshServices

/// Map-based location picker for setting node position
struct LocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appState) private var appState

    // Configuration
    private let initialCoordinate: CLLocationCoordinate2D?
    private let onSave: (CLLocationCoordinate2D) async throws -> Void

    // UI State
    @State private var position: MapCameraPosition = .automatic
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var isSaving = false
    @State private var showError: String?

    /// Generic initializer for any location-setting context
    init(
        initialCoordinate: CLLocationCoordinate2D? = nil,
        onSave: @escaping (CLLocationCoordinate2D) async throws -> Void
    ) {
        self.initialCoordinate = initialCoordinate
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MapReader { proxy in
                    Map(position: $position, interactionModes: [.pan, .zoom]) {
                        if let coord = selectedCoordinate {
                            Marker(L10n.Settings.LocationPicker.markerTitle, coordinate: coord)
                                .tint(.blue)
                        }
                    }
                    .onTapGesture { screenLocation in
                        if let coordinate = proxy.convert(screenLocation, from: .local) {
                            selectedCoordinate = coordinate
                        }
                    }
                    .onMapCameraChange { context in
                        visibleRegion = context.region
                    }
                    .mapControls {
                        MapUserLocationButton()
                        MapCompass()
                    }
                }

                // Center crosshair for precise placement
                Image(systemName: "plus")
                    .font(.title)
                    .foregroundStyle(.secondary)

                // Coordinate display and actions
                VStack {
                    Spacer()

                    if let coord = selectedCoordinate {
                        VStack(spacing: 4) {
                            CoordinateText(
                                label: L10n.Settings.LocationPicker.latitude,
                                value: coord.latitude
                            )
                            CoordinateText(
                                label: L10n.Settings.LocationPicker.longitude,
                                value: coord.longitude
                            )
                        }
                        .font(.caption.monospacedDigit())
                        .padding()
                        .background {
                            if #available(iOS 26.0, *) {
                                Color.clear
                            } else {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.ultraThinMaterial)
                            }
                        }
                        .modifier(CoordinateGlassModifier())
                    }

                    Group {
                        if #available(iOS 26.0, *) {
                            GlassEffectContainer {
                                buttonContent
                            }
                        } else {
                            buttonContent
                        }
                    }
                    .padding()
                    .padding(.bottom, 16)
                }
            }
            .navigationTitle(L10n.Settings.LocationPicker.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Localizable.Common.cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Localizable.Common.save) { saveLocation() }
                        .radioDisabled(for: appState.connectionState, or: isSaving)
                }
            }
            .onAppear {
                loadCurrentLocation()
            }
            .onChange(of: appState.locationService.currentLocation) { _, newLocation in
                // Only react if we haven't set a position yet (no saved location case)
                guard let newLocation,
                      initialCoordinate == nil
                        || (initialCoordinate?.latitude == 0 && initialCoordinate?.longitude == 0),
                      position == .automatic else { return }

                position = .region(MKCoordinateRegion(
                    center: newLocation.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
            }
            .errorAlert($showError)
        }
    }

    private func loadCurrentLocation() {
        // Case 1: Existing saved location
        if let coord = initialCoordinate,
           coord.latitude != 0 || coord.longitude != 0 {
            selectedCoordinate = coord
            position = .region(MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
            return
        }

        // Case 2: No saved location, check user location
        let locationService = appState.locationService
        if locationService.isAuthorized {
            if let userLocation = locationService.currentLocation {
                position = .region(MKCoordinateRegion(
                    center: userLocation.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
            } else if !locationService.isRequestingLocation {
                locationService.requestLocation()
            }
        }

        // Case 3: No saved location, no authorization - .automatic handles it
    }

    private func dropPinAtCenter() {
        // Get center from tracked visible region, falling back to position.region
        if let region = visibleRegion {
            selectedCoordinate = region.center
        } else if let region = position.region {
            selectedCoordinate = region.center
        }
    }

    private func saveLocation() {
        let coord = selectedCoordinate ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)

        isSaving = true
        Task {
            do {
                try await onSave(coord)
                dismiss()
            } catch {
                showError = error.localizedDescription
            }
            isSaving = false
        }
    }

    @ViewBuilder
    private var buttonContent: some View {
        HStack(spacing: 12) {
            if selectedCoordinate != nil {
                Button(L10n.Settings.LocationPicker.clearLocation, role: .destructive) {
                    selectedCoordinate = nil
                }
                .modifier(GlassButtonModifier(isProminent: false))
            }

            Button(L10n.Settings.LocationPicker.dropPin) {
                dropPinAtCenter()
            }
            .modifier(GlassButtonModifier(isProminent: true))
        }
    }
}

// MARK: - Local Device Convenience

extension LocationPickerView {
    /// Convenience initializer for local device location setting (Settings screen)
    /// Retry handling for SettingsServiceError is handled at the call site since it requires RetryAlertState
    static func forLocalDevice(appState: AppState) -> LocationPickerView {
        let device = appState.connectedDevice
        let initialCoord = device.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }

        return LocationPickerView(initialCoordinate: initialCoord) { coordinate in
            guard let settingsService = appState.services?.settingsService else {
                throw SettingsServiceError.notConnected
            }
            _ = try await settingsService.setLocationVerified(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude
            )
        }
    }
}

// MARK: - Liquid Glass Modifiers

private struct CoordinateGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: 8))
        } else {
            content
        }
    }
}

private struct GlassButtonModifier: ViewModifier {
    let isProminent: Bool

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if isProminent {
                content
                    .buttonStyle(.glassProminent)
                    .controlSize(.regular)
            } else {
                content
                    .buttonStyle(.glass)
                    .controlSize(.regular)
            }
        } else {
            if isProminent {
                content.buttonStyle(.borderedProminent)
            } else {
                content.buttonStyle(.bordered)
            }
        }
    }
}

private struct CoordinateText: View {
    let label: String
    let value: Double

    var body: some View {
        Text("\(label) \(value, format: .number.precision(.fractionLength(6)))")
    }
}
