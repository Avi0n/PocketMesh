import Testing
@testable import PocketMesh

@Suite("PathManagementViewModel Discovery Timeout")
struct PathManagementViewModelDiscoveryTimeoutTests {
    @Test("Accepts sane firmware timeout")
    func acceptsSaneFirmwareTimeout() {
        let timeout = PathManagementViewModel.sanitizedDiscoveryTimeoutSeconds(suggestedTimeoutMs: 5_000)
        #expect(timeout == 6.0)
    }

    @Test("Falls back on zero timeout")
    func fallsBackOnZeroTimeout() {
        let timeout = PathManagementViewModel.sanitizedDiscoveryTimeoutSeconds(suggestedTimeoutMs: 0)
        #expect(timeout == 30.0)
    }

    @Test("Falls back below minimum timeout")
    func fallsBackBelowMinimumTimeout() {
        let timeout = PathManagementViewModel.sanitizedDiscoveryTimeoutSeconds(suggestedTimeoutMs: 3_000)
        #expect(timeout == 30.0)
    }

    @Test("Falls back for absurdly large timeout")
    func fallsBackForAbsurdlyLargeTimeout() {
        let timeout = PathManagementViewModel.sanitizedDiscoveryTimeoutSeconds(suggestedTimeoutMs: 68_719_800)
        #expect(timeout == 30.0)
    }
}
