import SwiftUI
import PocketMeshServices

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var appState = appState

        Group {
            if appState.hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .animation(.default, value: appState.hasCompletedOnboarding)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                appState.handleBecameActive()
            }
        }
        .alert("Connection Failed", isPresented: $appState.showingConnectionFailedAlert) {
            if appState.failedPairingDeviceID != nil {
                // Wrong PIN scenario - offer to remove and retry
                Button("Remove & Try Again") {
                    appState.removeFailedPairingAndRetry()
                }
                Button("Cancel", role: .cancel) {
                    appState.failedPairingDeviceID = nil
                }
            } else if appState.pendingReconnectDeviceID != nil {
                Button("Try Again") {
                    Task {
                        if let deviceID = appState.pendingReconnectDeviceID {
                            try? await appState.connectionManager.connect(to: deviceID)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {
                    appState.pendingReconnectDeviceID = nil
                }
            } else {
                Button("OK", role: .cancel) { }
            }
        } message: {
            Text(appState.connectionFailedMessage ?? "Unable to connect to device.")
        }
        .alert(
            "Could Not Connect",
            isPresented: Binding(
                get: { appState.otherAppWarningDeviceID != nil },
                set: { if !$0 { appState.otherAppWarningDeviceID = nil } }
            )
        ) {
            Button("OK") {
                appState.cancelOtherAppWarning()
            }
        } message: {
            Text("Ensure no other app is connected to the device, then try again.")
        }
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        NavigationStack(path: $appState.onboardingPath) {
            WelcomeView()
                .navigationDestination(for: OnboardingStep.self) { step in
                    switch step {
                    case .welcome:
                        WelcomeView()
                    case .permissions:
                        PermissionsView()
                    case .deviceScan:
                        DeviceScanView()
                    case .radioPreset:
                        RadioPresetOnboardingView()
                    }
                }
        }
    }
}

// MARK: - Main Tab View

struct MainTabView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        ZStack(alignment: .top) {
            TabView(selection: $appState.selectedTab) {
            Tab("Chats", systemImage: "message.fill", value: 0) {
                ChatsView()
            }
            .badge(appState.services?.notificationService.badgeCount ?? 0)

            Tab("Nodes", systemImage: "flipphone", value: 1) {
                ContactsListView()
            }

            Tab("Map", systemImage: "map.fill", value: 2) {
                MapView()
            }

            Tab("Tools", systemImage: "wrench.and.screwdriver", value: 3) {
                ToolsView()
            }

            Tab("Settings", systemImage: "gear", value: 4) {
                SettingsView()
            }
        }

            if appState.shouldShowSyncingPill || appState.connectionState == .connecting {
                SyncingPillView(
                    phase: appState.currentSyncPhase,
                    connectionState: appState.connectionState
                )
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(duration: 0.3), value: appState.shouldShowSyncingPill || appState.connectionState == .connecting)
            }
        }
        .onChange(of: appState.selectedTab) { _, newTab in
            // Donate pending flood advert tip when returning to a valid tab
            if appState.pendingFloodAdvertTipDonation && (newTab == 0 || newTab == 1 || newTab == 2) {
                Task {
                    await appState.donateFloodAdvertTipIfOnValidTab()
                }
            }
        }
    }
}

#Preview("Content View - Onboarding") {
    ContentView()
        .environment(AppState())
}

#Preview("Content View - Main App") {
    let appState = AppState()
    appState.hasCompletedOnboarding = true
    return ContentView()
        .environment(appState)
}
