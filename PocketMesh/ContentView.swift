import SwiftUI
import PocketMeshServices

struct ContentView: View {
    @Environment(\.appState) private var appState
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
        .alert(L10n.Localizable.Alert.ConnectionFailed.title, isPresented: $appState.showingConnectionFailedAlert) {
            if appState.failedPairingDeviceID != nil {
                // Wrong PIN scenario - offer to remove and retry
                Button(L10n.Localizable.Alert.ConnectionFailed.removeAndRetry) {
                    appState.removeFailedPairingAndRetry()
                }
                Button(L10n.Localizable.Common.cancel, role: .cancel) {
                    appState.failedPairingDeviceID = nil
                }
            } else if appState.pendingReconnectDeviceID != nil {
                Button(L10n.Localizable.Common.tryAgain) {
                    Task {
                        if let deviceID = appState.pendingReconnectDeviceID {
                            try? await appState.connectionManager.connect(to: deviceID, forceReconnect: true)
                        }
                    }
                }
                Button(L10n.Localizable.Common.cancel, role: .cancel) {
                    appState.pendingReconnectDeviceID = nil
                }
            } else {
                Button(L10n.Localizable.Common.ok, role: .cancel) { }
            }
        } message: {
            Text(appState.connectionFailedMessage ?? L10n.Localizable.Alert.ConnectionFailed.defaultMessage)
        }
        .alert(
            L10n.Localizable.Alert.CouldNotConnect.title,
            isPresented: Binding(
                get: { appState.otherAppWarningDeviceID != nil },
                set: { if !$0 { appState.otherAppWarningDeviceID = nil } }
            )
        ) {
            Button(L10n.Localizable.Common.ok) {
                appState.cancelOtherAppWarning()
            }
        } message: {
            Text(L10n.Localizable.Alert.CouldNotConnect.otherAppMessage)
        }
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @Environment(\.appState) private var appState

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
    @Environment(\.appState) private var appState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingDeviceSelection = false
    @State private var displayedPillState: StatusPillState = .hidden

    private var topPillPadding: CGFloat {
        horizontalSizeClass == .regular ? 56 : 8
    }

    private var pillAnimation: Animation {
        if reduceMotion { return .linear(duration: 0) }

        switch appState.statusPillState {
        case .ready:
            return .spring(duration: 0.4, bounce: 0.15)
        case .failed, .disconnected:
            return .spring(duration: 0.35, bounce: 0.2)
        default:
            return .spring(duration: 0.4)
        }
    }

    var body: some View {
        @Bindable var appState = appState

        ZStack(alignment: .top) {
            TabView(selection: $appState.selectedTab) {
            Tab(L10n.Localizable.Tabs.chats, systemImage: "message.fill", value: 0) {
                ChatsView()
            }
            .badge(appState.services?.notificationService.badgeCount ?? 0)

            Tab(L10n.Localizable.Tabs.nodes, systemImage: "flipphone", value: 1) {
                ContactsListView()
            }

            Tab(L10n.Localizable.Tabs.map, systemImage: "map.fill", value: 2) {
                MapView()
            }

            Tab(L10n.Localizable.Tabs.tools, systemImage: "wrench.and.screwdriver", value: 3) {
                ToolsView()
            }

            Tab(L10n.Localizable.Tabs.settings, systemImage: "gear", value: 4) {
                SettingsView()
            }
        }

            SyncingPillView(
                state: displayedPillState,
                onDisconnectedTap: { showingDeviceSelection = true }
            )
            .animation(.spring(duration: 0.3), value: displayedPillState)
            .padding(.top, topPillPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .offset(y: appState.statusPillState == .hidden ? -100 : 0)
            .opacity(appState.statusPillState == .hidden ? 0 : 1)
            .animation(pillAnimation, value: appState.statusPillState)
            .allowsHitTesting(appState.statusPillState != .hidden)
        }
        .onChange(of: appState.statusPillState, initial: true) { _, new in
            if new != .hidden {
                withAnimation(pillAnimation) {
                    displayedPillState = new
                }
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
        .sheet(isPresented: $showingDeviceSelection) {
            DeviceSelectionSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }
}

#Preview("Content View - Onboarding") {
    ContentView()
        .environment(\.appState, AppState())
}

#Preview("Content View - Main App") {
    let appState = AppState()
    appState.hasCompletedOnboarding = true
    return ContentView()
        .environment(\.appState, appState)
}
