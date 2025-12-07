import SwiftUI
@preconcurrency import CoreBluetooth
@preconcurrency import CoreLocation
import UserNotifications

// MARK: - Permissions Coordinator

/// Coordinator for managing Bluetooth, Location, and Notification permission requests and state observation.
/// Uses delegate callbacks to update permission state immediately when user responds.
@MainActor
@Observable
private final class PermissionsCoordinator: NSObject, CBCentralManagerDelegate, CLLocationManagerDelegate {
    var bluetoothAuthorization: CBManagerAuthorization = .notDetermined
    var locationAuthorization: CLAuthorizationStatus = .notDetermined
    var notificationAuthorization: UNAuthorizationStatus = .notDetermined

    private var centralManager: CBCentralManager?
    private var locationManager: CLLocationManager?
    private let bluetoothQueue = DispatchQueue(label: "com.pocketmesh.permissions.bluetooth")

    override init() {
        super.init()
        bluetoothAuthorization = CBCentralManager.authorization
        // Create location manager early to check current authorization
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationAuthorization = locationManager?.authorizationStatus ?? .notDetermined

        // Check notification authorization
        Task {
            await checkNotificationAuthorization()
        }
    }

    func requestBluetooth() {
        if centralManager == nil {
            // Use a dedicated queue (not main) to avoid synchronous callbacks on MainActor
            // The delegate will dispatch back to main actor as needed
            centralManager = CBCentralManager(delegate: self, queue: bluetoothQueue)
        }
    }

    func requestLocation() {
        locationManager?.requestWhenInUseAuthorization()
    }

    func requestNotifications() {
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                    options: [.alert, .sound, .badge]
                )
                notificationAuthorization = granted ? .authorized : .denied
            } catch {
                notificationAuthorization = .denied
            }
        }
    }

    func checkPermissions() {
        bluetoothAuthorization = CBCentralManager.authorization
        if let lm = locationManager {
            locationAuthorization = lm.authorizationStatus
        }
        Task {
            await checkNotificationAuthorization()
        }
    }

    private func checkNotificationAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationAuthorization = settings.authorizationStatus
    }

    // MARK: - CBCentralManagerDelegate

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            self.bluetoothAuthorization = CBCentralManager.authorization
        }
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.locationAuthorization = status
        }
    }
}

// MARK: - Permissions View

/// Second screen of onboarding - requests necessary permissions
struct PermissionsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var coordinator = PermissionsCoordinator()
    @State private var showingLocationAlert = false

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
                    icon: "antenna.radiowaves.left.and.right",
                    title: "Bluetooth",
                    description: "Connect to MeshCore radio devices",
                    isGranted: coordinator.bluetoothAuthorization == .allowedAlways,
                    isDenied: coordinator.bluetoothAuthorization == .denied,
                    action: coordinator.requestBluetooth
                )

                PermissionCard(
                    icon: "bell.fill",
                    title: "Notifications",
                    description: "Receive alerts for new messages",
                    isGranted: coordinator.notificationAuthorization == .authorized,
                    isDenied: coordinator.notificationAuthorization == .denied,
                    action: coordinator.requestNotifications
                )

                PermissionCard(
                    icon: "location.fill",
                    title: "Location",
                    description: "Share your location with mesh contacts (optional)",
                    isGranted: coordinator.locationAuthorization == .authorizedWhenInUse || coordinator.locationAuthorization == .authorizedAlways,
                    isDenied: coordinator.locationAuthorization == .denied,
                    isOptional: true,
                    action: {
                        if coordinator.locationAuthorization == .denied {
                            showingLocationAlert = true
                        } else {
                            coordinator.requestLocation()
                        }
                    }
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
                .disabled(!canProceed && coordinator.bluetoothAuthorization == .notDetermined)

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
        .onChange(of: scenePhase) {
            if scenePhase == .active {
                coordinator.checkPermissions()
            }
        }
        .alert("Location Permission", isPresented: $showingLocationAlert) {
            Button("Open Settings") {
                if let url = URL(string: "app-settings:") {
                    openURL(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Location permission was previously denied. Please enable it in Settings to share your location with mesh contacts.")
        }
    }

    private var canProceed: Bool {
        coordinator.bluetoothAuthorization == .allowedAlways
    }
}

// MARK: - Permission Card

private struct PermissionCard: View {
    @Environment(\.openURL) private var openURL

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
                    if let url = URL(string: "app-settings:") {
                        openURL(url)
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
