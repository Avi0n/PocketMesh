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
}
