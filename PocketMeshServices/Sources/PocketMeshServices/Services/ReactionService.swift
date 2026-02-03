import Foundation
import CryptoKit
import OSLog

/// A reaction waiting for its target message to be indexed
public struct PendingReaction: Sendable {
    public let parsed: ParsedReaction
    public let channelIndex: UInt8
    public let senderNodeName: String
    public let rawText: String
    public let deviceID: UUID
    public let receivedAt: Date
}

/// Service for handling emoji reactions on channel messages
public actor ReactionService {
    private let logger = Logger(subsystem: "PocketMeshServices", category: "ReactionService")
    private let messageCache: MessageLRUCache

    // Wire format: {emoji} @[{sender}] {preview} [xxxxxxxx]
    // Fixed overhead: " @[" (3) + "] " (2) + " [" (2) + "]" (1) + identifier (8) = 16
    // Channel message limit: 147 bytes (matches official MeshCore app)
    private static let fixedOverhead = 16
    private static let maxMessageBytes = 147
    private static let maxPendingReactions = 100

    // Pending reactions queue (Element X pattern: no TTL, session lifetime)
    private var pendingReactions: [PendingReactionKey: [PendingReaction]] = [:]
    private var pendingOrder: [PendingReactionKey] = []

    private struct PendingReactionKey: Hashable {
        let channelIndex: UInt8
        let targetSender: String
        let messageHash: String
    }

    /// Calculates available bytes for content preview in reaction wire format
    nonisolated static func previewBytesAvailable(emoji: String, senderName: String) -> Int {
        maxMessageBytes - emoji.utf8.count - senderName.utf8.count - fixedOverhead
    }

    public init(messageCache: MessageLRUCache = MessageLRUCache()) {
        self.messageCache = messageCache
    }

    /// Indexes a message for reaction matching and returns any pending reactions that now match
    public func indexMessage(
        id: UUID,
        channelIndex: UInt8,
        senderName: String,
        text: String,
        timestamp: UInt32
    ) async -> [PendingReaction] {
        await messageCache.index(
            messageID: id,
            channelIndex: channelIndex,
            senderName: senderName,
            text: text,
            timestamp: timestamp
        )

        // Check pending queue for matching reactions
        let hash = ReactionParser.generateMessageHash(text: text, timestamp: timestamp)
        let key = PendingReactionKey(
            channelIndex: channelIndex,
            targetSender: senderName,
            messageHash: hash
        )

        guard var candidates = pendingReactions[key] else {
            return []
        }

        // Filter by content preview match (same disambiguation as findTargetMessage)
        let matched = candidates.filter { pending in
            let maxPreviewBytes = Self.previewBytesAvailable(
                emoji: pending.parsed.emoji,
                senderName: senderName
            )
            let preview = ReactionParser.generateContentPreview(text, maxBytes: maxPreviewBytes)
            return preview == pending.parsed.contentPreview
        }

        // Remove matched from pending
        let matchedSet = Set(matched.map { "\($0.senderNodeName)-\($0.receivedAt.timeIntervalSince1970)" })
        candidates.removeAll { matchedSet.contains("\($0.senderNodeName)-\($0.receivedAt.timeIntervalSince1970)") }

        if candidates.isEmpty {
            pendingReactions.removeValue(forKey: key)
            pendingOrder.removeAll { $0 == key }
        } else {
            pendingReactions[key] = candidates
        }

        if !matched.isEmpty {
            logger.debug("Matched \(matched.count) pending reaction(s) to message \(id)")
        }

        return matched
    }

    /// Builds reaction wire format text for sending
    /// Format: `{emoji} @[{sender}] {preview} [xxxxxxxx]`
    public nonisolated func buildReactionText(
        emoji: String,
        targetSender: String,
        targetText: String,
        targetTimestamp: UInt32
    ) -> String {
        let hash = ReactionParser.generateMessageHash(text: targetText, timestamp: targetTimestamp)
        let availableForPreview = Self.previewBytesAvailable(emoji: emoji, senderName: targetSender)
        let preview = ReactionParser.generateContentPreview(targetText, maxBytes: availableForPreview)
        return "\(emoji) @[\(targetSender)] \(preview) [\(hash)]"
    }

    /// Finds target message ID for a parsed reaction using preview-based disambiguation
    public func findTargetMessage(parsed: ParsedReaction, channelIndex: UInt8) async -> UUID? {
        let candidates = await messageCache.lookup(
            channelIndex: channelIndex,
            senderName: parsed.targetSender,
            messageHash: parsed.messageHash
        )

        guard !candidates.isEmpty else { return nil }

        let maxPreviewBytes = Self.previewBytesAvailable(emoji: parsed.emoji, senderName: parsed.targetSender)
        let matches = candidates.filter { candidate in
            let preview = ReactionParser.generateContentPreview(candidate.text, maxBytes: maxPreviewBytes)
            return preview == parsed.contentPreview
        }

        return matches.max(by: { $0.indexedAt < $1.indexedAt })?.messageID
    }

    /// Attempts to process incoming text as a reaction
    /// Returns true if handled as reaction, false to process as regular message
    public nonisolated func tryProcessAsReaction(_ text: String) -> ParsedReaction? {
        ReactionParser.parse(text)
    }

    /// Queues a reaction that couldn't find its target message
    public func queuePendingReaction(
        parsed: ParsedReaction,
        channelIndex: UInt8,
        senderNodeName: String,
        rawText: String,
        deviceID: UUID
    ) {
        let key = PendingReactionKey(
            channelIndex: channelIndex,
            targetSender: parsed.targetSender,
            messageHash: parsed.messageHash
        )
        let pending = PendingReaction(
            parsed: parsed,
            channelIndex: channelIndex,
            senderNodeName: senderNodeName,
            rawText: rawText,
            deviceID: deviceID,
            receivedAt: Date()
        )

        if pendingReactions[key] != nil {
            pendingReactions[key]!.append(pending)
        } else {
            pendingReactions[key] = [pending]
            pendingOrder.append(key)
        }

        evictIfNeeded()
        logger.debug("Queued pending reaction \(parsed.emoji) for \(parsed.targetSender)")
    }

    /// Clears all pending reactions (call on disconnect)
    public func clearPendingReactions() {
        let count = pendingReactions.values.reduce(0) { $0 + $1.count }
        pendingReactions.removeAll()
        pendingOrder.removeAll()
        if count > 0 {
            logger.debug("Cleared \(count) pending reaction(s)")
        }
    }

    private func evictIfNeeded() {
        var totalCount = pendingReactions.values.reduce(0) { $0 + $1.count }

        while totalCount > Self.maxPendingReactions, let oldestKey = pendingOrder.first {
            if var entries = pendingReactions[oldestKey], !entries.isEmpty {
                entries.removeFirst()
                totalCount -= 1

                if entries.isEmpty {
                    pendingReactions.removeValue(forKey: oldestKey)
                    pendingOrder.removeFirst()
                } else {
                    pendingReactions[oldestKey] = entries
                }
            } else {
                pendingOrder.removeFirst()
            }
        }
    }
}
