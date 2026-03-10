// PocketMeshServices/Tests/PocketMeshServicesTests/Services/MessageDeduplicationCacheTests.swift
import Foundation
import Testing
@testable import PocketMeshServices

@Suite("MessageDeduplicationCache Tests")
struct MessageDeduplicationCacheTests {

    // MARK: - Direct Message Tests

    @Test("First direct message is not a duplicate")
    func firstDirectMessageNotDuplicate() async {
        let cache = MessageDeduplicationCache()
        let contactID = UUID()

        let isDuplicate = await cache.isDuplicateDirectMessage(
            contactID: contactID,
            timestamp: 1704067200,
            content: "Hello world"
        )

        #expect(!isDuplicate)
    }

    @Test("Same direct message is detected as duplicate")
    func sameDirectMessageIsDuplicate() async {
        let cache = MessageDeduplicationCache()
        let contactID = UUID()

        // First call registers it
        _ = await cache.isDuplicateDirectMessage(
            contactID: contactID,
            timestamp: 1704067200,
            content: "Hello world"
        )

        // Second call should detect duplicate
        let isDuplicate = await cache.isDuplicateDirectMessage(
            contactID: contactID,
            timestamp: 1704067200,
            content: "Hello world"
        )

        #expect(isDuplicate)
    }

    @Test("Message remains duplicate on subsequent checks")
    func tripleCheckRemainsDuplicate() async {
        let cache = MessageDeduplicationCache()
        let contactID = UUID()

        // First call registers it
        let first = await cache.isDuplicateDirectMessage(
            contactID: contactID,
            timestamp: 1704067200,
            content: "Hello world"
        )
        #expect(!first)

        // Second call detects duplicate
        let second = await cache.isDuplicateDirectMessage(
            contactID: contactID,
            timestamp: 1704067200,
            content: "Hello world"
        )
        #expect(second)

        // Third call should still detect duplicate (not re-registered)
        let third = await cache.isDuplicateDirectMessage(
            contactID: contactID,
            timestamp: 1704067200,
            content: "Hello world"
        )
        #expect(third)
    }

    @Test("Different content is not a duplicate")
    func differentContentNotDuplicate() async {
        let cache = MessageDeduplicationCache()
        let contactID = UUID()

        _ = await cache.isDuplicateDirectMessage(
            contactID: contactID,
            timestamp: 1704067200,
            content: "Hello world"
        )

        let isDuplicate = await cache.isDuplicateDirectMessage(
            contactID: contactID,
            timestamp: 1704067200,
            content: "Different message"
        )

        #expect(!isDuplicate)
    }

    @Test("Different timestamp is not a duplicate")
    func differentTimestampNotDuplicate() async {
        let cache = MessageDeduplicationCache()
        let contactID = UUID()

        _ = await cache.isDuplicateDirectMessage(
            contactID: contactID,
            timestamp: 1704067200,
            content: "Hello world"
        )

        let isDuplicate = await cache.isDuplicateDirectMessage(
            contactID: contactID,
            timestamp: 1704067201,
            content: "Hello world"
        )

        #expect(!isDuplicate)
    }

    @Test("Different contact has separate cache")
    func differentContactSeparateCache() async {
        let cache = MessageDeduplicationCache()
        let contact1 = UUID()
        let contact2 = UUID()

        _ = await cache.isDuplicateDirectMessage(
            contactID: contact1,
            timestamp: 1704067200,
            content: "Hello world"
        )

        // Same message from different contact should not be duplicate
        let isDuplicate = await cache.isDuplicateDirectMessage(
            contactID: contact2,
            timestamp: 1704067200,
            content: "Hello world"
        )

        #expect(!isDuplicate)
    }

    @Test("Direct message FIFO eviction at limit of 50")
    func directMessageFIFOEviction() async {
        let cache = MessageDeduplicationCache()
        let contactID = UUID()

        // Add 50 messages (fills cache)
        for i in 0..<50 {
            _ = await cache.isDuplicateDirectMessage(
                contactID: contactID,
                timestamp: UInt32(i),
                content: "Message \(i)"
            )
        }

        // First message should still be in cache
        var isDuplicate = await cache.isDuplicateDirectMessage(
            contactID: contactID,
            timestamp: 0,
            content: "Message 0"
        )
        #expect(isDuplicate)

        // Add 51st message (should evict oldest)
        _ = await cache.isDuplicateDirectMessage(
            contactID: contactID,
            timestamp: 50,
            content: "Message 50"
        )

        // First message should be evicted now
        isDuplicate = await cache.isDuplicateDirectMessage(
            contactID: contactID,
            timestamp: 0,
            content: "Message 0"
        )
        #expect(!isDuplicate)
    }

    // MARK: - Channel Message Tests

    @Test("First channel message is not a duplicate")
    func firstChannelMessageNotDuplicate() async {
        let cache = MessageDeduplicationCache()

        let isDuplicate = await cache.isDuplicateChannelMessage(
            channelIndex: 0,
            timestamp: 1704067200,
            username: "Alice",
            content: "Hello channel"
        )

        #expect(!isDuplicate)
    }

    @Test("Same channel message is detected as duplicate")
    func sameChannelMessageIsDuplicate() async {
        let cache = MessageDeduplicationCache()

        _ = await cache.isDuplicateChannelMessage(
            channelIndex: 0,
            timestamp: 1704067200,
            username: "Alice",
            content: "Hello channel"
        )

        let isDuplicate = await cache.isDuplicateChannelMessage(
            channelIndex: 0,
            timestamp: 1704067200,
            username: "Alice",
            content: "Hello channel"
        )

        #expect(isDuplicate)
    }

    @Test("Different username is not a duplicate")
    func differentUsernameNotDuplicate() async {
        let cache = MessageDeduplicationCache()

        _ = await cache.isDuplicateChannelMessage(
            channelIndex: 0,
            timestamp: 1704067200,
            username: "Alice",
            content: "Hello channel"
        )

        let isDuplicate = await cache.isDuplicateChannelMessage(
            channelIndex: 0,
            timestamp: 1704067200,
            username: "Bob",
            content: "Hello channel"
        )

        #expect(!isDuplicate)
    }

    @Test("Different channel has separate cache")
    func differentChannelSeparateCache() async {
        let cache = MessageDeduplicationCache()

        _ = await cache.isDuplicateChannelMessage(
            channelIndex: 0,
            timestamp: 1704067200,
            username: "Alice",
            content: "Hello channel"
        )

        let isDuplicate = await cache.isDuplicateChannelMessage(
            channelIndex: 1,
            timestamp: 1704067200,
            username: "Alice",
            content: "Hello channel"
        )

        #expect(!isDuplicate)
    }

    @Test("Channel message FIFO eviction at limit of 100")
    func channelMessageFIFOEviction() async {
        let cache = MessageDeduplicationCache()
        let channelIndex: UInt8 = 0

        // Add 100 messages (fills cache)
        for i in 0..<100 {
            _ = await cache.isDuplicateChannelMessage(
                channelIndex: channelIndex,
                timestamp: UInt32(i),
                username: "User",
                content: "Message \(i)"
            )
        }

        // First message should still be in cache
        var isDuplicate = await cache.isDuplicateChannelMessage(
            channelIndex: channelIndex,
            timestamp: 0,
            username: "User",
            content: "Message 0"
        )
        #expect(isDuplicate)

        // Add 101st message (should evict oldest)
        _ = await cache.isDuplicateChannelMessage(
            channelIndex: channelIndex,
            timestamp: 100,
            username: "User",
            content: "Message 100"
        )

        // First message should be evicted now
        isDuplicate = await cache.isDuplicateChannelMessage(
            channelIndex: channelIndex,
            timestamp: 0,
            username: "User",
            content: "Message 0"
        )
        #expect(!isDuplicate)
    }

    // MARK: - Unknown Contact Tests

    @Test("Unknown contacts share the same deduplication bucket")
    func unknownContactsShareBucket() async {
        let cache = MessageDeduplicationCache()

        // Register a message from unknown contact
        _ = await cache.isDuplicateDirectMessage(
            contactID: MessageDeduplicationCache.unknownContactID,
            timestamp: 1704067200,
            content: "Hello from unknown"
        )

        // Same message with same sentinel ID should be duplicate
        let isDuplicate = await cache.isDuplicateDirectMessage(
            contactID: MessageDeduplicationCache.unknownContactID,
            timestamp: 1704067200,
            content: "Hello from unknown"
        )

        #expect(isDuplicate)
    }

    @Test("Unknown contact bucket is separate from known contacts")
    func unknownContactSeparateFromKnown() async {
        let cache = MessageDeduplicationCache()
        let knownContact = UUID()

        // Register from unknown contact
        _ = await cache.isDuplicateDirectMessage(
            contactID: MessageDeduplicationCache.unknownContactID,
            timestamp: 1704067200,
            content: "Hello"
        )

        // Same message from known contact should NOT be duplicate
        let isDuplicate = await cache.isDuplicateDirectMessage(
            contactID: knownContact,
            timestamp: 1704067200,
            content: "Hello"
        )

        #expect(!isDuplicate)
    }

    // MARK: - Clear Tests

    @Test("Clear removes all cached entries")
    func clearRemovesAllEntries() async {
        let cache = MessageDeduplicationCache()
        let contactID = UUID()

        _ = await cache.isDuplicateDirectMessage(
            contactID: contactID,
            timestamp: 1704067200,
            content: "Hello"
        )

        _ = await cache.isDuplicateChannelMessage(
            channelIndex: 0,
            timestamp: 1704067200,
            username: "Alice",
            content: "Channel msg"
        )

        await cache.clear()

        // Both should no longer be detected as duplicates
        let directDup = await cache.isDuplicateDirectMessage(
            contactID: contactID,
            timestamp: 1704067200,
            content: "Hello"
        )
        let channelDup = await cache.isDuplicateChannelMessage(
            channelIndex: 0,
            timestamp: 1704067200,
            username: "Alice",
            content: "Channel msg"
        )

        #expect(!directDup)
        #expect(!channelDup)
    }
}
