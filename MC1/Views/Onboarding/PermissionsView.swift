import SwiftUI
import CoreLocation

/// Second screen of onboarding - requests necessary permissions
struct PermissionsView: View {
    @Environment(\.appState) private var appState
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

                Text(L10n.Onboarding.Permissions.title)
                    .font(.largeTitle)
                    .bold()

                Text(L10n.Onboarding.Permissions.subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(.top, 40)

            Spacer()

            // Permission cards
            LiquidGlassContainer(spacing: 20) {
                VStack(spacing: 16) {
                    PermissionCard(
                        icon: "bell.fill",
                        title: L10n.Onboarding.Permissions.Notifications.title,
                        description: L10n.Onboarding.Permissions.Notifications.description,
                        isGranted: coordinator.notificationAuthorization == .authorized,
                        isDenied: coordinator.notificationAuthorization == .denied,
                        action: coordinator.requestNotifications
                    )

                    PermissionCard(
                        icon: "location.fill",
                        title: L10n.Onboarding.Permissions.Location.title,
                        description: L10n.Onboarding.Permissions.Location.description,
                        isGranted: coordinator.locationAuthorization == .authorizedWhenInUse || coordinator.locationAuthorization == .authorizedAlways,
                        isDenied: coordinator.locationAuthorization == .denied,
                        action: {
                            if coordinator.locationAuthorization == .denied {
                                showingLocationAlert = true
                            } else {
                                coordinator.requestLocation()
                            }
                        }
                    )
                }
            }
            .padding(.horizontal)

            Spacer()

            // Navigation buttons
            VStack(spacing: 12) {
                Button {
                    appState.onboarding.onboardingPath.append(.deviceScan)
                } label: {
                    Text(allPermissionsGranted ? L10n.Onboarding.Permissions.continue : L10n.Onboarding.Permissions.skipForNow)
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .liquidGlassProminentButtonStyle()

                Button {
                    appState.onboarding.onboardingPath.removeLast()
                } label: {
                    Text(L10n.Onboarding.Permissions.back)
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
        .alert(L10n.Onboarding.Permissions.LocationAlert.title, isPresented: $showingLocationAlert) {
            Button(L10n.Onboarding.Permissions.LocationAlert.openSettings) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            Button(L10n.Localizable.Common.cancel, role: .cancel) { }
        } message: {
            Text(L10n.Onboarding.Permissions.LocationAlert.message)
        }
    }

    private var allPermissionsGranted: Bool {
        let notificationsGranted = coordinator.notificationAuthorization == .authorized
        let locationGranted = coordinator.locationAuthorization == .authorizedWhenInUse || coordinator.locationAuthorization == .authorizedAlways
        return notificationsGranted && locationGranted
    }
}

#Preview {
    PermissionsView()
        .environment(\.appState, AppState())
}
