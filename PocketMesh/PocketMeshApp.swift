import SwiftUI
import SwiftData
import TipKit
import PocketMeshServices

@main
struct PocketMeshApp: App {
    @State private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    #if DEBUG
    /// Whether running in screenshot mode for App Store screenshots
    private var isScreenshotMode: Bool {
        ProcessInfo.processInfo.arguments.contains("-screenshotMode")
    }
    #endif

    init() {
        let container = try! PersistenceStore.createContainer()
        _appState = State(initialValue: AppState(modelContainer: container))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .task {
                    try? Tips.configure([
                        .displayFrequency(.immediate)
                    ])

                    #if DEBUG
                    if isScreenshotMode {
                        await setupScreenshotMode()
                    } else {
                        await appState.initialize()
                    }
                    #else
                    await appState.initialize()
                    #endif
                }
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    handleScenePhaseChange(from: oldPhase, to: newPhase)
                }
        }
    }

    #if DEBUG && targetEnvironment(simulator)
    /// Sets up the app for App Store screenshot capture.
    /// Bypasses onboarding and auto-connects to simulator with mock data.
    @MainActor
    private func setupScreenshotMode() async {
        // Bypass onboarding
        appState.hasCompletedOnboarding = true

        // Persist simulator device ID for auto-reconnect
        UserDefaults.standard.set(
            MockDataProvider.simulatorDeviceID.uuidString,
            forKey: "com.pocketmesh.lastConnectedDeviceID"
        )

        // Initialize app (will auto-connect to simulator device)
        await appState.initialize()
    }
    #elseif DEBUG
    @MainActor
    private func setupScreenshotMode() async {
        // Screenshot mode only works in simulator
        await appState.initialize()
    }
    #endif

    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            Task {
                await appState.handleReturnToForeground()
            }
        case .background:
            appState.handleEnterBackground()
            Task {
                await appState.services?.debugLogBuffer.flush()
            }
        case .inactive:
            break
        @unknown default:
            break
        }
    }
}
