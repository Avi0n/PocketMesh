import Testing
import PocketMeshServices
@testable import PocketMesh

@Suite("SyncingPillView Tests")
struct SyncingPillViewTests {
    @Test("displayText returns Disconnected when warning visible")
    func disconnectedWarningOverridesEverything() {
        #expect(
            SyncingPillView.displayText(
                phase: .contacts,
                connectionState: .connecting,
                showsConnectedToast: true,
                showsDisconnectedWarning: true
            ) == "Disconnected"
        )
    }

    @Test("displayText prefers Connecting over sync phases")
    func connectingOverridesSync() {
        #expect(
            SyncingPillView.displayText(
                phase: .channels,
                connectionState: .connected,
                showsConnectedToast: false,
                showsDisconnectedWarning: false
            ) == "Connecting..."
        )
    }

    @Test("displayText shows sync phase when ready")
    func syncPhaseTexts() {
        #expect(
            SyncingPillView.displayText(
                phase: .contacts,
                connectionState: .ready,
                showsConnectedToast: true,
                showsDisconnectedWarning: false
            ) == "Syncing contacts"
        )
        #expect(
            SyncingPillView.displayText(
                phase: .channels,
                connectionState: .ready,
                showsConnectedToast: true,
                showsDisconnectedWarning: false
            ) == "Syncing channels"
        )
    }

    @Test("displayText shows Connected toast only when eligible")
    func connectedToastEligibility() {
        #expect(
            SyncingPillView.displayText(
                phase: nil,
                connectionState: .ready,
                showsConnectedToast: true,
                showsDisconnectedWarning: false
            ) == "Connected"
        )

        #expect(
            SyncingPillView.displayText(
                phase: nil,
                connectionState: .connecting,
                showsConnectedToast: true,
                showsDisconnectedWarning: false
            ) == "Connecting..."
        )

        #expect(
            SyncingPillView.displayText(
                phase: .contacts,
                connectionState: .ready,
                showsConnectedToast: true,
                showsDisconnectedWarning: false
            ) == "Syncing contacts"
        )
    }

    @Test("shouldShowConnectedToast returns true only when ready/disconnected")
    func shouldShowConnectedToastOnlyWhenStable() {
        #expect(
            SyncingPillView.shouldShowConnectedToast(
                phase: nil,
                connectionState: .ready,
                showsConnectedToast: true,
                showsDisconnectedWarning: false
            ) == true
        )

        #expect(
            SyncingPillView.shouldShowConnectedToast(
                phase: nil,
                connectionState: .disconnected,
                showsConnectedToast: true,
                showsDisconnectedWarning: false
            ) == true
        )

        #expect(
            SyncingPillView.shouldShowConnectedToast(
                phase: nil,
                connectionState: .connected,
                showsConnectedToast: true,
                showsDisconnectedWarning: false
            ) == false
        )

        #expect(
            SyncingPillView.shouldShowConnectedToast(
                phase: .channels,
                connectionState: .ready,
                showsConnectedToast: true,
                showsDisconnectedWarning: false
            ) == false
        )

        #expect(
            SyncingPillView.shouldShowConnectedToast(
                phase: nil,
                connectionState: .ready,
                showsConnectedToast: true,
                showsDisconnectedWarning: true
            ) == false
        )
    }
}
