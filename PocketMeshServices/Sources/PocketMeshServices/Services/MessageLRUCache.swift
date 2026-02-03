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

/// Candidate message for reaction matching
public struct MessageCandidate: Sendable, Equatable {
    public let messageID: UUID
    public let text: String
    public let timestamp: UInt32
    public let indexedAt: Date

    public init(messageID: UUID, text: String, timestamp: UInt32, indexedAt: Date = Date()) {
        self.messageID = messageID
        self.text = text
        self.timestamp = timestamp
        self.indexedAt = indexedAt
    }
}

/// LRU cache for recent channel messages to enable reaction matching with collision resolution
public actor MessageLRUCache {
    private var cache: [MessageCacheKey: [MessageCandidate]] = [:]
    private var order: [MessageCacheKey] = []
    private let capacity: Int
    private let maxCandidatesPerKey: Int

    public init(capacity: Int = 500, maxCandidatesPerKey: Int = 5) {
        self.capacity = capacity
        self.maxCandidatesPerKey = maxCandidatesPerKey
    }

    /// Indexes a message for later lookup
    public func index(messageID: UUID, channelIndex: UInt8, senderName: String, text: String, timestamp: UInt32) {
        let hash = ReactionParser.generateMessageHash(text: text, timestamp: timestamp)
        let key = MessageCacheKey(channelIndex: channelIndex, senderName: senderName, messageHash: hash)
        let candidate = MessageCandidate(messageID: messageID, text: text, timestamp: timestamp)

        // Update LRU order
        if let existingIndex = order.firstIndex(of: key) {
            order.remove(at: existingIndex)
        }
        order.append(key)

        // Evict oldest key if at capacity
        if order.count > capacity, let oldest = order.first {
            order.removeFirst()
            cache.removeValue(forKey: oldest)
        }

        // Add candidate to key's list
        var candidates = cache[key] ?? []

        // Remove existing candidate with same messageID (re-indexing)
        candidates.removeAll { $0.messageID == messageID }

        // Append new candidate
        candidates.append(candidate)

        // Prune to max candidates (keep most recent)
        if candidates.count > maxCandidatesPerKey {
            candidates = Array(candidates.suffix(maxCandidatesPerKey))
        }

        cache[key] = candidates
    }

    /// Looks up candidates by cache key
    public func lookup(channelIndex: UInt8, senderName: String, messageHash: String) -> [MessageCandidate] {
        let key = MessageCacheKey(channelIndex: channelIndex, senderName: senderName, messageHash: messageHash)
        return cache[key] ?? []
    }

    /// Clears the cache
    public func clear() {
        cache.removeAll()
        order.removeAll()
    }
}
