import SwiftUI
import CoreBluetooth
import CoreLocation

/// Second screen of onboarding - requests necessary permissions
struct PermissionsView: View {
    @Environment(AppState.self) private var appState
    @State private var bluetoothAuthorization: CBManagerAuthorization = .notDetermined
    @State private var locationAuthorization: CLAuthorizationStatus = .notDetermined
    @State private var showingLocationAlert = false

    private let locationManager = CLLocationManager()

    var body: some View {
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 12) {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.tint)

                Text("Permissions")
                    .font(.largeTitle)
                    .bold()

                Text("PocketMesh needs your permission to work properly")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.top, 40)

            Spacer()

            // Permission cards
            VStack(spacing: 16) {
                PermissionCard(
                    icon: "bluetooth",
                    title: "Bluetooth",
                    description: "Connect to MeshCore radio devices",
                    isGranted: bluetoothAuthorization == .allowedAlways,
                    isDenied: bluetoothAuthorization == .denied,
                    action: requestBluetooth
                )

                PermissionCard(
                    icon: "location.fill",
                    title: "Location",
                    description: "Share your location with mesh contacts (optional)",
                    isGranted: locationAuthorization == .authorizedWhenInUse || locationAuthorization == .authorizedAlways,
                    isDenied: locationAuthorization == .denied,
                    isOptional: true,
                    action: requestLocation
                )
            }
            .padding(.horizontal)

            Spacer()

            // Navigation buttons
            VStack(spacing: 12) {
                Button {
                    withAnimation {
                        appState.onboardingStep = .deviceScan
                    }
                } label: {
                    Text(canProceed ? "Continue" : "Skip for Now")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canProceed && bluetoothAuthorization == .notDetermined)

                Button {
                    withAnimation {
                        appState.onboardingStep = .welcome
                    }
                } label: {
                    Text("Back")
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .onAppear {
            checkPermissions()
        }
        .alert("Location Permission", isPresented: $showingLocationAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Location permission was previously denied. Please enable it in Settings to share your location with mesh contacts.")
        }
    }

    private var canProceed: Bool {
        bluetoothAuthorization == .allowedAlways
    }

    private func checkPermissions() {
        bluetoothAuthorization = CBCentralManager.authorization
        locationAuthorization = locationManager.authorizationStatus
    }

    private func requestBluetooth() {
        // Creating a CBCentralManager triggers the permission prompt
        // The actual manager is managed by BLEService
        let _ = CBCentralManager()

        // Check again after a brief delay
        Task {
            try? await Task.sleep(for: .seconds(1))
            bluetoothAuthorization = CBCentralManager.authorization
        }
    }

    private func requestLocation() {
        if locationAuthorization == .denied {
            showingLocationAlert = true
        } else {
            locationManager.requestWhenInUseAuthorization()

            // Check again after a brief delay
            Task {
                try? await Task.sleep(for: .seconds(1))
                locationAuthorization = locationManager.authorizationStatus
            }
        }
    }
}

// MARK: - Permission Card

private struct PermissionCard: View {
    let icon: String
    let title: String
    let description: String
    let isGranted: Bool
    let isDenied: Bool
    var isOptional: Bool = false
    let action: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(iconColor)
                .frame(width: 44, height: 44)
                .background(iconColor.opacity(0.1), in: .circle)

            // Text
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title)
                        .font(.headline)

                    if isOptional {
                        Text("Optional")
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.2), in: .capsule)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Status/Action
            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
            } else if isDenied {
                Button("Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button("Allow") {
                    action()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
    }

    private var iconColor: Color {
        if isGranted {
            return .green
        } else if isDenied {
            return .orange
        } else {
            return .accentColor
        }
    }
}

#Preview {
    PermissionsView()
        .environment(AppState())
}
