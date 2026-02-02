import Foundation
import Testing
@testable import PocketMeshServices

@Suite("MessageLRUCache Tests")
struct MessageLRUCacheTests {

    @Test("Indexes and retrieves message")
    func indexesAndRetrievesMessage() async {
        let cache = MessageLRUCache()
        let messageID = UUID()

        await cache.index(
            messageID: messageID,
            channelIndex: 0,
            senderName: "Node",
            text: "Hello",
            timestamp: 1704067200
        )

        let hash = ReactionParser.generateMessageHash(text: "Hello", timestamp: 1704067200)
        let result = await cache.lookup(channelIndex: 0, senderName: "Node", messageHash: hash)

        #expect(result == messageID)
    }

    @Test("Returns nil for non-existent message")
    func returnsNilForNonExistent() async {
        let cache = MessageLRUCache()

        let result = await cache.lookup(channelIndex: 0, senderName: "Node", messageHash: "abcd1234")

        #expect(result == nil)
    }

    @Test("Evicts oldest entry at capacity")
    func evictsOldestAtCapacity() async {
        let cache = MessageLRUCache(capacity: 3)

        // Add 3 messages
        for i in 0..<3 {
            await cache.index(
                messageID: UUID(),
                channelIndex: 0,
                senderName: "Node\(i)",
                text: "Message \(i)",
                timestamp: UInt32(i)
            )
        }

        let hash0 = ReactionParser.generateMessageHash(text: "Message 0", timestamp: 0)
        let before = await cache.lookup(channelIndex: 0, senderName: "Node0", messageHash: hash0)
        #expect(before != nil)

        // Add 4th message (should evict first)
        await cache.index(
            messageID: UUID(),
            channelIndex: 0,
            senderName: "Node3",
            text: "Message 3",
            timestamp: 3
        )

        let after = await cache.lookup(channelIndex: 0, senderName: "Node0", messageHash: hash0)
        #expect(after == nil)
    }

    @Test("Different channels are separate")
    func differentChannelsAreSeparate() async {
        let cache = MessageLRUCache()
        let messageID = UUID()

        await cache.index(
            messageID: messageID,
            channelIndex: 0,
            senderName: "Node",
            text: "Hello",
            timestamp: 1704067200
        )

        let hash = ReactionParser.generateMessageHash(text: "Hello", timestamp: 1704067200)

        // Should find on channel 0
        let result0 = await cache.lookup(channelIndex: 0, senderName: "Node", messageHash: hash)
        #expect(result0 == messageID)

        // Should not find on channel 1
        let result1 = await cache.lookup(channelIndex: 1, senderName: "Node", messageHash: hash)
        #expect(result1 == nil)
    }
}
