import SwiftUI
import TipKit
import PocketMeshServices
#if DEBUG
import DataScoutCompanion
#endif

@main
struct PocketMeshApp: App {
    @State private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

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
                    await appState.initialize()
                    #if DEBUG
                    // ConnectionService.shared.startAdvertising(container: appState.modelContainer)
                    #endif
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
