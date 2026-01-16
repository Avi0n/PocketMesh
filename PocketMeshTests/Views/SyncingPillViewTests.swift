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
                showsDisconnectedWarning: true,
                isFailure: false,
                failureText: "Sync Failed"
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
                showsDisconnectedWarning: false,
                isFailure: false,
                failureText: "Sync Failed"
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
                showsDisconnectedWarning: false,
                isFailure: false,
                failureText: "Sync Failed"
            ) == "Syncing contacts"
        )
        #expect(
            SyncingPillView.displayText(
                phase: .channels,
                connectionState: .ready,
                showsConnectedToast: true,
                showsDisconnectedWarning: false,
                isFailure: false,
                failureText: "Sync Failed"
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
                showsDisconnectedWarning: false,
                isFailure: false,
                failureText: "Sync Failed"
            ) == "Connected"
        )

        #expect(
            SyncingPillView.displayText(
                phase: nil,
                connectionState: .connecting,
                showsConnectedToast: true,
                showsDisconnectedWarning: false,
                isFailure: false,
                failureText: "Sync Failed"
            ) == "Connecting..."
        )

        #expect(
            SyncingPillView.displayText(
                phase: .contacts,
                connectionState: .ready,
                showsConnectedToast: true,
                showsDisconnectedWarning: false,
                isFailure: false,
                failureText: "Sync Failed"
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
                showsDisconnectedWarning: false,
                isFailure: false
            ) == true
        )

        #expect(
            SyncingPillView.shouldShowConnectedToast(
                phase: nil,
                connectionState: .disconnected,
                showsConnectedToast: true,
                showsDisconnectedWarning: false,
                isFailure: false
            ) == true
        )

        #expect(
            SyncingPillView.shouldShowConnectedToast(
                phase: nil,
                connectionState: .connected,
                showsConnectedToast: true,
                showsDisconnectedWarning: false,
                isFailure: false
            ) == false
        )

        #expect(
            SyncingPillView.shouldShowConnectedToast(
                phase: .channels,
                connectionState: .ready,
                showsConnectedToast: true,
                showsDisconnectedWarning: false,
                isFailure: false
            ) == false
        )

        #expect(
            SyncingPillView.shouldShowConnectedToast(
                phase: nil,
                connectionState: .ready,
                showsConnectedToast: true,
                showsDisconnectedWarning: true,
                isFailure: false
            ) == false
        )
    }

    @Test("displayText returns failure text when isFailure is true")
    func failureOverridesAll() {
        #expect(
            SyncingPillView.displayText(
                phase: .contacts,
                connectionState: .ready,
                showsConnectedToast: true,
                showsDisconnectedWarning: false,
                isFailure: true,
                failureText: "Custom Error"
            ) == "Custom Error"
        )
    }

    @Test("shouldShowConnectedToast returns false when isFailure is true")
    func failurePreventsConnectedToast() {
        #expect(
            SyncingPillView.shouldShowConnectedToast(
                phase: nil,
                connectionState: .ready,
                showsConnectedToast: true,
                showsDisconnectedWarning: false,
                isFailure: true
            ) == false
        )
    }
}
