import PocketMeshKit
import SwiftData
import SwiftUI

@main
struct PocketMeshApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appCoordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appCoordinator)
                .modelContainer(PersistenceController.shared.container)
                .onAppear {
                    appCoordinator.initialize()

                    // Make coordinator accessible to AppDelegate
                    appDelegate.appCoordinator = appCoordinator
                }
        }
    }
}
