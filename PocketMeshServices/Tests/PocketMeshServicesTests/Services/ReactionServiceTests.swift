import Foundation
import Testing
@testable import PocketMeshServices

@Suite("ReactionService Tests")
struct ReactionServiceTests {

    @Test("Builds correct wire format with Crockford Base32 identifier")
    func buildsWireFormat() async {
        let service = ReactionService()
        let timestamp: UInt32 = 1704067200

        let text = service.buildReactionText(
            emoji: "👍",
            targetSender: "AlphaNode",
            targetText: "What's the situation at Main St today?",
            targetTimestamp: timestamp
        )

        // Verify format: {emoji} @[{sender}] {preview} [XXXXXXXX]
        #expect(text.hasPrefix("👍 @[AlphaNode] What's the situation at..."))
        #expect(text.contains(" ["))
        #expect(text.hasSuffix("]"))

        // Verify 8-char Crockford Base32 identifier is present (lowercase)
        let idPattern = #/\[([0-9a-hj-km-np-tv-z]{8})\]$/#
        #expect(text.firstMatch(of: idPattern) != nil)
    }

    @Test("Builds wire format with short message")
    func buildsWireFormatShortMessage() async {
        let service = ReactionService()
        let timestamp: UInt32 = 1704067200

        let text = service.buildReactionText(
            emoji: "❤️",
            targetSender: "Node",
            targetText: "ok",
            targetTimestamp: timestamp
        )

        #expect(text.contains("@[Node] ok"))
        #expect(text.hasSuffix("]"))
    }

    @Test("Generated identifier is consistent")
    func generatedIdentifierIsConsistent() async {
        let service = ReactionService()
        let timestamp: UInt32 = 1704067200
        let targetText = "Hello world"

        let text1 = service.buildReactionText(
            emoji: "👍",
            targetSender: "Node",
            targetText: targetText,
            targetTimestamp: timestamp
        )

        let text2 = service.buildReactionText(
            emoji: "👍",
            targetSender: "Node",
            targetText: targetText,
            targetTimestamp: timestamp
        )

        #expect(text1 == text2)
    }

    @Test("Different timestamps produce different identifiers")
    func differentTimestampsDifferentIdentifiers() async {
        let service = ReactionService()
        let targetText = "Hello world"

        let text1 = service.buildReactionText(
            emoji: "👍",
            targetSender: "Node",
            targetText: targetText,
            targetTimestamp: 1704067200
        )

        let text2 = service.buildReactionText(
            emoji: "👍",
            targetSender: "Node",
            targetText: targetText,
            targetTimestamp: 1704067201
        )

        #expect(text1 != text2)
    }

    // MARK: - Disambiguation Tests

    @Test("Finds indexed message by hash and preview")
    func findsIndexedMessage() async {
        let service = ReactionService()
        let messageID = UUID()
        let timestamp: UInt32 = 1704067200

        await service.indexMessage(
            id: messageID,
            channelIndex: 0,
            senderName: "Node",
            text: "Hello world",
            timestamp: timestamp
        )

        let reactionText = service.buildReactionText(
            emoji: "👍",
            targetSender: "Node",
            targetText: "Hello world",
            targetTimestamp: timestamp
        )

        let parsed = ReactionParser.parse(reactionText)!
        let foundID = await service.findTargetMessage(parsed: parsed, channelIndex: 0)

        #expect(foundID == messageID)
    }

    @Test("Returns nil when no candidates exist")
    func returnsNilWhenNoCandidates() async {
        let service = ReactionService()

        let parsed = ParsedReaction(
            emoji: "👍",
            targetSender: "Node",
            contentPreview: "Hello",
            messageHash: "ABCD1234"
        )

        let foundID = await service.findTargetMessage(parsed: parsed, channelIndex: 0)

        #expect(foundID == nil)
    }

    @Test("Disambiguates by preview when multiple candidates have same hash")
    func disambiguatesByPreview() async {
        let service = ReactionService()
        let id1 = UUID()
        let id2 = UUID()
        let timestamp: UInt32 = 1704067200

        // Index two messages with same hash but different text
        // (In reality this would be rare, but we simulate it by indexing with same params)
        await service.indexMessage(
            id: id1,
            channelIndex: 0,
            senderName: "Node",
            text: "Message one",
            timestamp: timestamp
        )

        await service.indexMessage(
            id: id2,
            channelIndex: 0,
            senderName: "Node",
            text: "Message two",
            timestamp: timestamp
        )

        // Build reaction for second message
        let reactionText = service.buildReactionText(
            emoji: "👍",
            targetSender: "Node",
            targetText: "Message two",
            targetTimestamp: timestamp
        )

        let parsed = ReactionParser.parse(reactionText)!
        let foundID = await service.findTargetMessage(parsed: parsed, channelIndex: 0)

        // Should find the second message based on preview match
        #expect(foundID == id2)
    }

    @Test("Returns nil when preview doesn't match any candidate (fail-safe)")
    func returnsNilWhenPreviewDoesntMatch() async {
        let service = ReactionService()
        let messageID = UUID()
        let timestamp: UInt32 = 1704067200

        await service.indexMessage(
            id: messageID,
            channelIndex: 0,
            senderName: "Node",
            text: "Original message",
            timestamp: timestamp
        )

        // Create a parsed reaction with wrong preview but matching hash
        let hash = ReactionParser.generateMessageHash(text: "Original message", timestamp: timestamp)
        let parsed = ParsedReaction(
            emoji: "👍",
            targetSender: "Node",
            contentPreview: "Different preview",
            messageHash: hash
        )

        let foundID = await service.findTargetMessage(parsed: parsed, channelIndex: 0)

        // Should return nil because preview doesn't match
        #expect(foundID == nil)
    }

    @Test("Picks most recently indexed when multiple candidates match preview")
    func picksMostRecentWhenMultipleMatch() async {
        let service = ReactionService()
        let id1 = UUID()
        let id2 = UUID()
        let timestamp: UInt32 = 1704067200

        // Index two messages with identical text (same hash and same preview)
        await service.indexMessage(
            id: id1,
            channelIndex: 0,
            senderName: "Node",
            text: "Same message",
            timestamp: timestamp
        )

        // Small delay to ensure different indexedAt times
        try? await Task.sleep(for: .milliseconds(10))

        await service.indexMessage(
            id: id2,
            channelIndex: 0,
            senderName: "Node",
            text: "Same message",
            timestamp: timestamp
        )

        let reactionText = service.buildReactionText(
            emoji: "👍",
            targetSender: "Node",
            targetText: "Same message",
            targetTimestamp: timestamp
        )

        let parsed = ReactionParser.parse(reactionText)!
        let foundID = await service.findTargetMessage(parsed: parsed, channelIndex: 0)

        // Should find the most recently indexed (id2)
        #expect(foundID == id2)
    }

    // MARK: - Pending Reactions Queue Tests

    @Test("Queued reaction matches when message indexed")
    func queuedReactionMatchesWhenMessageIndexed() async {
        let service = ReactionService()
        let messageID = UUID()
        let deviceID = UUID()
        let timestamp: UInt32 = 1704067200

        // Build reaction text for a message that doesn't exist yet
        let reactionText = service.buildReactionText(
            emoji: "👍",
            targetSender: "AlphaNode",
            targetText: "Hello world",
            targetTimestamp: timestamp
        )

        let parsed = ReactionParser.parse(reactionText)!

        // Queue the reaction (target message not indexed yet)
        await service.queuePendingReaction(
            parsed: parsed,
            channelIndex: 0,
            senderNodeName: "BetaNode",
            rawText: reactionText,
            deviceID: deviceID
        )

        // Now index the target message - should return the pending reaction
        let matches = await service.indexMessage(
            id: messageID,
            channelIndex: 0,
            senderName: "AlphaNode",
            text: "Hello world",
            timestamp: timestamp
        )

        #expect(matches.count == 1)
        #expect(matches.first?.parsed.emoji == "👍")
        #expect(matches.first?.senderNodeName == "BetaNode")
    }

    @Test("Multiple reactions for same target all match")
    func multipleReactionsForSameTargetAllMatch() async {
        let service = ReactionService()
        let messageID = UUID()
        let deviceID = UUID()
        let timestamp: UInt32 = 1704067200

        // Queue multiple reactions for the same message
        for emoji in ["👍", "❤️", "😂"] {
            let reactionText = service.buildReactionText(
                emoji: emoji,
                targetSender: "AlphaNode",
                targetText: "Hello world",
                targetTimestamp: timestamp
            )
            let parsed = ReactionParser.parse(reactionText)!

            await service.queuePendingReaction(
                parsed: parsed,
                channelIndex: 0,
                senderNodeName: "BetaNode",
                rawText: reactionText,
                deviceID: deviceID
            )
        }

        // Index the target message - should return all pending reactions
        let matches = await service.indexMessage(
            id: messageID,
            channelIndex: 0,
            senderName: "AlphaNode",
            text: "Hello world",
            timestamp: timestamp
        )

        #expect(matches.count == 3)
        let emojis = Set(matches.map { $0.parsed.emoji })
        #expect(emojis == ["👍", "❤️", "😂"])
    }

    @Test("Preview mismatch prevents false match")
    func previewMismatchPreventsFalseMatch() async {
        let service = ReactionService()
        let messageID = UUID()
        let deviceID = UUID()
        let timestamp: UInt32 = 1704067200

        // Queue a reaction for "Hello world"
        let reactionText = service.buildReactionText(
            emoji: "👍",
            targetSender: "AlphaNode",
            targetText: "Hello world",
            targetTimestamp: timestamp
        )
        let parsed = ReactionParser.parse(reactionText)!

        await service.queuePendingReaction(
            parsed: parsed,
            channelIndex: 0,
            senderNodeName: "BetaNode",
            rawText: reactionText,
            deviceID: deviceID
        )

        // Index a different message with same hash but different text
        // (simulating a hash collision)
        let matches = await service.indexMessage(
            id: messageID,
            channelIndex: 0,
            senderName: "AlphaNode",
            text: "Different text",
            timestamp: timestamp
        )

        // Should NOT match because preview doesn't match
        #expect(matches.isEmpty)
    }

    @Test("Clear removes all pending reactions")
    func clearRemovesAllPending() async {
        let service = ReactionService()
        let messageID = UUID()
        let deviceID = UUID()
        let timestamp: UInt32 = 1704067200

        // Queue a reaction
        let reactionText = service.buildReactionText(
            emoji: "👍",
            targetSender: "AlphaNode",
            targetText: "Hello world",
            targetTimestamp: timestamp
        )
        let parsed = ReactionParser.parse(reactionText)!

        await service.queuePendingReaction(
            parsed: parsed,
            channelIndex: 0,
            senderNodeName: "BetaNode",
            rawText: reactionText,
            deviceID: deviceID
        )

        // Clear all pending
        await service.clearPendingReactions()

        // Index the target message - should return nothing
        let matches = await service.indexMessage(
            id: messageID,
            channelIndex: 0,
            senderName: "AlphaNode",
            text: "Hello world",
            timestamp: timestamp
        )

        #expect(matches.isEmpty)
    }

    @Test("Pending reactions are scoped by channel")
    func pendingReactionsScopedByChannel() async {
        let service = ReactionService()
        let messageID = UUID()
        let deviceID = UUID()
        let timestamp: UInt32 = 1704067200

        // Queue a reaction for channel 0
        let reactionText = service.buildReactionText(
            emoji: "👍",
            targetSender: "AlphaNode",
            targetText: "Hello world",
            targetTimestamp: timestamp
        )
        let parsed = ReactionParser.parse(reactionText)!

        await service.queuePendingReaction(
            parsed: parsed,
            channelIndex: 0,
            senderNodeName: "BetaNode",
            rawText: reactionText,
            deviceID: deviceID
        )

        // Index on channel 1 - should NOT match
        let matchesChannel1 = await service.indexMessage(
            id: messageID,
            channelIndex: 1,
            senderName: "AlphaNode",
            text: "Hello world",
            timestamp: timestamp
        )

        #expect(matchesChannel1.isEmpty)

        // Index on channel 0 - should match
        let matchesChannel0 = await service.indexMessage(
            id: messageID,
            channelIndex: 0,
            senderName: "AlphaNode",
            text: "Hello world",
            timestamp: timestamp
        )

        #expect(matchesChannel0.count == 1)
    }
}
