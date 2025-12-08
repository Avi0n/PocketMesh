import SwiftUI
import PocketMeshKit

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
            case .devicePair:
                DevicePairView()
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

        TabView(selection: $appState.selectedTab) {
            Tab("Chats", systemImage: "message.fill", value: 0) {
                ChatsListView()
            }

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
