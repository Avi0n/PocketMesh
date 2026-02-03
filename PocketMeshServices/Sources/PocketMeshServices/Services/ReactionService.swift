import Foundation
import CryptoKit
import OSLog

/// Service for handling emoji reactions on channel messages
public actor ReactionService {
    private let logger = Logger(subsystem: "PocketMeshServices", category: "ReactionService")
    private let pendingQueue: PendingReactionsQueue
    private let messageCache: MessageLRUCache

    public init(
        pendingQueue: PendingReactionsQueue = PendingReactionsQueue(),
        messageCache: MessageLRUCache = MessageLRUCache()
    ) {
        self.pendingQueue = pendingQueue
        self.messageCache = messageCache
    }

    /// Indexes a message for reaction matching (call when message received)
    public func indexMessage(
        id: UUID,
        channelIndex: UInt8,
        senderName: String,
        text: String,
        timestamp: UInt32
    ) async {
        await messageCache.index(
            messageID: id,
            channelIndex: channelIndex,
            senderName: senderName,
            text: text,
            timestamp: timestamp
        )
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

        // Calculate available bytes for preview
        // Format: {emoji} @[{sender}] {preview} [xxxxxxxx]
        // Fixed overhead: " @[" (3) + "] " (2) + " [" (2) + "]" (1) + identifier (8) = 16
        // Channel message limit: 147 bytes (matches official MeshCore app)
        let fixedOverhead = 16
        let maxMessageBytes = 147
        let availableForPreview = maxMessageBytes - emoji.utf8.count - targetSender.utf8.count - fixedOverhead

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

        // Calculate preview bytes limit matching buildReactionText
        // Format: {emoji} @[{sender}] {preview} [xxxxxxxx]
        // Fixed overhead: " @[" (3) + "] " (2) + " [" (2) + "]" (1) + identifier (8) = 16
        // Channel message limit: 147 bytes (matches official MeshCore app)
        let fixedOverhead = 16
        let maxMessageBytes = 147
        let maxPreviewBytes = maxMessageBytes - parsed.emoji.utf8.count - parsed.targetSender.utf8.count - fixedOverhead

        // Find candidates whose preview matches
        let matches = candidates.filter { candidate in
            let preview = ReactionParser.generateContentPreview(candidate.text, maxBytes: maxPreviewBytes)
            return preview == parsed.contentPreview
        }

        // Return most recently indexed match, or nil if no match
        return matches.max(by: { $0.indexedAt < $1.indexedAt })?.messageID
    }

    /// Attempts to process incoming text as a reaction
    /// Returns true if handled as reaction, false to process as regular message
    public nonisolated func tryProcessAsReaction(_ text: String) -> ParsedReaction? {
        ReactionParser.parse(text)
    }
}
