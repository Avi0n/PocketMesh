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

    @Test("Direct message LRU eviction at limit of 5")
    func directMessageLRUEviction() async {
        let cache = MessageDeduplicationCache()
        let contactID = UUID()

        // Add 5 messages (fills cache)
        for i in 0..<5 {
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

        // Add 6th message (should evict oldest)
        _ = await cache.isDuplicateDirectMessage(
            contactID: contactID,
            timestamp: 5,
            content: "Message 5"
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

    @Test("Channel message LRU eviction at limit of 10")
    func channelMessageLRUEviction() async {
        let cache = MessageDeduplicationCache()
        let channelIndex: UInt8 = 0

        // Add 10 messages (fills cache)
        for i in 0..<10 {
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

        // Add 11th message (should evict oldest)
        _ = await cache.isDuplicateChannelMessage(
            channelIndex: channelIndex,
            timestamp: 10,
            username: "User",
            content: "Message 10"
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
