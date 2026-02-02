import Foundation
import Testing
@testable import PocketMeshServices

@Suite("PendingReactionsQueue Tests")
struct PendingReactionsQueueTests {

    @Test("Adds parsed reaction to queue")
    func addsParsedReaction() async {
        let queue = PendingReactionsQueue()
        let parsed = ParsedReaction(
            emoji: "👍",
            targetSender: "Node",
            contentPreview: "Hello",
            messageHash: "a1b2c3d4"
        )

        await queue.add(parsed, channelIndex: 0, rawText: "👍 @Node: Hello [a1b2c3d4]")

        let pending = await queue.allPending()
        #expect(pending.count == 1)
    }

    @Test("Expires entries after TTL")
    func expiresAfterTTL() async throws {
        let queue = PendingReactionsQueue(ttlSeconds: 0.1) // 100ms for testing
        let parsed = ParsedReaction(
            emoji: "👍",
            targetSender: "Node",
            contentPreview: "Hello",
            messageHash: "a1b2c3d4"
        )

        await queue.add(parsed, channelIndex: 0, rawText: "👍 @Node: Hello [a1b2c3d4]")

        // Wait for expiry
        try await Task.sleep(for: .milliseconds(150))

        let expired = await queue.expireOldEntries()
        #expect(expired.count == 1)
        #expect(expired.first?.rawText == "👍 @Node: Hello [a1b2c3d4]")

        let pending = await queue.allPending()
        #expect(pending.isEmpty)
    }

    @Test("Removes entry when matched")
    func removesWhenMatched() async {
        let queue = PendingReactionsQueue()
        let parsed = ParsedReaction(
            emoji: "👍",
            targetSender: "Node",
            contentPreview: "Hello",
            messageHash: "a1b2c3d4"
        )

        await queue.add(parsed, channelIndex: 0, rawText: "👍 @Node: Hello [a1b2c3d4]")
        await queue.removeMatched(messageHash: "a1b2c3d4", channelIndex: 0)

        let pending = await queue.allPending()
        #expect(pending.isEmpty)
    }
}
