import Testing
import Foundation
@testable import PocketMesh
@testable import PocketMeshServices
@testable import MeshCore

@Suite("Batch Trace State")
@MainActor
struct BatchTraceStateTests {

    @Test("batch properties have correct defaults")
    func batchPropertiesHaveCorrectDefaults() {
        let viewModel = TracePathViewModel()

        #expect(viewModel.batchEnabled == false)
        #expect(viewModel.batchSize == 5)
        #expect(viewModel.currentTraceIndex == 0)
        #expect(viewModel.completedResults.isEmpty)
        #expect(viewModel.isBatchInProgress == false)
        #expect(viewModel.isBatchComplete == false)
    }

    @Test("successfulResults filters to successful traces only")
    func successfulResultsFiltersCorrectly() {
        let viewModel = TracePathViewModel()

        let successResult = TraceResult(
            hops: [],
            durationMs: 100,
            success: true,
            errorMessage: nil,
            tracedPathBytes: [0xAA]
        )
        let failedResult = TraceResult(
            hops: [],
            durationMs: 0,
            success: false,
            errorMessage: "Timeout",
            tracedPathBytes: [0xAA]
        )

        viewModel.completedResults = [successResult, failedResult, successResult]

        #expect(viewModel.successfulResults.count == 2)
    }

    @Test("successCount returns number of successful traces")
    func successCountReturnsCorrectValue() {
        let viewModel = TracePathViewModel()

        let successResult = TraceResult(
            hops: [],
            durationMs: 100,
            success: true,
            errorMessage: nil,
            tracedPathBytes: [0xAA]
        )
        let failedResult = TraceResult(
            hops: [],
            durationMs: 0,
            success: false,
            errorMessage: "Timeout",
            tracedPathBytes: [0xAA]
        )

        viewModel.completedResults = [successResult, failedResult, successResult]

        #expect(viewModel.successCount == 2)
    }

    @Test("batchEnabled didSet clears batch state when disabled")
    func batchEnabledDidSetClearsBatchState() {
        let viewModel = TracePathViewModel()
        viewModel.batchEnabled = true
        viewModel.currentTraceIndex = 3
        viewModel.completedResults = [
            TraceResult(hops: [], durationMs: 100, success: true, errorMessage: nil, tracedPathBytes: [0xAA])
        ]

        viewModel.batchEnabled = false

        #expect(viewModel.currentTraceIndex == 0)
        #expect(viewModel.completedResults.isEmpty)
    }
}
