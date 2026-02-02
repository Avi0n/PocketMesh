import Foundation
import Testing
@testable import PocketMeshServices

@Suite("ReactionService Tests")
struct ReactionServiceTests {

    @Test("Builds correct wire format with hash")
    func buildsWireFormat() async {
        let service = ReactionService()
        let timestamp: UInt32 = 1704067200 // Unix timestamp

        let text = service.buildReactionText(
            emoji: "👍",
            targetSender: "AlphaNode",
            targetText: "What's the situation at Main St today?",
            targetTimestamp: timestamp
        )

        // Verify format: {emoji} @[{sender}] {preview} [xxxxxxxx]
        #expect(text.hasPrefix("👍 @[AlphaNode] What's the situation at..."))
        #expect(text.contains(" ["))
        #expect(text.hasSuffix("]"))

        // Verify 8-char hex hash is present
        let hashPattern = #/\[([0-9a-f]{8})\]$/#
        #expect(text.firstMatch(of: hashPattern) != nil)
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

    @Test("Generated hash is consistent")
    func generatedHashIsConsistent() async {
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

        // Same input produces same hash
        #expect(text1 == text2)
    }

    @Test("Different timestamps produce different hashes")
    func differentTimestampsDifferentHashes() async {
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

        // Different timestamps produce different hashes
        #expect(text1 != text2)
    }
}
