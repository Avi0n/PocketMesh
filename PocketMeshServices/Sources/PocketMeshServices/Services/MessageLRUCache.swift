import Foundation

/// Key for message lookup in LRU cache
public struct MessageCacheKey: Hashable, Sendable {
    public let channelIndex: UInt8
    public let senderName: String
    public let messageHash: String

    public init(channelIndex: UInt8, senderName: String, messageHash: String) {
        self.channelIndex = channelIndex
        self.senderName = senderName
        self.messageHash = messageHash
    }
}

/// LRU cache for recent channel messages to enable O(1) reaction matching
public actor MessageLRUCache {
    private var cache: [MessageCacheKey: UUID] = [:]
    private var order: [MessageCacheKey] = []
    private let capacity: Int

    public init(capacity: Int = 200) {
        self.capacity = capacity
    }

    /// Indexes a message for later lookup
    public func index(messageID: UUID, channelIndex: UInt8, senderName: String, text: String, timestamp: UInt32) {
        let hash = ReactionParser.generateMessageHash(text: text, timestamp: timestamp)
        let key = MessageCacheKey(channelIndex: channelIndex, senderName: senderName, messageHash: hash)

        // Remove if already exists (will re-add at end)
        if let existingIndex = order.firstIndex(of: key) {
            order.remove(at: existingIndex)
        }

        // Evict oldest if at capacity
        if order.count >= capacity, let oldest = order.first {
            order.removeFirst()
            cache.removeValue(forKey: oldest)
        }

        cache[key] = messageID
        order.append(key)
    }

    /// Looks up a message ID by cache key
    public func lookup(channelIndex: UInt8, senderName: String, messageHash: String) -> UUID? {
        let key = MessageCacheKey(channelIndex: channelIndex, senderName: senderName, messageHash: messageHash)
        return cache[key]
    }

    /// Clears the cache
    public func clear() {
        cache.removeAll()
        order.removeAll()
    }
}
