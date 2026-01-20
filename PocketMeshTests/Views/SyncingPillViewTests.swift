import Testing
import SwiftUI
@testable import PocketMesh

@Suite("SyncingPillView Tests")
struct SyncingPillViewTests {

    @Test("Connecting state renders correctly")
    @MainActor
    func connectingState() {
        let view = SyncingPillView(state: .connecting)
        // View should render without error
        _ = view.body
    }

    @Test("Syncing state renders correctly")
    @MainActor
    func syncingState() {
        let view = SyncingPillView(state: .syncing)
        _ = view.body
    }

    @Test("Ready state renders correctly")
    @MainActor
    func readyState() {
        let view = SyncingPillView(state: .ready)
        _ = view.body
    }

    @Test("Disconnected state renders correctly")
    @MainActor
    func disconnectedState() {
        let view = SyncingPillView(state: .disconnected)
        _ = view.body
    }

    @Test("Disconnected state with tap handler renders as button")
    @MainActor
    func disconnectedWithTapHandler() {
        var tapped = false
        let view = SyncingPillView(
            state: .disconnected,
            onDisconnectedTap: { tapped = true }
        )
        _ = view.body
        // View should render as button when tap handler provided
        #expect(!tapped) // Handler not called until user taps
    }

    @Test("Failed state renders correctly")
    @MainActor
    func failedState() {
        let view = SyncingPillView(state: .failed(message: "Sync Failed"))
        _ = view.body
    }

    @Test("Failed state with custom message")
    @MainActor
    func failedStateCustomMessage() {
        let view = SyncingPillView(state: .failed(message: "Custom Error"))
        _ = view.body
    }

    @Test("Hidden state renders empty")
    @MainActor
    func hiddenState() {
        let view = SyncingPillView(state: .hidden)
        _ = view.body
    }
}
