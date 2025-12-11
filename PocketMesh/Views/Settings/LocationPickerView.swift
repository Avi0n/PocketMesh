import SwiftUI
import MapKit
import PocketMeshKit

/// Map-based location picker for setting node position
struct LocationPickerView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var position: MapCameraPosition = .automatic
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var isSaving = false
    @State private var showError: String?
    @State private var retryAlert = RetryAlertState()

    var body: some View {
        NavigationStack {
            ZStack {
                MapReader { proxy in
                    Map(position: $position, interactionModes: [.pan, .zoom]) {
                        if let coord = selectedCoordinate {
                            Marker("Node Location", coordinate: coord)
                                .tint(.blue)
                        }
                    }
                    .onTapGesture { screenLocation in
                        if let coordinate = proxy.convert(screenLocation, from: .local) {
                            selectedCoordinate = coordinate
                        }
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
                            Text("Latitude: \(coord.latitude, format: .number.precision(.fractionLength(6)))")
                            Text("Longitude: \(coord.longitude, format: .number.precision(.fractionLength(6)))")
                        }
                        .font(.caption.monospacedDigit())
                        .padding()
                        .background(.ultraThinMaterial, in: .rect(cornerRadius: 8))
                    }

                    Button("Drop Pin at Center") {
                        dropPinAtCenter()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding()
                }
            }
            .navigationTitle("Set Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveLocation() }
                        .disabled(selectedCoordinate == nil || isSaving)
                }
            }
            .onAppear {
                loadCurrentLocation()
            }
            .errorAlert($showError)
            .retryAlert(retryAlert)
        }
    }

    private func loadCurrentLocation() {
        guard let device = appState.connectedDevice else { return }

        if device.latitude != 0 || device.longitude != 0 {
            let coord = CLLocationCoordinate2D(latitude: device.latitude, longitude: device.longitude)
            selectedCoordinate = coord
            position = .region(MKCoordinateRegion(
                center: coord,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        }
    }

    private func dropPinAtCenter() {
        // Get center from current camera position
        if let region = position.region {
            selectedCoordinate = region.center
        }
    }

    private func saveLocation() {
        guard let coord = selectedCoordinate else { return }

        isSaving = true
        Task {
            do {
                let (deviceInfo, selfInfo) = try await appState.withSyncActivity {
                    try await appState.settingsService.setLocationVerified(
                        latitude: coord.latitude,
                        longitude: coord.longitude
                    )
                }
                appState.updateDeviceInfo(deviceInfo, selfInfo)
                retryAlert.reset()
                dismiss()
            } catch let error as SettingsServiceError where error.isRetryable {
                retryAlert.show(
                    message: error.localizedDescription ?? "Please ensure device is connected and try again.",
                    onRetry: { saveLocation() },
                    onMaxRetriesExceeded: { dismiss() }
                )
            } catch {
                showError = error.localizedDescription
            }
            isSaving = false
        }
    }
}
