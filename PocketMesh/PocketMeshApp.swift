import SwiftUI
import PocketMeshKit

@main
struct PocketMeshApp: App {
    @State private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .task {
                    await appState.initializeBLE()
                }
                .onChange(of: scenePhase) { oldPhase, newPhase in
                    handleScenePhaseChange(from: oldPhase, to: newPhase)
                }
        }
    }

    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            Task {
                await appState.handleReturnToForeground()
            }
        case .background:
            appState.handleEnterBackground()
        case .inactive:
            break
        @unknown default:
            break
        }
    }
}
