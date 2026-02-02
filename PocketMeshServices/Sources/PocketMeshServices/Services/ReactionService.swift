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
    public func indexMessage(id: UUID, channelIndex: UInt8, senderName: String, text: String, timestamp: UInt32) async {
        await messageCache.index(messageID: id, channelIndex: channelIndex, senderName: senderName, text: text, timestamp: timestamp)
    }

    /// Builds reaction wire format text for sending
    /// Format: `{emoji} @[{sender}] {preview} [xxxxxxxx]`
    public nonisolated func buildReactionText(
        emoji: String,
        targetSender: String,
        targetText: String,
        targetTimestamp: UInt32
    ) -> String {
        let preview = ReactionParser.generateContentPreview(targetText)
        let hash = ReactionParser.generateMessageHash(text: targetText, timestamp: targetTimestamp)
        return "\(emoji) @[\(targetSender)] \(preview) [\(hash)]"
    }

    /// Finds target message ID for a parsed reaction (O(1) cache lookup)
    public func findTargetMessage(parsed: ParsedReaction, channelIndex: UInt8) async -> UUID? {
        await messageCache.lookup(
            channelIndex: channelIndex,
            senderName: parsed.targetSender,
            messageHash: parsed.messageHash
        )
    }

    /// Attempts to process incoming text as a reaction
    /// Returns true if handled as reaction, false to process as regular message
    public nonisolated func tryProcessAsReaction(_ text: String) -> ParsedReaction? {
        ReactionParser.parse(text)
    }
}
