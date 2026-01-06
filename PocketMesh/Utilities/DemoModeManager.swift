import SwiftUI

@MainActor
@Observable
final class DemoModeManager {
    static let shared = DemoModeManager()

    @ObservationIgnored
    @AppStorage("isDemoModeUnlocked") var isUnlocked: Bool = false

    @ObservationIgnored
    @AppStorage("isDemoModeEnabled") var isEnabled: Bool = false

    private init() {}

    func unlock() {
        isUnlocked = true
        isEnabled = true
    }
}
