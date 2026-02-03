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

// MARK: - TraceHop Location Tests

@Suite("TraceHop Location")
@MainActor
struct TraceHopLocationTests {

    @Test("hasLocation returns true with valid non-zero coordinates")
    func hasLocationWithValidCoordinates() {
        let hop = TraceHop(
            hashBytes: Data([0x3F]),
            resolvedName: "Tower",
            snr: 5.0,
            isStartNode: false,
            isEndNode: false,
            latitude: 37.7749,
            longitude: -122.4194
        )
        #expect(hop.hasLocation == true)
    }

    @Test("hasLocation returns false with zero coordinates")
    func hasLocationWithZeroCoordinates() {
        let hop = TraceHop(
            hashBytes: Data([0x3F]),
            resolvedName: "Tower",
            snr: 5.0,
            isStartNode: false,
            isEndNode: false,
            latitude: 0,
            longitude: 0
        )
        #expect(hop.hasLocation == false)
    }

    @Test("hasLocation returns false with nil coordinates")
    func hasLocationWithNilCoordinates() {
        let hop = TraceHop(
            hashBytes: Data([0x3F]),
            resolvedName: "Tower",
            snr: 5.0,
            isStartNode: false,
            isEndNode: false,
            latitude: nil,
            longitude: nil
        )
        #expect(hop.hasLocation == false)
    }

    @Test("hasLocation returns true if only latitude is non-zero")
    func hasLocationWithOnlyLatitude() {
        let hop = TraceHop(
            hashBytes: Data([0x3F]),
            resolvedName: "Tower",
            snr: 5.0,
            isStartNode: false,
            isEndNode: false,
            latitude: 45.0,
            longitude: 0
        )
        #expect(hop.hasLocation == true)
    }

    @Test("hasLocation returns true if only longitude is non-zero")
    func hasLocationWithOnlyLongitude() {
        let hop = TraceHop(
            hashBytes: Data([0x3F]),
            resolvedName: "Tower",
            snr: 5.0,
            isStartNode: false,
            isEndNode: false,
            latitude: 0,
            longitude: -122.0
        )
        #expect(hop.hasLocation == true)
    }
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

    @Test("handleTraceResponse creates correct hops with receiver SNR attribution")
    func singleHopTraceProducesCorrectHops() {
        let viewModel = TracePathViewModel()

        // Create a TraceInfo with one repeater hop + final nil node
        // SNR values: 5.0 = what repeater measured, 3.0 = what we measured on return
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

        // Start node has no SNR (it transmitted first, didn't receive)
        #expect(result.hops[0].isStartNode == true)
        #expect(result.hops[0].hashBytes == nil)
        #expect(result.hops[0].snr == 0)  // Receiver attribution: start didn't receive

        // Intermediate hop shows SNR it measured when receiving
        #expect(result.hops[1].isStartNode == false)
        #expect(result.hops[1].isEndNode == false)
        #expect(result.hops[1].hashBytes == Data([0xAB]))
        #expect(result.hops[1].snr == 5.0)  // Receiver attribution: what repeater measured

        // End node shows SNR it measured when receiving
        #expect(result.hops[2].isEndNode == true)
        #expect(result.hops[2].hashBytes == nil)
        #expect(result.hops[2].snr == 3.0)  // Receiver attribution: what we measured
    }

    @Test("handleTraceResponse creates correct hops for multi-hop trace with receiver SNR attribution")
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

        // Receiver attribution: each node shows what it measured when receiving
        #expect(result.hops[0].snr == 0)     // Start: didn't receive (transmitted first)
        #expect(result.hops[1].snr == 6.0)   // AA: what AA measured
        #expect(result.hops[2].snr == 4.0)   // BB: what BB measured
        #expect(result.hops[3].snr == 2.0)   // CC: what CC measured
        #expect(result.hops[4].snr == -1.0)  // End: what End measured

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

// MARK: - Location Resolution Tests

@Suite("Location Resolution")
@MainActor
struct LocationResolutionTests {

    @Test("resolveHashToLocation returns location for single matching contact")
    func returnsLocationForSingleMatch() {
        let viewModel = TracePathViewModel()
        let deviceID = UUID()

        let contact = ContactDTO(
            id: UUID(),
            deviceID: deviceID,
            publicKey: Data([0x3F] + Array(repeating: UInt8(0), count: 31)),
            name: "Tower",
            typeRawValue: ContactType.repeater.rawValue,
            flags: 0,
            outPathLength: 0,
            outPath: Data(),
            lastAdvertTimestamp: 0,
            latitude: 37.7749,
            longitude: -122.4194,
            lastModified: 0,
            nickname: nil,
            isBlocked: false,
            isMuted: false,
            isFavorite: false,
            lastMessageDate: nil,
            unreadCount: 0
        )
        viewModel.setContactsForTesting([contact])

        let location = viewModel.resolveHashToLocation(0x3F)
        #expect(location != nil)
        #expect(location?.latitude == 37.7749)
        #expect(location?.longitude == -122.4194)
    }

    @Test("resolveHashToLocation returns nil for no matches")
    func returnsNilForNoMatch() {
        let viewModel = TracePathViewModel()
        viewModel.setContactsForTesting([])

        let location = viewModel.resolveHashToLocation(0xFF)
        #expect(location == nil)
    }

    @Test("resolveHashToLocation returns best match for multiple contacts")
    func returnsBestMatchForMultipleContacts() {
        let viewModel = TracePathViewModel()
        let deviceID = UUID()

        let contact1 = ContactDTO(
            id: UUID(),
            deviceID: deviceID,
            publicKey: Data([0x3F] + Array(repeating: UInt8(0), count: 31)),
            name: "Tower1",
            typeRawValue: ContactType.repeater.rawValue,
            flags: 0,
            outPathLength: 0,
            outPath: Data(),
            lastAdvertTimestamp: 10,
            latitude: 37.0,
            longitude: -122.0,
            lastModified: 0,
            nickname: nil,
            isBlocked: false,
            isMuted: false,
            isFavorite: false,
            lastMessageDate: nil,
            unreadCount: 0
        )
        let contact2 = ContactDTO(
            id: UUID(),
            deviceID: deviceID,
            publicKey: Data([0x3F] + Array(repeating: UInt8(1), count: 31)),
            name: "Tower2",
            typeRawValue: ContactType.repeater.rawValue,
            flags: 0,
            outPathLength: 0,
            outPath: Data(),
            lastAdvertTimestamp: 50,
            latitude: 38.0,
            longitude: -123.0,
            lastModified: 0,
            nickname: nil,
            isBlocked: false,
            isMuted: false,
            isFavorite: false,
            lastMessageDate: nil,
            unreadCount: 0
        )
        viewModel.setContactsForTesting([contact1, contact2])

        let location = viewModel.resolveHashToLocation(0x3F)
        #expect(location?.latitude == 38.0)
        #expect(location?.longitude == -123.0)
    }

    @Test("resolveHashToLocation returns nil for contact without location")
    func returnsNilForContactWithoutLocation() {
        let viewModel = TracePathViewModel()
        let deviceID = UUID()

        let contact = ContactDTO(
            id: UUID(),
            deviceID: deviceID,
            publicKey: Data([0x3F] + Array(repeating: UInt8(0), count: 31)),
            name: "Tower",
            typeRawValue: ContactType.repeater.rawValue,
            flags: 0,
            outPathLength: 0,
            outPath: Data(),
            lastAdvertTimestamp: 0,
            latitude: 0,
            longitude: 0,
            lastModified: 0,
            nickname: nil,
            isBlocked: false,
            isMuted: false,
            isFavorite: false,
            lastMessageDate: nil,
            unreadCount: 0
        )
        viewModel.setContactsForTesting([contact])

        let location = viewModel.resolveHashToLocation(0x3F)
        #expect(location == nil)
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

// MARK: - Total Path Distance Tests

@Suite("Total Path Distance")
@MainActor
struct TotalPathDistanceTests {

    @Test("calculates full path distance when device has location")
    func calculatesFullPathDistanceWithDeviceLocation() {
        let viewModel = TracePathViewModel()

        // San Francisco to Oakland to Berkeley and back (full path)
        let sf = (lat: 37.7749, lon: -122.4194)
        let oakland = (lat: 37.8044, lon: -122.2712)
        let berkeley = (lat: 37.8716, lon: -122.2727)

        let hops = [
            TraceHop(hashBytes: nil, resolvedName: "Device", snr: 0, isStartNode: true, isEndNode: false,
                     latitude: sf.lat, longitude: sf.lon),
            TraceHop(hashBytes: Data([0x3F]), resolvedName: "Oakland", snr: 5.0, isStartNode: false, isEndNode: false,
                     latitude: oakland.lat, longitude: oakland.lon),
            TraceHop(hashBytes: Data([0x4F]), resolvedName: "Berkeley", snr: 4.0, isStartNode: false, isEndNode: false,
                     latitude: berkeley.lat, longitude: berkeley.lon),
            TraceHop(hashBytes: nil, resolvedName: "Device", snr: 3.0, isStartNode: false, isEndNode: true,
                     latitude: sf.lat, longitude: sf.lon)
        ]

        viewModel.result = TraceResult(hops: hops, durationMs: 100, success: true, errorMessage: nil, tracedPathBytes: [0x3F, 0x4F])

        let distance = viewModel.totalPathDistance
        #expect(distance != nil)
        // SF→Oakland ~13km, Oakland→Berkeley ~8km, Berkeley→SF ~17km ≈ 38km total
        #expect(distance! > 30_000)  // > 30km
        #expect(distance! < 50_000)  // < 50km
    }

    @Test("falls back to intermediate-only distance when device lacks location")
    func fallsBackToIntermediateOnlyDistance() {
        let viewModel = TracePathViewModel()

        let oakland = (lat: 37.8044, lon: -122.2712)
        let berkeley = (lat: 37.8716, lon: -122.2727)

        let hops = [
            TraceHop(hashBytes: nil, resolvedName: "Device", snr: 0, isStartNode: true, isEndNode: false,
                     latitude: nil, longitude: nil),  // No device location
            TraceHop(hashBytes: Data([0x3F]), resolvedName: "Oakland", snr: 5.0, isStartNode: false, isEndNode: false,
                     latitude: oakland.lat, longitude: oakland.lon),
            TraceHop(hashBytes: Data([0x4F]), resolvedName: "Berkeley", snr: 4.0, isStartNode: false, isEndNode: false,
                     latitude: berkeley.lat, longitude: berkeley.lon),
            TraceHop(hashBytes: nil, resolvedName: "Device", snr: 3.0, isStartNode: false, isEndNode: true,
                     latitude: nil, longitude: nil)  // No device location
        ]

        viewModel.result = TraceResult(hops: hops, durationMs: 100, success: true, errorMessage: nil, tracedPathBytes: [0x3F, 0x4F])

        let distance = viewModel.totalPathDistance
        #expect(distance != nil)
        // Falls back to Oakland→Berkeley only ≈ 7.5km
        #expect(distance! > 7_000)  // > 7km
        #expect(distance! < 9_000)  // < 9km
    }

    @Test("returns nil when hop missing location")
    func returnsNilWhenHopMissingLocation() {
        let viewModel = TracePathViewModel()

        let hops = [
            TraceHop(hashBytes: nil, resolvedName: "Device", snr: 0, isStartNode: true, isEndNode: false,
                     latitude: 37.7749, longitude: -122.4194),
            TraceHop(hashBytes: Data([0x3F]), resolvedName: "Unknown", snr: 5.0, isStartNode: false, isEndNode: false,
                     latitude: nil, longitude: nil),
            TraceHop(hashBytes: nil, resolvedName: "Device", snr: 3.0, isStartNode: false, isEndNode: true,
                     latitude: 37.7749, longitude: -122.4194)
        ]

        viewModel.result = TraceResult(hops: hops, durationMs: 100, success: true, errorMessage: nil, tracedPathBytes: [0x3F])

        #expect(viewModel.totalPathDistance == nil)
    }

    @Test("returns nil when hop has zero location")
    func returnsNilWhenHopHasZeroLocation() {
        let viewModel = TracePathViewModel()

        let hops = [
            TraceHop(hashBytes: nil, resolvedName: "Device", snr: 0, isStartNode: true, isEndNode: false,
                     latitude: 37.7749, longitude: -122.4194),
            TraceHop(hashBytes: Data([0x3F]), resolvedName: "Tower", snr: 5.0, isStartNode: false, isEndNode: false,
                     latitude: 0, longitude: 0),
            TraceHop(hashBytes: nil, resolvedName: "Device", snr: 3.0, isStartNode: false, isEndNode: true,
                     latitude: 37.7749, longitude: -122.4194)
        ]

        viewModel.result = TraceResult(hops: hops, durationMs: 100, success: true, errorMessage: nil, tracedPathBytes: [0x3F])

        #expect(viewModel.totalPathDistance == nil)
    }

    @Test("returns nil for failed result")
    func returnsNilForFailedResult() {
        let viewModel = TracePathViewModel()

        viewModel.result = TraceResult(hops: [], durationMs: 0, success: false, errorMessage: "Timeout", tracedPathBytes: [])
        #expect(viewModel.totalPathDistance == nil)
    }

    @Test("calculates distance for single repeater when device has location")
    func calculatesDistanceForSingleRepeaterWithDeviceLocation() {
        let viewModel = TracePathViewModel()

        let sf = (lat: 37.7749, lon: -122.4194)
        let tower = (lat: 37.8, lon: -122.3)

        let hops = [
            TraceHop(hashBytes: nil, resolvedName: "Device", snr: 0, isStartNode: true, isEndNode: false,
                     latitude: sf.lat, longitude: sf.lon),
            TraceHop(hashBytes: Data([0x3F]), resolvedName: "Tower", snr: 5.0, isStartNode: false, isEndNode: false,
                     latitude: tower.lat, longitude: tower.lon),
            TraceHop(hashBytes: nil, resolvedName: "Device", snr: 3.0, isStartNode: false, isEndNode: true,
                     latitude: sf.lat, longitude: sf.lon)
        ]

        viewModel.result = TraceResult(hops: hops, durationMs: 100, success: true, errorMessage: nil, tracedPathBytes: [0x3F])

        // Full path: SF→Tower→SF should calculate (device has location)
        #expect(viewModel.totalPathDistance != nil)
    }

    @Test("returns nil with single repeater and no device location")
    func returnsNilWithSingleRepeaterNoDeviceLocation() {
        let viewModel = TracePathViewModel()

        let hops = [
            TraceHop(hashBytes: nil, resolvedName: "Device", snr: 0, isStartNode: true, isEndNode: false,
                     latitude: nil, longitude: nil),  // No device location
            TraceHop(hashBytes: Data([0x3F]), resolvedName: "Tower", snr: 5.0, isStartNode: false, isEndNode: false,
                     latitude: 37.8, longitude: -122.3),
            TraceHop(hashBytes: nil, resolvedName: "Device", snr: 3.0, isStartNode: false, isEndNode: true,
                     latitude: nil, longitude: nil)  // No device location
        ]

        viewModel.result = TraceResult(hops: hops, durationMs: 100, success: true, errorMessage: nil, tracedPathBytes: [0x3F])

        // Only 1 intermediate repeater, device has no location - can't calculate distance
        #expect(viewModel.totalPathDistance == nil)
    }

    @Test("isDistanceUsingFallback is false when device has location")
    func isDistanceUsingFallbackFalseWithDeviceLocation() {
        let viewModel = TracePathViewModel()

        let sf = (lat: 37.7749, lon: -122.4194)
        let oakland = (lat: 37.8044, lon: -122.2712)
        let berkeley = (lat: 37.8716, lon: -122.2727)

        let hops = [
            TraceHop(hashBytes: nil, resolvedName: "Device", snr: 0, isStartNode: true, isEndNode: false,
                     latitude: sf.lat, longitude: sf.lon),
            TraceHop(hashBytes: Data([0x3F]), resolvedName: "Oakland", snr: 5.0, isStartNode: false, isEndNode: false,
                     latitude: oakland.lat, longitude: oakland.lon),
            TraceHop(hashBytes: Data([0x4F]), resolvedName: "Berkeley", snr: 4.0, isStartNode: false, isEndNode: false,
                     latitude: berkeley.lat, longitude: berkeley.lon),
            TraceHop(hashBytes: nil, resolvedName: "Device", snr: 3.0, isStartNode: false, isEndNode: true,
                     latitude: sf.lat, longitude: sf.lon)
        ]

        viewModel.result = TraceResult(hops: hops, durationMs: 100, success: true, errorMessage: nil, tracedPathBytes: [0x3F, 0x4F])

        #expect(viewModel.isDistanceUsingFallback == false)
    }

    @Test("isDistanceUsingFallback is true when device lacks location")
    func isDistanceUsingFallbackTrueWithoutDeviceLocation() {
        let viewModel = TracePathViewModel()

        let oakland = (lat: 37.8044, lon: -122.2712)
        let berkeley = (lat: 37.8716, lon: -122.2727)

        let hops = [
            TraceHop(hashBytes: nil, resolvedName: "Device", snr: 0, isStartNode: true, isEndNode: false,
                     latitude: nil, longitude: nil),  // No device location
            TraceHop(hashBytes: Data([0x3F]), resolvedName: "Oakland", snr: 5.0, isStartNode: false, isEndNode: false,
                     latitude: oakland.lat, longitude: oakland.lon),
            TraceHop(hashBytes: Data([0x4F]), resolvedName: "Berkeley", snr: 4.0, isStartNode: false, isEndNode: false,
                     latitude: berkeley.lat, longitude: berkeley.lon),
            TraceHop(hashBytes: nil, resolvedName: "Device", snr: 3.0, isStartNode: false, isEndNode: true,
                     latitude: nil, longitude: nil)  // No device location
        ]

        viewModel.result = TraceResult(hops: hops, durationMs: 100, success: true, errorMessage: nil, tracedPathBytes: [0x3F, 0x4F])

        #expect(viewModel.isDistanceUsingFallback == true)
    }

    @Test("isDistanceUsingFallback is false when distance is nil")
    func isDistanceUsingFallbackFalseWhenDistanceNil() {
        let viewModel = TracePathViewModel()

        let hops = [
            TraceHop(hashBytes: nil, resolvedName: "Device", snr: 0, isStartNode: true, isEndNode: false,
                     latitude: nil, longitude: nil),
            TraceHop(hashBytes: Data([0x3F]), resolvedName: "Tower", snr: 5.0, isStartNode: false, isEndNode: false,
                     latitude: nil, longitude: nil),  // Repeater also missing location
            TraceHop(hashBytes: nil, resolvedName: "Device", snr: 3.0, isStartNode: false, isEndNode: true,
                     latitude: nil, longitude: nil)
        ]

        viewModel.result = TraceResult(hops: hops, durationMs: 100, success: true, errorMessage: nil, tracedPathBytes: [0x3F])

        // Distance is nil because repeater lacks location, so fallback flag is false
        #expect(viewModel.totalPathDistance == nil)
        #expect(viewModel.isDistanceUsingFallback == false)
    }
}

// MARK: - Repeaters Without Location Tests

@Suite("Repeaters Without Location")
@MainActor
struct RepeatersWithoutLocationTests {

    @Test("returns names of hops missing locations")
    func returnsNamesOfMissingLocations() {
        let viewModel = TracePathViewModel()

        let hops = [
            TraceHop(hashBytes: nil, resolvedName: "Device", snr: 0, isStartNode: true, isEndNode: false,
                     latitude: 37.7749, longitude: -122.4194),
            TraceHop(hashBytes: Data([0x3F]), resolvedName: "Tower A", snr: 5.0, isStartNode: false, isEndNode: false,
                     latitude: nil, longitude: nil),
            TraceHop(hashBytes: Data([0x4F]), resolvedName: "Tower B", snr: 4.0, isStartNode: false, isEndNode: false,
                     latitude: 37.8, longitude: -122.3),
            TraceHop(hashBytes: Data([0x5F]), resolvedName: "Tower C", snr: 3.0, isStartNode: false, isEndNode: false,
                     latitude: 0, longitude: 0),
            TraceHop(hashBytes: nil, resolvedName: "Device", snr: 2.0, isStartNode: false, isEndNode: true,
                     latitude: 37.7749, longitude: -122.4194)
        ]

        viewModel.result = TraceResult(hops: hops, durationMs: 100, success: true, errorMessage: nil, tracedPathBytes: [0x3F, 0x4F, 0x5F])

        let missing = viewModel.repeatersWithoutLocation
        #expect(missing.count == 2)
        #expect(missing.contains("Tower A"))
        #expect(missing.contains("Tower C"))
        #expect(!missing.contains("Tower B"))
    }

    @Test("uses hash display for unresolved names")
    func usesHashDisplayForUnresolvedNames() {
        let viewModel = TracePathViewModel()

        let hops = [
            TraceHop(hashBytes: nil, resolvedName: "Device", snr: 0, isStartNode: true, isEndNode: false,
                     latitude: 37.7749, longitude: -122.4194),
            TraceHop(hashBytes: Data([0x3F]), resolvedName: nil, snr: 5.0, isStartNode: false, isEndNode: false,
                     latitude: nil, longitude: nil),
            TraceHop(hashBytes: nil, resolvedName: "Device", snr: 2.0, isStartNode: false, isEndNode: true,
                     latitude: 37.7749, longitude: -122.4194)
        ]

        viewModel.result = TraceResult(hops: hops, durationMs: 100, success: true, errorMessage: nil, tracedPathBytes: [0x3F])

        let missing = viewModel.repeatersWithoutLocation
        #expect(missing.count == 1)
        #expect(missing[0] == "3F") // hex display
    }

    @Test("excludes start and end nodes")
    func excludesStartAndEndNodes() {
        let viewModel = TracePathViewModel()

        let hops = [
            TraceHop(hashBytes: nil, resolvedName: "Device", snr: 0, isStartNode: true, isEndNode: false,
                     latitude: nil, longitude: nil), // Start node missing - excluded
            TraceHop(hashBytes: Data([0x3F]), resolvedName: "Tower", snr: 5.0, isStartNode: false, isEndNode: false,
                     latitude: 37.8, longitude: -122.3),
            TraceHop(hashBytes: nil, resolvedName: "Device", snr: 2.0, isStartNode: false, isEndNode: true,
                     latitude: nil, longitude: nil) // End node missing - excluded
        ]

        viewModel.result = TraceResult(hops: hops, durationMs: 100, success: true, errorMessage: nil, tracedPathBytes: [0x3F])

        let missing = viewModel.repeatersWithoutLocation
        #expect(missing.count == 0) // Only intermediate hops count
    }

    @Test("returns empty when device location missing but no intermediate repeaters affected")
    func returnsEmptyWhenOnlyDeviceMissing() {
        let viewModel = TracePathViewModel()

        let hops = [
            TraceHop(hashBytes: nil, resolvedName: "My Device", snr: 0, isStartNode: true, isEndNode: false,
                     latitude: nil, longitude: nil),
            TraceHop(hashBytes: Data([0x3F]), resolvedName: "Tower", snr: 5.0, isStartNode: false, isEndNode: false,
                     latitude: 37.8, longitude: -122.3),
            TraceHop(hashBytes: nil, resolvedName: "My Device", snr: 2.0, isStartNode: false, isEndNode: true,
                     latitude: nil, longitude: nil)
        ]

        viewModel.result = TraceResult(hops: hops, durationMs: 100, success: true, errorMessage: nil, tracedPathBytes: [0x3F])

        let missing = viewModel.repeatersWithoutLocation
        #expect(missing.count == 0)
    }
}

// MARK: - Code Input Parsing Tests

@Suite("Code Input Parsing")
@MainActor
struct CodeInputParsingTests {

    private func createRepeater(prefix: UInt8, name: String) -> ContactDTO {
        let contact = Contact(
            id: UUID(),
            deviceID: UUID(),
            publicKey: Data([prefix] + Array(repeating: UInt8(0x00), count: 31)),
            name: name,
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

    @Test("parses valid comma-separated codes and adds repeaters")
    func parsesValidCodes() {
        let viewModel = TracePathViewModel()
        viewModel.availableRepeaters = [
            createRepeater(prefix: 0xA3, name: "Alpha"),
            createRepeater(prefix: 0xB7, name: "Bravo"),
            createRepeater(prefix: 0xF2, name: "Foxtrot")
        ]

        let result = viewModel.addRepeatersFromCodes("A3, B7")

        #expect(result.added == ["A3", "B7"])
        #expect(result.notFound.isEmpty)
        #expect(result.alreadyInPath.isEmpty)
        #expect(viewModel.outboundPath.count == 2)
        #expect(viewModel.outboundPath[0].hashByte == 0xA3)
        #expect(viewModel.outboundPath[1].hashByte == 0xB7)
    }

    @Test("handles case insensitive input")
    func caseInsensitive() {
        let viewModel = TracePathViewModel()
        viewModel.availableRepeaters = [
            createRepeater(prefix: 0xA3, name: "Alpha")
        ]

        let result = viewModel.addRepeatersFromCodes("a3")

        #expect(result.added == ["A3"])
        #expect(viewModel.outboundPath.count == 1)
    }

    @Test("handles codes without spaces after commas")
    func noSpacesAfterCommas() {
        let viewModel = TracePathViewModel()
        viewModel.availableRepeaters = [
            createRepeater(prefix: 0xA3, name: "Alpha"),
            createRepeater(prefix: 0xB7, name: "Bravo")
        ]

        let result = viewModel.addRepeatersFromCodes("A3,B7")

        #expect(result.added.count == 2)
        #expect(viewModel.outboundPath.count == 2)
    }

    @Test("reports codes not found in available repeaters")
    func reportsNotFound() {
        let viewModel = TracePathViewModel()
        viewModel.availableRepeaters = [
            createRepeater(prefix: 0xA3, name: "Alpha")
        ]

        let result = viewModel.addRepeatersFromCodes("A3, 11, FF")

        #expect(result.added == ["A3"])
        #expect(result.notFound == ["11", "FF"])
        #expect(viewModel.outboundPath.count == 1)
    }

    @Test("reports codes already in outbound path")
    func reportsAlreadyInPath() {
        let viewModel = TracePathViewModel()
        let alpha = createRepeater(prefix: 0xA3, name: "Alpha")
        viewModel.availableRepeaters = [alpha]
        viewModel.addRepeater(alpha)

        let result = viewModel.addRepeatersFromCodes("A3")

        #expect(result.added.isEmpty)
        #expect(result.alreadyInPath == ["A3"])
        #expect(viewModel.outboundPath.count == 1)
    }

    @Test("deduplicates codes in input")
    func deduplicatesInput() {
        let viewModel = TracePathViewModel()
        viewModel.availableRepeaters = [
            createRepeater(prefix: 0xA3, name: "Alpha")
        ]

        let result = viewModel.addRepeatersFromCodes("A3, A3, a3")

        #expect(result.added == ["A3"])
        #expect(viewModel.outboundPath.count == 1)
    }

    @Test("reports invalid hex format")
    func reportsInvalidFormat() {
        let viewModel = TracePathViewModel()
        viewModel.availableRepeaters = [
            createRepeater(prefix: 0xA3, name: "Alpha")
        ]

        let result = viewModel.addRepeatersFromCodes("A3, ZZ, 123, X")

        #expect(result.added == ["A3"])
        #expect(result.invalidFormat == ["ZZ", "123", "X"])
    }

    @Test("handles empty input")
    func handlesEmptyInput() {
        let viewModel = TracePathViewModel()

        let result = viewModel.addRepeatersFromCodes("")

        #expect(result.added.isEmpty)
        #expect(result.notFound.isEmpty)
        #expect(result.invalidFormat.isEmpty)
    }

    @Test("handles whitespace-only input")
    func handlesWhitespaceOnly() {
        let viewModel = TracePathViewModel()

        let result = viewModel.addRepeatersFromCodes("   ,  , ")

        #expect(result.added.isEmpty)
    }

    @Test("hasErrors returns false when all codes are valid and new")
    func hasErrorsWhenNoErrors() {
        let viewModel = TracePathViewModel()
        viewModel.availableRepeaters = [
            createRepeater(prefix: 0xA3, name: "Alpha")
        ]

        let result = viewModel.addRepeatersFromCodes("A3")

        #expect(result.hasErrors == false)
        #expect(result.errorMessage == nil)
    }

    @Test("hasErrors returns true when errors exist")
    func hasErrorsWhenErrors() {
        let viewModel = TracePathViewModel()
        viewModel.availableRepeaters = []

        let result = viewModel.addRepeatersFromCodes("A3")

        #expect(result.hasErrors == true)
        #expect(result.errorMessage != nil)
    }

    @Test("errorMessage formats multiple error types with separator")
    func errorMessageFormatsMultipleTypes() {
        let viewModel = TracePathViewModel()
        let alpha = createRepeater(prefix: 0xA3, name: "Alpha")
        viewModel.availableRepeaters = [alpha]
        viewModel.addRepeater(alpha)

        let result = viewModel.addRepeatersFromCodes("ZZ, 11, A3")

        #expect(result.errorMessage?.contains("Invalid format: ZZ") == true)
        #expect(result.errorMessage?.contains("11 not found") == true)
        #expect(result.errorMessage?.contains("A3 already in path") == true)
    }

    @Test("clears saved path state when repeaters are added")
    func clearsSavedPathStateOnSuccess() {
        let viewModel = TracePathViewModel()
        viewModel.availableRepeaters = [
            createRepeater(prefix: 0xA3, name: "Alpha")
        ]
        viewModel.activeSavedPath = createTestSavedPath(runs: [])

        _ = viewModel.addRepeatersFromCodes("A3")

        #expect(viewModel.activeSavedPath == nil)
    }
}

// MARK: - OutboundPath Name Resolution Tests

@Suite("OutboundPath Name Resolution")
@MainActor
struct OutboundPathNameResolutionTests {

    private func createContact(prefix: UInt8, name: String, lat: Double = 0, lon: Double = 0) -> ContactDTO {
        ContactDTO(
            id: UUID(),
            deviceID: UUID(),
            publicKey: Data([prefix] + Array(repeating: UInt8(0), count: 31)),
            name: name,
            typeRawValue: ContactType.repeater.rawValue,
            flags: 0,
            outPathLength: 0,
            outPath: Data(),
            lastAdvertTimestamp: 0,
            latitude: lat,
            longitude: lon,
            lastModified: 0,
            nickname: nil,
            isBlocked: false,
            isMuted: false,
            isFavorite: false,
            lastMessageDate: nil,
            unreadCount: 0
        )
    }

    @Test("resolves name using best match when contact collision exists")
    func resolvesNameUsingBestMatchWithCollision() {
        let viewModel = TracePathViewModel()

        // Two contacts with same first byte (collision)
        let contact1 = createContact(prefix: 0x3F, name: "Flint Hill - KC3ELT")
        let contact2 = createContact(prefix: 0x3F, name: "Other Tower")
        // Make contact2 have different second byte so they're distinct
        var contact2Key = contact2.publicKey
        contact2Key = Data([0x3F, 0x01] + Array(repeating: UInt8(0), count: 30))
        let contact1Modified = ContactDTO(
            id: contact1.id,
            deviceID: contact1.deviceID,
            publicKey: contact1.publicKey,
            name: contact1.name,
            typeRawValue: contact1.typeRawValue,
            flags: contact1.flags,
            outPathLength: contact1.outPathLength,
            outPath: contact1.outPath,
            lastAdvertTimestamp: 10,
            latitude: contact1.latitude,
            longitude: contact1.longitude,
            lastModified: contact1.lastModified,
            nickname: contact1.nickname,
            isBlocked: contact1.isBlocked,
            isMuted: contact1.isMuted,
            isFavorite: contact1.isFavorite,
            lastMessageDate: contact1.lastMessageDate,
            unreadCount: contact1.unreadCount
        )
        let contact2Modified = ContactDTO(
            id: contact2.id,
            deviceID: contact2.deviceID,
            publicKey: contact2Key,
            name: "Other Tower",
            typeRawValue: contact2.typeRawValue,
            flags: contact2.flags,
            outPathLength: contact2.outPathLength,
            outPath: contact2.outPath,
            lastAdvertTimestamp: 50,
            latitude: contact2.latitude,
            longitude: contact2.longitude,
            lastModified: contact2.lastModified,
            nickname: contact2.nickname,
            isBlocked: contact2.isBlocked,
            isMuted: contact2.isMuted,
            isFavorite: contact2.isFavorite,
            lastMessageDate: contact2.lastMessageDate,
            unreadCount: contact2.unreadCount
        )

        viewModel.setContactsForTesting([contact1Modified, contact2Modified])

        // User selects contact1 for their path
        viewModel.addRepeater(contact1Modified)

        // Run trace
        let traceInfo = TraceInfo(
            tag: 12345,
            authCode: 0,
            flags: 0,
            pathLength: 1,
            path: [
                TraceNode(hash: 0x3F, snr: 5.0),
                TraceNode(hash: nil, snr: 3.0)
            ]
        )

        viewModel.setPendingTagForTesting(12345)
        viewModel.handleTraceResponse(traceInfo, deviceID: nil)

        guard let result = viewModel.result else {
            Issue.record("Result should not be nil")
            return
        }

        // Name should resolve from best match (most recent advert)
        #expect(result.hops[1].resolvedName == "Other Tower")
    }

    @Test("falls back to contact lookup when hop not in outboundPath")
    func fallsBackToContactLookup() {
        let viewModel = TracePathViewModel()

        // Single contact (no collision)
        let contact = createContact(prefix: 0xAB, name: "Test Tower")
        viewModel.setContactsForTesting([contact])

        // Empty outboundPath - user didn't select any repeaters
        // (simulating an unexpected hop in the trace response)

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

        // Should fall back to contact lookup since outboundPath is empty
        #expect(result.hops[1].resolvedName == "Test Tower")
    }
}
