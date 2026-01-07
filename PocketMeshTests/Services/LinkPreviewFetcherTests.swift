import Testing
import Foundation
@testable import PocketMesh

@Suite("LinkPreviewFetcher Tests")
@MainActor
struct LinkPreviewFetcherTests {

    @Test("isFetching returns false for unknown message ID")
    func isFetchingReturnsFalseForUnknown() {
        let fetcher = LinkPreviewFetcher()
        let unknownID = UUID()
        #expect(fetcher.isFetching(unknownID) == false)
    }

    @Test("isFetching returns false for multiple unknown IDs")
    func isFetchingReturnsFalseForMultipleUnknowns() {
        let fetcher = LinkPreviewFetcher()

        // None of these should be marked as fetching
        for _ in 0..<10 {
            let randomID = UUID()
            #expect(fetcher.isFetching(randomID) == false)
        }
    }
}
