import Testing
import Foundation
@testable import PocketMesh
@testable import PocketMeshServices
@testable import MeshCore

// MARK: - Test Helpers

private func createTestSavedPath(runs: [TracePathRunDTO]) -> SavedTracePathDTO {
    SavedTracePathDTO(
        id: UUID(),
        deviceID: UUID(),
        name: "Test Path",
        pathBytes: Data([0x01, 0x02, 0x01]),
        createdDate: Date(),
        runs: runs
    )
}

private func createTestRun(date: Date, roundTripMs: Int = 100, success: Bool = true) -> TracePathRunDTO {
    TracePathRunDTO(
        id: UUID(),
        date: date,
        success: success,
        roundTripMs: success ? roundTripMs : 0,
        hopsSNR: success ? [5.0, 3.0, -2.0] : []
    )
}

private func createTestContact() -> ContactDTO {
    let contact = Contact(
        id: UUID(),
        deviceID: UUID(),
        publicKey: Data([0xAB] + Array(repeating: UInt8(0x00), count: 31)),
        name: "Test Repeater",
        typeRawValue: ContactType.repeater.rawValue,
        flags: 0,
        outPathLength: 0,
        outPath: Data(),
        lastAdvertTimestamp: 0,
        latitude: 0,
        longitude: 0,
        lastModified: 0
    )
    return ContactDTO(from: contact)
}

// MARK: - Path Edit Clears Saved Path Tests

@Suite("Path Edit Clears Saved Path")
@MainActor
struct PathEditClearsSavedPathTests {

    @Test("addRepeater clears activeSavedPath")
    func addRepeaterClearsActiveSavedPath() {
        let viewModel = TracePathViewModel()
        viewModel.activeSavedPath = createTestSavedPath(runs: [])

        #expect(viewModel.activeSavedPath != nil)

        viewModel.addRepeater(createTestContact())

        #expect(viewModel.activeSavedPath == nil)
    }

    @Test("removeRepeater clears activeSavedPath")
    func removeRepeaterClearsActiveSavedPath() {
        let viewModel = TracePathViewModel()
        viewModel.activeSavedPath = createTestSavedPath(runs: [])
        viewModel.addRepeater(createTestContact())
        // Re-set since addRepeater clears it
        viewModel.activeSavedPath = createTestSavedPath(runs: [])

        #expect(viewModel.activeSavedPath != nil)

        viewModel.removeRepeater(at: 0)

        #expect(viewModel.activeSavedPath == nil)
    }

    @Test("moveRepeater clears activeSavedPath")
    func moveRepeaterClearsActiveSavedPath() {
        let viewModel = TracePathViewModel()

        // Add two repeaters
        viewModel.addRepeater(createTestContact())
        viewModel.addRepeater(createTestContact())
        viewModel.activeSavedPath = createTestSavedPath(runs: [])

        #expect(viewModel.activeSavedPath != nil)

        viewModel.moveRepeater(from: IndexSet(integer: 0), to: 2)

        #expect(viewModel.activeSavedPath == nil)
    }
}

// MARK: - Previous Run Comparison Tests

@Suite("Previous Run Comparison")
@MainActor
struct PreviousRunComparisonTests {

    @Test("previousRun returns nil when no runs exist")
    func previousRunReturnsNilWhenNoRuns() {
        let viewModel = TracePathViewModel()
        viewModel.activeSavedPath = createTestSavedPath(runs: [])

        #expect(viewModel.previousRun == nil)
    }

    @Test("previousRun returns nil when only one run exists")
    func previousRunReturnsNilWhenOnlyOneRun() {
        let viewModel = TracePathViewModel()
        let run = createTestRun(date: Date())
        viewModel.activeSavedPath = createTestSavedPath(runs: [run])

        #expect(viewModel.previousRun == nil)
    }

    @Test("previousRun returns second-to-last run when two runs exist")
    func previousRunReturnsSecondToLastWithTwoRuns() {
        let viewModel = TracePathViewModel()
        let olderRun = createTestRun(date: Date().addingTimeInterval(-60), roundTripMs: 150)
        let newerRun = createTestRun(date: Date(), roundTripMs: 100)
        viewModel.activeSavedPath = createTestSavedPath(runs: [olderRun, newerRun])

        let previous = viewModel.previousRun
        #expect(previous != nil)
        #expect(previous?.roundTripMs == 150)
    }

    @Test("previousRun returns second-to-last run when multiple runs exist")
    func previousRunReturnsSecondToLastWithMultipleRuns() {
        let viewModel = TracePathViewModel()
        let run1 = createTestRun(date: Date().addingTimeInterval(-120), roundTripMs: 200)
        let run2 = createTestRun(date: Date().addingTimeInterval(-60), roundTripMs: 150)
        let run3 = createTestRun(date: Date(), roundTripMs: 100)
        viewModel.activeSavedPath = createTestSavedPath(runs: [run1, run2, run3])

        let previous = viewModel.previousRun
        #expect(previous != nil)
        #expect(previous?.roundTripMs == 150)  // Second-to-last (run2)
    }

    @Test("previousRun skips failed runs when finding comparison")
    func previousRunSkipsFailedRuns() {
        let viewModel = TracePathViewModel()
        // Oldest: success @ 200ms
        let run1 = createTestRun(date: Date().addingTimeInterval(-120), roundTripMs: 200)
        // Middle: failed (roundTripMs = 0)
        let run2 = createTestRun(date: Date().addingTimeInterval(-60), success: false)
        // Newest: success @ 100ms
        let run3 = createTestRun(date: Date(), roundTripMs: 100)
        viewModel.activeSavedPath = createTestSavedPath(runs: [run1, run2, run3])

        let previous = viewModel.previousRun
        #expect(previous != nil)
        // Should skip the failed run2 and return run1 (200ms)
        #expect(previous?.roundTripMs == 200)
    }

    @Test("previousRun returns nil when only one successful run exists among failures")
    func previousRunReturnsNilWithOnlyOneSuccess() {
        let viewModel = TracePathViewModel()
        let failedRun1 = createTestRun(date: Date().addingTimeInterval(-120), success: false)
        let failedRun2 = createTestRun(date: Date().addingTimeInterval(-60), success: false)
        let successRun = createTestRun(date: Date(), roundTripMs: 100)
        viewModel.activeSavedPath = createTestSavedPath(runs: [failedRun1, failedRun2, successRun])

        // Only one successful run, so no previous successful run exists
        #expect(viewModel.previousRun == nil)
    }
}

// MARK: - Trace Response Hop Parsing Tests

@Suite("Trace Response Hop Parsing")
@MainActor
struct TraceResponseHopParsingTests {

    @Test("handleTraceResponse creates correct hops with sender SNR attribution")
    func singleHopTraceProducesCorrectHops() {
        let viewModel = TracePathViewModel()

        // Create a TraceInfo with one repeater hop + final nil node
        // SNR values: 5.0 = how repeater heard us, 3.0 = how we heard return
        let traceInfo = TraceInfo(
            tag: 12345,
            authCode: 0,
            flags: 0,
            pathLength: 1,
            path: [
                TraceNode(hash: 0xAB, snr: 5.0),   // Repeater received at 5.0 dB
                TraceNode(hash: nil, snr: 3.0)     // We received return at 3.0 dB
            ]
        )

        // Set up pending tag to match
        viewModel.setPendingTagForTesting(12345)
        viewModel.handleTraceResponse(traceInfo, deviceID: nil)

        guard let result = viewModel.result else {
            Issue.record("Result should not be nil")
            return
        }

        #expect(result.success == true)
        #expect(result.hops.count == 3)  // Start + 1 repeater + End

        // Start node gets SNR from first hop (how repeater heard our transmission)
        #expect(result.hops[0].isStartNode == true)
        #expect(result.hops[0].hashBytes == nil)
        #expect(result.hops[0].snr == 5.0)  // Sender attribution: how first hop heard us

        // Intermediate hop gets SNR from next node (how we heard its return)
        #expect(result.hops[1].isStartNode == false)
        #expect(result.hops[1].isEndNode == false)
        #expect(result.hops[1].hashBytes == Data([0xAB]))
        #expect(result.hops[1].snr == 3.0)  // Sender attribution: how end node heard repeater

        // End node has no SNR (no next hop to measure)
        #expect(result.hops[2].isEndNode == true)
        #expect(result.hops[2].hashBytes == nil)
        #expect(result.hops[2].snr == 0)  // No next hop, so no SNR
    }

    @Test("handleTraceResponse creates correct hops for multi-hop trace with sender SNR attribution")
    func multiHopTraceProducesCorrectHops() {
        let viewModel = TracePathViewModel()

        // Path: Start → AA → BB → CC → End
        // SNR values represent what each node recorded when receiving
        let traceInfo = TraceInfo(
            tag: 12345,
            authCode: 0,
            flags: 0,
            pathLength: 3,
            path: [
                TraceNode(hash: 0xAA, snr: 6.0),   // AA heard Start at 6.0 dB
                TraceNode(hash: 0xBB, snr: 4.0),   // BB heard AA at 4.0 dB
                TraceNode(hash: 0xCC, snr: 2.0),   // CC heard BB at 2.0 dB
                TraceNode(hash: nil, snr: -1.0)    // End heard CC at -1.0 dB
            ]
        )

        viewModel.setPendingTagForTesting(12345)
        viewModel.handleTraceResponse(traceInfo, deviceID: nil)

        guard let result = viewModel.result else {
            Issue.record("Result should not be nil")
            return
        }

        #expect(result.hops.count == 5)  // Start + 3 repeaters + End

        // Sender attribution: each node shows how the NEXT hop heard its transmission
        #expect(result.hops[0].snr == 6.0)   // Start: how AA heard us
        #expect(result.hops[1].snr == 4.0)   // AA: how BB heard AA
        #expect(result.hops[2].snr == 2.0)   // BB: how CC heard BB
        #expect(result.hops[3].snr == -1.0)  // CC: how End heard CC
        #expect(result.hops[4].snr == 0)     // End: no next hop

        // Verify all intermediate hops are present
        #expect(result.hops[1].hashBytes == Data([0xAA]))
        #expect(result.hops[2].hashBytes == Data([0xBB]))
        #expect(result.hops[3].hashBytes == Data([0xCC]))
    }

    @Test("handleTraceResponse ignores non-matching tags")
    func ignoresNonMatchingTags() {
        let viewModel = TracePathViewModel()

        let traceInfo = TraceInfo(
            tag: 99999,  // Different tag
            authCode: 0,
            flags: 0,
            pathLength: 1,
            path: [
                TraceNode(hash: 0xAB, snr: 5.0),
                TraceNode(hash: nil, snr: 3.0)
            ]
        )

        viewModel.setPendingTagForTesting(12345)  // Different from traceInfo.tag
        viewModel.handleTraceResponse(traceInfo, deviceID: nil)

        #expect(viewModel.result == nil)
    }
}

// MARK: - Result ID Tests

@Suite("Result ID Behavior")
@MainActor
struct ResultIDBehaviorTests {

    @Test("resultID is set on successful trace")
    func resultIDSetOnSuccess() {
        let viewModel = TracePathViewModel()

        // Simulate successful trace response
        let traceInfo = TraceInfo(
            tag: 12345,
            authCode: 0,
            flags: 0,
            pathLength: 1,
            path: [
                TraceNode(hash: 0xAB, snr: 5.0),
                TraceNode(hash: nil, snr: 3.0)
            ]
        )

        viewModel.setPendingTagForTesting(12345)
        #expect(viewModel.resultID == nil)

        viewModel.handleTraceResponse(traceInfo, deviceID: nil)

        #expect(viewModel.resultID != nil)
    }

    @Test("resultID changes on each successful trace")
    func resultIDChangesOnEachTrace() {
        let viewModel = TracePathViewModel()

        let traceInfo = TraceInfo(
            tag: 12345,
            authCode: 0,
            flags: 0,
            pathLength: 1,
            path: [
                TraceNode(hash: 0xAB, snr: 5.0),
                TraceNode(hash: nil, snr: 3.0)
            ]
        )

        viewModel.setPendingTagForTesting(12345)
        viewModel.handleTraceResponse(traceInfo, deviceID: nil)
        let firstID = viewModel.resultID

        // Run another trace
        viewModel.setPendingTagForTesting(12346)
        let traceInfo2 = TraceInfo(
            tag: 12346,
            authCode: 0,
            flags: 0,
            pathLength: 1,
            path: [
                TraceNode(hash: 0xAB, snr: 5.0),
                TraceNode(hash: nil, snr: 3.0)
            ]
        )
        viewModel.handleTraceResponse(traceInfo2, deviceID: nil)

        #expect(viewModel.resultID != firstID)
    }
}

// MARK: - Error Handling Tests

@Suite("Error Handling")
@MainActor
struct ErrorHandlingTests {

    @Test("setError sets errorMessage")
    func setErrorSetsMessage() {
        let viewModel = TracePathViewModel()

        #expect(viewModel.errorMessage == nil)

        viewModel.setError("Test error")

        #expect(viewModel.errorMessage == "Test error")
    }

    @Test("clearError clears errorMessage")
    func clearErrorClearsMessage() {
        let viewModel = TracePathViewModel()
        viewModel.setError("Test error")

        #expect(viewModel.errorMessage != nil)

        viewModel.clearError()

        #expect(viewModel.errorMessage == nil)
    }

    @Test("setError replaces previous error")
    func setErrorReplacesPrevious() {
        let viewModel = TracePathViewModel()

        viewModel.setError("First error")
        viewModel.setError("Second error")

        #expect(viewModel.errorMessage == "Second error")
    }

    @Test("addRepeater clears error")
    func addRepeaterClearsError() {
        let viewModel = TracePathViewModel()
        viewModel.setError("Test error")

        #expect(viewModel.errorMessage != nil)

        viewModel.addRepeater(createTestContact())

        #expect(viewModel.errorMessage == nil)
    }

    @Test("removeRepeater clears error")
    func removeRepeaterClearsError() {
        let viewModel = TracePathViewModel()
        viewModel.addRepeater(createTestContact())
        viewModel.setError("Test error")

        #expect(viewModel.errorMessage != nil)

        viewModel.removeRepeater(at: 0)

        #expect(viewModel.errorMessage == nil)
    }

    @Test("moveRepeater clears error")
    func moveRepeaterClearsError() {
        let viewModel = TracePathViewModel()
        viewModel.addRepeater(createTestContact())
        viewModel.addRepeater(createTestContact())
        viewModel.setError("Test error")

        #expect(viewModel.errorMessage != nil)

        viewModel.moveRepeater(from: IndexSet(integer: 0), to: 2)

        #expect(viewModel.errorMessage == nil)
    }

    @Test("error auto-clears after delay")
    func errorAutoClearsAfterDelay() async throws {
        let viewModel = TracePathViewModel()
        viewModel.errorAutoClearDelay = .milliseconds(100)

        viewModel.setError("Test error")
        #expect(viewModel.errorMessage != nil)

        // Wait slightly more than the auto-clear delay
        try await Task.sleep(for: .milliseconds(150))

        #expect(viewModel.errorMessage == nil)
    }

    @Test("clearError cancels pending auto-clear")
    func clearErrorCancelsPendingAutoClear() async throws {
        let viewModel = TracePathViewModel()
        viewModel.errorAutoClearDelay = .milliseconds(100)

        viewModel.setError("Test error")

        // Clear error before auto-clear would happen
        viewModel.clearError()

        // Wait for what would have been auto-clear time
        try await Task.sleep(for: .milliseconds(150))

        // Should still be nil (auto-clear was cancelled)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("new setError cancels previous auto-clear timer")
    func newErrorCancelsPreviousTimer() async throws {
        let viewModel = TracePathViewModel()
        viewModel.errorAutoClearDelay = .milliseconds(200)

        // Set first error
        viewModel.setError("First error")

        // Wait 100ms (less than 200ms auto-clear)
        try await Task.sleep(for: .milliseconds(100))

        // Set second error - this should cancel the first timer
        viewModel.setError("Second error")

        // Wait 150ms more (250ms total since first error, but only 150ms since second)
        try await Task.sleep(for: .milliseconds(150))

        // Should still show second error (first timer was cancelled, second hasn't expired)
        #expect(viewModel.errorMessage == "Second error")

        // Wait another 100ms (250ms total since second error)
        try await Task.sleep(for: .milliseconds(100))

        // Now it should be cleared
        #expect(viewModel.errorMessage == nil)
    }
}

// MARK: - Multi-byte Hash Tests

@Suite("Multi-byte Hash Handling")
@MainActor
struct MultiByteHashTests {

    @Test("multi-byte hash produces hop with full hashBytes and nil resolvedName")
    func multiByteHashProducesFullHashBytes() {
        let viewModel = TracePathViewModel()

        let traceInfo = TraceInfo(
            tag: 12345,
            authCode: 0,
            flags: 0,
            pathLength: 1,
            path: [
                TraceNode(hashBytes: Data([0xAB, 0xCD]), snr: 5.0),
                TraceNode(hashBytes: nil, snr: 3.0)
            ]
        )

        viewModel.setPendingTagForTesting(12345)
        viewModel.handleTraceResponse(traceInfo, deviceID: nil)

        guard let result = viewModel.result else {
            Issue.record("Result should not be nil")
            return
        }

        // Intermediate hop should have full 2-byte hash
        #expect(result.hops[1].hashBytes == Data([0xAB, 0xCD]))
        // Multi-byte hash cannot be resolved
        #expect(result.hops[1].resolvedName == nil)
        // Display string shows both bytes
        #expect(result.hops[1].hashDisplayString == "ABCD")
    }

    @Test("single-byte hash still resolves to contact name")
    func singleByteHashResolvesToName() {
        let viewModel = TracePathViewModel()

        let traceInfo = TraceInfo(
            tag: 12345,
            authCode: 0,
            flags: 0,
            pathLength: 1,
            path: [
                TraceNode(hash: 0xAB, snr: 5.0),
                TraceNode(hash: nil, snr: 3.0)
            ]
        )

        viewModel.setPendingTagForTesting(12345)
        viewModel.handleTraceResponse(traceInfo, deviceID: nil)

        guard let result = viewModel.result else {
            Issue.record("Result should not be nil")
            return
        }

        // Single-byte hash stored correctly
        #expect(result.hops[1].hashBytes == Data([0xAB]))
        #expect(result.hops[1].hashDisplayString == "AB")
    }
}

// MARK: - Device ID Validation Tests

@Suite("Device ID Validation")
@MainActor
struct DeviceIDValidationTests {

    @Test("response from different device is ignored")
    func responseFromDifferentDeviceIgnored() {
        let viewModel = TracePathViewModel()
        let pendingDevice = UUID()
        let differentDevice = UUID()

        let traceInfo = TraceInfo(
            tag: 12345,
            authCode: 0,
            flags: 0,
            pathLength: 1,
            path: [
                TraceNode(hash: 0xAB, snr: 5.0),
                TraceNode(hash: nil, snr: 3.0)
            ]
        )

        viewModel.setPendingTagForTesting(12345)
        viewModel.setPendingDeviceIDForTesting(pendingDevice)
        viewModel.handleTraceResponse(traceInfo, deviceID: differentDevice)

        // Result should be nil - response was ignored
        #expect(viewModel.result == nil)
    }

    @Test("response accepted when device IDs match")
    func responseAcceptedWhenDeviceIDsMatch() {
        let viewModel = TracePathViewModel()
        let deviceID = UUID()

        let traceInfo = TraceInfo(
            tag: 12345,
            authCode: 0,
            flags: 0,
            pathLength: 1,
            path: [
                TraceNode(hash: 0xAB, snr: 5.0),
                TraceNode(hash: nil, snr: 3.0)
            ]
        )

        viewModel.setPendingTagForTesting(12345)
        viewModel.setPendingDeviceIDForTesting(deviceID)
        viewModel.handleTraceResponse(traceInfo, deviceID: deviceID)

        #expect(viewModel.result != nil)
        #expect(viewModel.result?.success == true)
    }

    @Test("tag-only matching works when pendingDeviceID is nil")
    func tagOnlyMatchingWhenPendingDeviceIDNil() {
        let viewModel = TracePathViewModel()

        let traceInfo = TraceInfo(
            tag: 12345,
            authCode: 0,
            flags: 0,
            pathLength: 1,
            path: [
                TraceNode(hash: 0xAB, snr: 5.0),
                TraceNode(hash: nil, snr: 3.0)
            ]
        )

        viewModel.setPendingTagForTesting(12345)
        viewModel.setPendingDeviceIDForTesting(nil)
        viewModel.handleTraceResponse(traceInfo, deviceID: UUID())

        // Should accept - pendingDeviceID is nil so skip device check
        #expect(viewModel.result != nil)
    }

    @Test("tag-only matching works when received deviceID is nil")
    func tagOnlyMatchingWhenReceivedDeviceIDNil() {
        let viewModel = TracePathViewModel()

        let traceInfo = TraceInfo(
            tag: 12345,
            authCode: 0,
            flags: 0,
            pathLength: 1,
            path: [
                TraceNode(hash: 0xAB, snr: 5.0),
                TraceNode(hash: nil, snr: 3.0)
            ]
        )

        viewModel.setPendingTagForTesting(12345)
        viewModel.setPendingDeviceIDForTesting(UUID())
        viewModel.handleTraceResponse(traceInfo, deviceID: nil)

        // Should accept - received deviceID is nil so skip device check
        #expect(viewModel.result != nil)
    }
}

// MARK: - Path Capture Tests

@Suite("Path Capture in Result")
@MainActor
struct PathCaptureTests {

    @Test("result contains original path even if outboundPath modified")
    func resultContainsOriginalPath() {
        let viewModel = TracePathViewModel()

        // Set up pending path hash (simulating what runTrace does)
        let originalPath: [UInt8] = [0xAA, 0xBB, 0xAA]
        viewModel.setPendingPathHashForTesting(originalPath)
        viewModel.setPendingTagForTesting(12345)

        let traceInfo = TraceInfo(
            tag: 12345,
            authCode: 0,
            flags: 0,
            pathLength: 1,
            path: [
                TraceNode(hash: 0xAA, snr: 5.0),
                TraceNode(hash: nil, snr: 3.0)
            ]
        )

        viewModel.handleTraceResponse(traceInfo, deviceID: nil)

        guard let result = viewModel.result else {
            Issue.record("Result should not be nil")
            return
        }

        // Result should contain the original path
        #expect(result.tracedPathBytes == originalPath)
        #expect(result.tracedPathString == "AA,BB,AA")
    }

    @Test("canSavePath is false when path modified after trace")
    func canSavePathFalseWhenPathModified() {
        let viewModel = TracePathViewModel()

        // Simulate a completed trace with path [0xAA, 0xAA]
        let originalPath: [UInt8] = [0xAA, 0xAA]
        viewModel.setPendingPathHashForTesting(originalPath)
        viewModel.setPendingTagForTesting(12345)

        let traceInfo = TraceInfo(
            tag: 12345,
            authCode: 0,
            flags: 0,
            pathLength: 1,
            path: [
                TraceNode(hash: 0xAA, snr: 5.0),
                TraceNode(hash: nil, snr: 3.0)
            ]
        )

        viewModel.handleTraceResponse(traceInfo, deviceID: nil)

        // Verify result exists and has correct path
        #expect(viewModel.result?.tracedPathBytes == originalPath)

        // Now modify the outbound path (simulate user adding another hop)
        let contact = Contact(
            id: UUID(),
            deviceID: UUID(),
            publicKey: Data([0xBB] + Array(repeating: UInt8(0x00), count: 31)),
            name: "Different",
            typeRawValue: ContactType.repeater.rawValue,
            flags: 0,
            outPathLength: 0,
            outPath: Data(),
            lastAdvertTimestamp: 0,
            latitude: 0,
            longitude: 0,
            lastModified: 0
        )
        viewModel.addRepeater(ContactDTO(from: contact))

        // fullPathBytes is now different from result.tracedPathBytes
        // canSavePath should be false
        #expect(viewModel.canSavePath == false)
    }

    @Test("canSavePath is true when path unchanged after trace")
    func canSavePathTrueWhenPathUnchanged() {
        let viewModel = TracePathViewModel()

        // Add a repeater first so fullPathBytes is populated
        let contact = Contact(
            id: UUID(),
            deviceID: UUID(),
            publicKey: Data([0xAA] + Array(repeating: UInt8(0x00), count: 31)),
            name: "Repeater",
            typeRawValue: ContactType.repeater.rawValue,
            flags: 0,
            outPathLength: 0,
            outPath: Data(),
            lastAdvertTimestamp: 0,
            latitude: 0,
            longitude: 0,
            lastModified: 0
        )
        viewModel.addRepeater(ContactDTO(from: contact))

        // Get the current full path bytes
        let currentPath = viewModel.fullPathBytes

        // Simulate trace with same path
        viewModel.setPendingPathHashForTesting(currentPath)
        viewModel.setPendingTagForTesting(12345)

        let traceInfo = TraceInfo(
            tag: 12345,
            authCode: 0,
            flags: 0,
            pathLength: 1,
            path: [
                TraceNode(hash: 0xAA, snr: 5.0),
                TraceNode(hash: nil, snr: 3.0)
            ]
        )

        viewModel.handleTraceResponse(traceInfo, deviceID: nil)

        // Path unchanged, result successful - canSavePath should be true
        #expect(viewModel.canSavePath == true)
    }
}

// MARK: - Failure Result Tests

@Suite("Failure Result Path Display")
@MainActor
struct FailureResultTests {

    @Test("timeout result contains attempted path")
    func timeoutResultContainsAttemptedPath() {
        let attemptedPath: [UInt8] = [0xAA, 0xBB, 0xAA]
        let result = TraceResult.timeout(attemptedPath: attemptedPath)

        #expect(result.success == false)
        #expect(result.tracedPathBytes == attemptedPath)
        #expect(result.tracedPathString == "AA,BB,AA")
    }

    @Test("sendFailed result contains attempted path")
    func sendFailedResultContainsAttemptedPath() {
        let attemptedPath: [UInt8] = [0xCC, 0xDD, 0xCC]
        let result = TraceResult.sendFailed("Connection lost", attemptedPath: attemptedPath)

        #expect(result.success == false)
        #expect(result.errorMessage == "Connection lost")
        #expect(result.tracedPathBytes == attemptedPath)
        #expect(result.tracedPathString == "CC,DD,CC")
    }

    @Test("empty path produces empty tracedPathString")
    func emptyPathProducesEmptyString() {
        let result = TraceResult.timeout(attemptedPath: [])

        #expect(result.tracedPathBytes.isEmpty)
        #expect(result.tracedPathString == "")
    }
}
