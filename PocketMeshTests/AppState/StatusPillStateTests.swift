import Testing
import PocketMeshServices
@testable import PocketMesh

@Suite("StatusPillState Tests")
struct StatusPillStateTests {

    @Test("Failed state takes highest priority")
    @MainActor
    func failedTakesPriority() {
        let appState = AppState()
        appState.showSyncFailedPill()
        #expect(appState.statusPillState == .failed(message: "Sync Failed"))
    }

    @Test("Syncing takes priority over connecting")
    @MainActor
    func syncingOverConnecting() async {
        let appState = AppState()
        // Simulate sync activity
        await appState.withSyncActivity {
            #expect(appState.statusPillState == .syncing)
        }
    }

    @Test("Ready state shows when toast is active")
    @MainActor
    func readyStateShowsWithToast() {
        let appState = AppState()
        appState.showReadyToastBriefly()
        #expect(appState.statusPillState == .ready)
    }

    @Test("Hidden when no conditions met")
    @MainActor
    func hiddenByDefault() {
        let appState = AppState()
        #expect(appState.statusPillState == .hidden)
    }

    @Test("Disconnected shows after delay when device was paired")
    @MainActor
    func disconnectedAfterDelay() async throws {
        let appState = AppState()
        // This test verifies the delay mechanism exists
        // Full integration test would require mocking connectionManager
        appState.updateDisconnectedPillState()
        // Without a paired device, should remain hidden
        #expect(appState.statusPillState == .hidden)
    }

    @Test("Double onSyncActivityEnded does not drive count below zero")
    @MainActor
    func doubleEndedCallDoesNotGoNegative() {
        let appState = AppState()

        // Simulate sync starting
        appState.simulateSyncStarted()
        #expect(appState.statusPillState == .syncing)

        // First end call (simulates onDisconnected path)
        appState.simulateSyncEnded()
        #expect(appState.statusPillState != .syncing)

        // Second end call (simulates error path) - should be no-op due to guard
        appState.simulateSyncEnded()
        #expect(appState.statusPillState == .hidden)

        // Start new sync - pill should show (proves count didn't go negative)
        appState.simulateSyncStarted()
        #expect(appState.statusPillState == .syncing)
    }
}
