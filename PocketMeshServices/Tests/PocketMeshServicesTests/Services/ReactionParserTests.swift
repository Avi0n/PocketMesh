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

    // MARK: - Edge Cases (Task 4)

    @Test("Parses sender name containing colon")
    func parsesSenderWithColon() {
        let text = "👍 @Node:Alpha: Hello world... [a1b2c3d4]"
        let result = ReactionParser.parse(text)

        #expect(result != nil)
        #expect(result?.targetSender == "Node:Alpha")
        #expect(result?.contentPreview == "Hello world...")
    }

    // MARK: - Invalid Format Tests (Task 5)

    @Test("Returns nil for plain text message")
    func returnsNilForPlainText() {
        let text = "Just a normal message"
        #expect(ReactionParser.parse(text) == nil)
    }

    @Test("Returns nil for missing hash")
    func returnsNilForMissingHash() {
        let text = "👍 @Node: Hello"
        #expect(ReactionParser.parse(text) == nil)
    }

    @Test("Returns nil for missing @ symbol")
    func returnsNilForMissingAt() {
        let text = "👍 Node: Hello [a1b2c3d4]"
        #expect(ReactionParser.parse(text) == nil)
    }

    @Test("Returns nil for missing colon after sender")
    func returnsNilForMissingColon() {
        let text = "👍 @Node Hello [a1b2c3d4]"
        #expect(ReactionParser.parse(text) == nil)
    }

    @Test("Returns nil for invalid hash (wrong length)")
    func returnsNilForInvalidHashLength() {
        let text = "👍 @Node: Hello [abc]"
        #expect(ReactionParser.parse(text) == nil)
    }

    @Test("Returns nil for invalid hash (uppercase)")
    func returnsNilForUppercaseHash() {
        let text = "👍 @Node: Hello [A1B2C3D4]"
        #expect(ReactionParser.parse(text) == nil)
    }

    @Test("Returns nil for empty sender")
    func returnsNilForEmptySender() {
        let text = "👍 @: Hello [a1b2c3d4]"
        #expect(ReactionParser.parse(text) == nil)
    }

    @Test("Returns nil for empty content preview")
    func returnsNilForEmptyContent() {
        let text = "👍 @Node:  [a1b2c3d4]"
        #expect(ReactionParser.parse(text) == nil)
    }

    @Test("Returns nil for text not starting with emoji")
    func returnsNilForNonEmojiStart() {
        let text = "A @Node: Hello [a1b2c3d4]"
        #expect(ReactionParser.parse(text) == nil)
    }

    // MARK: - ZWJ Emoji Tests (Task 6)

    @Test("Parses reaction with skin tone modifier")
    func parsesEmojiWithSkinTone() {
        let text = "👍🏽 @Node: Hello [a1b2c3d4]"
        let result = ReactionParser.parse(text)

        #expect(result != nil)
        #expect(result?.emoji == "👍🏽")
    }

    @Test("Parses reaction with family ZWJ emoji")
    func parsesFamilyEmoji() {
        let text = "👨‍👩‍👧 @Node: Hello [a1b2c3d4]"
        let result = ReactionParser.parse(text)

        #expect(result != nil)
        #expect(result?.emoji == "👨‍👩‍👧")
    }

    @Test("Parses reaction with flag emoji")
    func parsesFlagEmoji() {
        let text = "🇺🇸 @Node: Hello [a1b2c3d4]"
        let result = ReactionParser.parse(text)

        #expect(result != nil)
        #expect(result?.emoji == "🇺🇸")
    }

    // MARK: - Content Preview Generation Tests

    @Test("Generates preview with 4 words truncated")
    func generatesPreviewTruncated() {
        let text = "What's the situation at Main St today?"
        let preview = ReactionParser.generateContentPreview(text)
        #expect(preview == "What's the situation at...")
    }

    @Test("Generates preview with exact 4 words")
    func generatesPreviewExactFourWords() {
        let text = "This is four words"
        let preview = ReactionParser.generateContentPreview(text)
        #expect(preview == "This is four words")
    }

    @Test("Generates preview with less than 4 words")
    func generatesPreviewShortMessage() {
        let text = "ok"
        let preview = ReactionParser.generateContentPreview(text)
        #expect(preview == "ok")
    }

    @Test("Generates preview with single character")
    func generatesPreviewSingleChar() {
        let text = "👍"
        let preview = ReactionParser.generateContentPreview(text)
        #expect(preview == "👍")
    }

    @Test("Generates preview with 3 words")
    func generatesPreviewThreeWords() {
        let text = "Hello there friend"
        let preview = ReactionParser.generateContentPreview(text)
        #expect(preview == "Hello there friend")
    }
}
