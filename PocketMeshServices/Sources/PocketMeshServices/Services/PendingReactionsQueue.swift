import Foundation

/// Entry in the pending reactions queue
public struct PendingReactionEntry: Sendable {
    public let parsed: ParsedReaction
    public let channelIndex: UInt8
    public let rawText: String
    public let addedAt: Date

    public init(parsed: ParsedReaction, channelIndex: UInt8, rawText: String, addedAt: Date = Date()) {
        self.parsed = parsed
        self.channelIndex = channelIndex
        self.rawText = rawText
        self.addedAt = addedAt
    }
}

/// Queue for reactions awaiting target message arrival.
/// Entries expire after TTL and fall back to regular message display.
public actor PendingReactionsQueue {
    private var entries: [PendingReactionEntry] = []
    private let ttlSeconds: TimeInterval
    private let maxEntries: Int

    public init(ttlSeconds: TimeInterval = 60, maxEntries: Int = 50) {
        self.ttlSeconds = ttlSeconds
        self.maxEntries = maxEntries
    }

    /// Adds a parsed reaction to the pending queue
    public func add(_ parsed: ParsedReaction, channelIndex: UInt8, rawText: String) {
        // Evict oldest if at capacity
        if entries.count >= maxEntries {
            entries.removeFirst()
        }

        entries.append(PendingReactionEntry(
            parsed: parsed,
            channelIndex: channelIndex,
            rawText: rawText
        ))
    }

    /// Returns all pending entries (for matching attempts)
    public func allPending() -> [PendingReactionEntry] {
        entries
    }

    /// Removes and returns expired entries (for fallback display)
    public func expireOldEntries() -> [PendingReactionEntry] {
        let now = Date()
        let expired = entries.filter { now.timeIntervalSince($0.addedAt) >= ttlSeconds }
        entries.removeAll { now.timeIntervalSince($0.addedAt) >= ttlSeconds }
        return expired
    }

    /// Removes a matched entry from the queue
    public func removeMatched(messageHash: String, channelIndex: UInt8) {
        entries.removeAll { entry in
            entry.channelIndex == channelIndex &&
            entry.parsed.messageHash == messageHash
        }
    }

    /// Clears all entries
    public func clear() {
        entries.removeAll()
    }
}
