import Foundation
import Testing
@testable import PocketMeshServices

@Suite("ReactionParser Tests")
struct ReactionParserTests {

    // MARK: - Valid Format Tests

    @Test("Parses simple reaction with thumbs up")
    func parsesSimpleReaction() {
        let text = "👍 @AlphaNode: What's the situation at... [7f3a9c12]"
        let result = ReactionParser.parse(text)

        #expect(result != nil)
        #expect(result?.emoji == "👍")
        #expect(result?.targetSender == "AlphaNode")
        #expect(result?.contentPreview == "What's the situation at...")
        #expect(result?.messageHash == "7f3a9c12")
    }

    @Test("Parses reaction with heart emoji")
    func parsesHeartReaction() {
        let text = "❤️ @BetaNode: ok [e4d8b1a0]"
        let result = ReactionParser.parse(text)

        #expect(result != nil)
        #expect(result?.emoji == "❤️")
        #expect(result?.targetSender == "BetaNode")
        #expect(result?.contentPreview == "ok")
        #expect(result?.messageHash == "e4d8b1a0")
    }

    @Test("Parses reaction to emoji-only message")
    func parsesReactionToEmojiMessage() {
        let text = "😂 @GammaNode: 👍 [2c5f8e77]"
        let result = ReactionParser.parse(text)

        #expect(result != nil)
        #expect(result?.emoji == "😂")
        #expect(result?.targetSender == "GammaNode")
        #expect(result?.contentPreview == "👍")
        #expect(result?.messageHash == "2c5f8e77")
    }

    @Test("Parses reaction with all lowercase hash")
    func parsesLowercaseHash() {
        let text = "👍 @Node: hello [abcdef12]"
        let result = ReactionParser.parse(text)

        #expect(result != nil)
        #expect(result?.messageHash == "abcdef12")
    }

    // MARK: - Hash Generation Tests

    @Test("Generates 8-character hex hash")
    func generatesEightCharHash() {
        let hash = ReactionParser.generateMessageHash(text: "Hello", timestamp: 1704067200)
        #expect(hash.count == 8)
        #expect(hash.allSatisfy { $0.isHexDigit })
    }

    @Test("Same input produces same hash")
    func sameInputSameHash() {
        let hash1 = ReactionParser.generateMessageHash(text: "Hello", timestamp: 1704067200)
        let hash2 = ReactionParser.generateMessageHash(text: "Hello", timestamp: 1704067200)
        #expect(hash1 == hash2)
    }

    @Test("Different text produces different hash")
    func differentTextDifferentHash() {
        let hash1 = ReactionParser.generateMessageHash(text: "Hello", timestamp: 1704067200)
        let hash2 = ReactionParser.generateMessageHash(text: "World", timestamp: 1704067200)
        #expect(hash1 != hash2)
    }

    @Test("Different timestamp produces different hash")
    func differentTimestampDifferentHash() {
        let hash1 = ReactionParser.generateMessageHash(text: "Hello", timestamp: 1704067200)
        let hash2 = ReactionParser.generateMessageHash(text: "Hello", timestamp: 1704067201)
        #expect(hash1 != hash2)
    }
}
