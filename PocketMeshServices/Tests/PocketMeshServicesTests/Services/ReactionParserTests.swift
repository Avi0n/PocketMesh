import Foundation
import Testing
@testable import PocketMeshServices

@Suite("ReactionParser Tests")
struct ReactionParserTests {

    // MARK: - Valid Format Tests

    @Test("Parses simple reaction with thumbs up")
    func parsesSimpleReaction() {
        let text = "👍 @[AlphaNode] What's the situation at... [7f3a9c12]"
        let result = ReactionParser.parse(text)

        #expect(result != nil)
        #expect(result?.emoji == "👍")
        #expect(result?.targetSender == "AlphaNode")
        #expect(result?.contentPreview == "What's the situation at...")
        #expect(result?.messageHash == "7f3a9c12")
    }

    @Test("Parses reaction with heart emoji")
    func parsesHeartReaction() {
        let text = "❤️ @[BetaNode] ok [e4d8b1a0]"
        let result = ReactionParser.parse(text)

        #expect(result != nil)
        #expect(result?.emoji == "❤️")
        #expect(result?.targetSender == "BetaNode")
        #expect(result?.contentPreview == "ok")
        #expect(result?.messageHash == "e4d8b1a0")
    }

    @Test("Parses reaction to emoji-only message")
    func parsesReactionToEmojiMessage() {
        let text = "😂 @[GammaNode] 👍 [2c5f8e77]"
        let result = ReactionParser.parse(text)

        #expect(result != nil)
        #expect(result?.emoji == "😂")
        #expect(result?.targetSender == "GammaNode")
        #expect(result?.contentPreview == "👍")
        #expect(result?.messageHash == "2c5f8e77")
    }

    @Test("Parses reaction with uppercase identifier and normalizes to lowercase")
    func parsesUppercaseIdentifier() {
        let text = "👍 @[Node] hello [ABCDEF12]"
        let result = ReactionParser.parse(text)

        #expect(result != nil)
        #expect(result?.messageHash == "abcdef12")
    }

    @Test("Parses reaction with mixed case identifier")
    func parsesMixedCaseIdentifier() {
        let text = "👍 @[Node] hello [AbCdEf12]"
        let result = ReactionParser.parse(text)

        #expect(result != nil)
        #expect(result?.messageHash == "abcdef12")
    }

    // MARK: - Crockford Base32 Identifier Tests

    @Test("Generates 8-character Crockford Base32 identifier")
    func generatesEightCharBase32() {
        let hash = ReactionParser.generateMessageHash(text: "Hello", timestamp: 1704067200)
        #expect(hash.count == 8)
        // Verify all characters are valid Crockford Base32 (lowercase)
        let validChars = CharacterSet(charactersIn: "0123456789abcdefghjkmnpqrstvwxyz")
        #expect(hash.unicodeScalars.allSatisfy { validChars.contains($0) })
    }

    @Test("Same input produces same identifier")
    func sameInputSameHash() {
        let hash1 = ReactionParser.generateMessageHash(text: "Hello", timestamp: 1704067200)
        let hash2 = ReactionParser.generateMessageHash(text: "Hello", timestamp: 1704067200)
        #expect(hash1 == hash2)
    }

    @Test("Different text produces different identifier")
    func differentTextDifferentHash() {
        let hash1 = ReactionParser.generateMessageHash(text: "Hello", timestamp: 1704067200)
        let hash2 = ReactionParser.generateMessageHash(text: "World", timestamp: 1704067200)
        #expect(hash1 != hash2)
    }

    @Test("Different timestamp produces different identifier")
    func differentTimestampDifferentHash() {
        let hash1 = ReactionParser.generateMessageHash(text: "Hello", timestamp: 1704067200)
        let hash2 = ReactionParser.generateMessageHash(text: "Hello", timestamp: 1704067201)
        #expect(hash1 != hash2)
    }

    @Test("Crockford O is decoded as 0")
    func crockfordODecodesAsZero() {
        let text = "👍 @[Node] hello [OOOOOOOO]"
        let result = ReactionParser.parse(text)

        #expect(result != nil)
        #expect(result?.messageHash == "00000000")
    }

    @Test("Crockford I/L are decoded as 1")
    func crockfordILDecodeAsOne() {
        let textI = "👍 @[Node] hello [iiiiiiii]"
        let resultI = ReactionParser.parse(textI)
        #expect(resultI?.messageHash == "11111111")

        let textL = "👍 @[Node] hello [LLLLLLLL]"
        let resultL = ReactionParser.parse(textL)
        #expect(resultL?.messageHash == "11111111")
    }

    // MARK: - Edge Cases

    @Test("Parses sender name containing colon")
    func parsesSenderWithColon() {
        let text = "👍 @[Node:Alpha] Hello world... [a1b2c3d4]"
        let result = ReactionParser.parse(text)

        #expect(result != nil)
        #expect(result?.targetSender == "Node:Alpha")
        #expect(result?.contentPreview == "Hello world...")
    }

    // MARK: - Invalid Format Tests

    @Test("Returns nil for plain text message")
    func returnsNilForPlainText() {
        let text = "Just a normal message"
        #expect(ReactionParser.parse(text) == nil)
    }

    @Test("Returns nil for missing identifier")
    func returnsNilForMissingHash() {
        let text = "👍 @[Node] Hello"
        #expect(ReactionParser.parse(text) == nil)
    }

    @Test("Returns nil for missing @ symbol")
    func returnsNilForMissingAt() {
        let text = "👍 [Node] Hello [a1b2c3d4]"
        #expect(ReactionParser.parse(text) == nil)
    }

    @Test("Returns nil for missing brackets around sender")
    func returnsNilForMissingBrackets() {
        let text = "👍 @Node Hello [a1b2c3d4]"
        #expect(ReactionParser.parse(text) == nil)
    }

    @Test("Returns nil for invalid identifier length")
    func returnsNilForInvalidHashLength() {
        let text = "👍 @[Node] Hello [abc]"
        #expect(ReactionParser.parse(text) == nil)
    }

    @Test("Returns nil for invalid Crockford characters (U)")
    func returnsNilForInvalidCrockfordU() {
        let text = "👍 @[Node] Hello [uuuuuuuu]"
        #expect(ReactionParser.parse(text) == nil)
    }

    @Test("Returns nil for empty sender")
    func returnsNilForEmptySender() {
        let text = "👍 @[] Hello [a1b2c3d4]"
        #expect(ReactionParser.parse(text) == nil)
    }

    @Test("Returns nil for empty content preview")
    func returnsNilForEmptyContent() {
        let text = "👍 @[Node]  [a1b2c3d4]"
        #expect(ReactionParser.parse(text) == nil)
    }

    @Test("Returns nil for text not starting with emoji")
    func returnsNilForNonEmojiStart() {
        let text = "A @[Node] Hello [a1b2c3d4]"
        #expect(ReactionParser.parse(text) == nil)
    }

    // MARK: - ZWJ Emoji Tests

    @Test("Parses reaction with skin tone modifier")
    func parsesEmojiWithSkinTone() {
        let text = "👍🏽 @[Node] Hello [a1b2c3d4]"
        let result = ReactionParser.parse(text)

        #expect(result != nil)
        #expect(result?.emoji == "👍🏽")
    }

    @Test("Parses reaction with family ZWJ emoji")
    func parsesFamilyEmoji() {
        let text = "👨‍👩‍👧 @[Node] Hello [a1b2c3d4]"
        let result = ReactionParser.parse(text)

        #expect(result != nil)
        #expect(result?.emoji == "👨‍👩‍👧")
    }

    @Test("Parses reaction with flag emoji")
    func parsesFlagEmoji() {
        let text = "🇺🇸 @[Node] Hello [a1b2c3d4]"
        let result = ReactionParser.parse(text)

        #expect(result != nil)
        #expect(result?.emoji == "🇺🇸")
    }

    // MARK: - Content Preview Generation Tests

    @Test("Returns full text when it fits")
    func generatesPreviewFullText() {
        let text = "This is four words"
        let preview = ReactionParser.generateContentPreview(text, maxBytes: 100)
        #expect(preview == "This is four words")
    }

    @Test("Returns short message unchanged")
    func generatesPreviewShortMessage() {
        let text = "ok"
        let preview = ReactionParser.generateContentPreview(text, maxBytes: 100)
        #expect(preview == "ok")
    }

    @Test("Returns single emoji unchanged")
    func generatesPreviewSingleEmoji() {
        let text = "👍"
        let preview = ReactionParser.generateContentPreview(text, maxBytes: 100)
        #expect(preview == "👍")
    }

    @Test("Truncates by character when byte limit exceeded")
    func truncatesByCharacter() {
        let text = "Hello world"
        // "Hello..." = 8 bytes, allow 10
        let preview = ReactionParser.generateContentPreview(text, maxBytes: 10)
        #expect(preview.utf8.count <= 10)
        #expect(preview.hasSuffix("..."))
        #expect(preview == "Hello w...")
    }

    @Test("Truncates long word by character")
    func truncatesLongWord() {
        let text = "Supercalifragilisticexpialidocious"
        let preview = ReactionParser.generateContentPreview(text, maxBytes: 10)
        #expect(preview.utf8.count <= 10)
        #expect(preview.hasSuffix("..."))
        #expect(preview == "Superc...")
    }

    @Test("Handles Chinese text truncation")
    func truncatesChineseText() {
        let text = "你好世界这是一条很长的消息"  // Each char is 3 bytes
        // Allow 15 bytes: 4 chars (12 bytes) + "..." (3 bytes) = 15
        let preview = ReactionParser.generateContentPreview(text, maxBytes: 15)
        #expect(preview.utf8.count <= 15)
        #expect(preview.hasSuffix("..."))
        #expect(preview == "你好世界...")
    }

    @Test("Handles Japanese text truncation")
    func truncatesJapaneseText() {
        let text = "こんにちは世界"  // Mixed 3-byte chars
        let preview = ReactionParser.generateContentPreview(text, maxBytes: 12)
        #expect(preview.utf8.count <= 12)
        #expect(preview.hasSuffix("..."))
    }

    @Test("Handles emoji in middle of text")
    func truncatesTextWithEmoji() {
        let text = "Hello 👋 world"
        let preview = ReactionParser.generateContentPreview(text, maxBytes: 15)
        #expect(preview.utf8.count <= 15)
        #expect(preview.hasSuffix("..."))
    }

    @Test("Returns ellipsis when maxBytes is very small")
    func returnsEllipsisWhenTiny() {
        let text = "Hello"
        let preview = ReactionParser.generateContentPreview(text, maxBytes: 4)
        #expect(preview.utf8.count <= 4)
    }

    // MARK: - Summary Cache Tests

    @Test("Builds summary from reactions")
    func buildsSummary() {
        let reactions = [
            ("👍", 3),
            ("❤️", 2),
            ("😂", 1)
        ]
        let summary = ReactionParser.buildSummary(from: reactions)
        #expect(summary == "👍:3,❤️:2,😂:1")
    }

    @Test("Parses summary string")
    func parsesSummary() {
        let summary = "👍:3,❤️:2,😂:1"
        let parsed = ReactionParser.parseSummary(summary)

        #expect(parsed.count == 3)
        #expect(parsed[0] == ("👍", 3))
        #expect(parsed[1] == ("❤️", 2))
        #expect(parsed[2] == ("😂", 1))
    }

    @Test("Parses empty summary")
    func parsesEmptySummary() {
        let parsed = ReactionParser.parseSummary(nil)
        #expect(parsed.isEmpty)
    }

    @Test("Sorts summary by count descending")
    func sortsSummaryByCount() {
        let reactions = [
            ("😂", 1),
            ("👍", 5),
            ("❤️", 3)
        ]
        let summary = ReactionParser.buildSummary(from: reactions)
        #expect(summary == "👍:5,❤️:3,😂:1")
    }
}
