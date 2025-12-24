import SwiftUI
import PocketMeshServices

struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.hasCompletedOnboarding {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .animation(.default, value: appState.hasCompletedOnboarding)
    }
}

// MARK: - Onboarding View

struct OnboardingView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            switch appState.onboardingStep {
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
        .transition(.asymmetric(
            insertion: .move(edge: .trailing),
            removal: .move(edge: .leading)
        ))
        .animation(.default, value: appState.onboardingStep)
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
                ChatsListView()
            }
            .badge(appState.services?.notificationService.badgeCount ?? 0)

            Tab("Contacts", systemImage: "person.2.fill", value: 1) {
                ContactsListView()
            }

            Tab("Map", systemImage: "map.fill", value: 2) {
                MapView()
            }

            Tab("Settings", systemImage: "gear", value: 3) {
                SettingsView()
            }
        }

            if appState.shouldShowSyncingPill {
                SyncingPillView()
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.spring(duration: 0.3), value: appState.shouldShowSyncingPill)
            }
        }
        .alert("Connection Failed", isPresented: $appState.showingConnectionFailedAlert) {
            if appState.pendingReconnectDeviceID != nil {
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
    }
}

// MARK: - Placeholder Views

struct ChatsPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No Conversations",
                systemImage: "message",
                description: Text("Start a conversation with a contact")
            )
            .navigationTitle("Chats")
        }
    }
}

struct ContactsPlaceholderView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No Contacts",
                systemImage: "person.2",
                description: Text("Contacts will appear when discovered on the mesh network")
            )
            .navigationTitle("Contacts")
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
