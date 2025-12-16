import Testing
import Foundation
@testable import PocketMeshKit

@Suite("MentionUtilities Tests")
struct MentionUtilitiesTests {

    // MARK: - createMention Tests

    @Test("createMention creates correct format")
    func testCreateMention() {
        let mention = MentionUtilities.createMention(for: "Alice")
        #expect(mention == "@[Alice]")
    }

    @Test("createMention handles names with spaces")
    func testCreateMentionWithSpaces() {
        let mention = MentionUtilities.createMention(for: "My Node")
        #expect(mention == "@[My Node]")
    }

    @Test("createMention handles special characters")
    func testCreateMentionWithSpecialChars() {
        let mention = MentionUtilities.createMention(for: "Node-123")
        #expect(mention == "@[Node-123]")
    }

    @Test("createMention handles empty name")
    func testCreateMentionEmpty() {
        let mention = MentionUtilities.createMention(for: "")
        #expect(mention == "@[]")
    }

    // MARK: - extractMentions Tests

    @Test("extractMentions parses single mention")
    func testExtractSingleMention() {
        let mentions = MentionUtilities.extractMentions(from: "@[Alice] hello!")
        #expect(mentions == ["Alice"])
    }

    @Test("extractMentions parses multiple mentions")
    func testExtractMultipleMentions() {
        let mentions = MentionUtilities.extractMentions(from: "@[Alice] and @[Bob] hello!")
        #expect(mentions == ["Alice", "Bob"])
    }

    @Test("extractMentions returns empty for no mentions")
    func testExtractNoMentions() {
        let mentions = MentionUtilities.extractMentions(from: "Hello world!")
        #expect(mentions.isEmpty)
    }

    @Test("extractMentions handles names with spaces")
    func testExtractMentionWithSpaces() {
        let mentions = MentionUtilities.extractMentions(from: "@[My Node] says hi")
        #expect(mentions == ["My Node"])
    }

    @Test("extractMentions handles special characters")
    func testExtractMentionWithSpecialChars() {
        let mentions = MentionUtilities.extractMentions(from: "@[Node-123] testing")
        #expect(mentions == ["Node-123"])
    }

    @Test("extractMentions handles adjacent mentions")
    func testExtractAdjacentMentions() {
        let mentions = MentionUtilities.extractMentions(from: "@[Alice]@[Bob]")
        #expect(mentions == ["Alice", "Bob"])
    }

    @Test("extractMentions ignores malformed patterns")
    func testExtractMalformedPatterns() {
        // Missing closing bracket
        let mentions1 = MentionUtilities.extractMentions(from: "@[Alice hello")
        #expect(mentions1.isEmpty)

        // Missing opening bracket
        let mentions2 = MentionUtilities.extractMentions(from: "@Alice] hello")
        #expect(mentions2.isEmpty)

        // Just @ symbol
        let mentions3 = MentionUtilities.extractMentions(from: "@ hello")
        #expect(mentions3.isEmpty)
    }

    @Test("extractMentions handles empty message")
    func testExtractFromEmptyMessage() {
        let mentions = MentionUtilities.extractMentions(from: "")
        #expect(mentions.isEmpty)
    }

    @Test("extractMentions handles Unicode names")
    func testExtractUnicodeMentions() {
        let mentions = MentionUtilities.extractMentions(from: "@[日本語] hello")
        #expect(mentions == ["日本語"])
    }
}
