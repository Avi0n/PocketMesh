import Testing
import Foundation
@testable import PocketMeshServices

@Suite("HashtagUtilities Tests")
struct HashtagUtilitiesTests {

    // MARK: - Regex Pattern Tests

    @Test("hashtag pattern matches valid hashtags")
    func testPatternMatchesValid() {
        let pattern = HashtagUtilities.hashtagPattern
        let regex = try! NSRegularExpression(pattern: pattern)

        let validCases = ["#general", "#General", "#test-channel", "#abc123", "#a"]
        for text in validCases {
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)
            #expect(matches.count == 1, "Expected match for: \(text)")
        }
    }

    @Test("hashtag pattern rejects invalid hashtags")
    func testPatternRejectsInvalid() {
        // Use anchored pattern for full-string validation (extraction pattern finds partial matches)
        let anchoredPattern = "^" + HashtagUtilities.hashtagPattern + "$"
        let regex = try! NSRegularExpression(pattern: anchoredPattern)

        let invalidCases = ["#test_underscore", "#test.dot", "#", "#-bad", "#bad!", "#white space"]
        for text in invalidCases {
            let range = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, range: range)
            #expect(matches.isEmpty, "Expected no match for: \(text)")
        }
    }

    // MARK: - extractHashtags Tests

    @Test("extractHashtags finds single hashtag")
    func testExtractSingle() {
        let result = HashtagUtilities.extractHashtags(from: "Join #general today")
        #expect(result.count == 1)
        #expect(result.first?.name == "#general")
    }

    @Test("extractHashtags accepts uppercase hashtags")
    func testExtractUppercase() {
        let result = HashtagUtilities.extractHashtags(from: "Join #General today")
        #expect(result.count == 1)
        #expect(result.first?.name == "#General")
    }

    @Test("extractHashtags finds multiple hashtags")
    func testExtractMultiple() {
        let result = HashtagUtilities.extractHashtags(from: "Try #one and #two")
        #expect(result.count == 2)
        #expect(result[0].name == "#one")
        #expect(result[1].name == "#two")
    }

    @Test("extractHashtags returns empty for no hashtags")
    func testExtractNone() {
        let result = HashtagUtilities.extractHashtags(from: "No hashtags here")
        #expect(result.isEmpty)
    }

    @Test("extractHashtags excludes hashtags inside URLs")
    func testExtractExcludesURLs() {
        let result = HashtagUtilities.extractHashtags(from: "See https://example.com#section and #general")
        #expect(result.count == 1)
        #expect(result.first?.name == "#general")
    }

    @Test("extractHashtags handles hashtag at end with punctuation")
    func testExtractWithPunctuation() {
        let result = HashtagUtilities.extractHashtags(from: "Join #general.")
        #expect(result.count == 1)
        #expect(result.first?.name == "#general")
    }

    @Test("extractHashtags handles adjacent hashtags")
    func testExtractAdjacent() {
        let result = HashtagUtilities.extractHashtags(from: "#one#two")
        #expect(result.count == 2)
    }

    // MARK: - isValidHashtagName Tests

    @Test("isValidHashtagName accepts valid names")
    func testIsValidAccepts() {
        #expect(HashtagUtilities.isValidHashtagName("general"))
        #expect(HashtagUtilities.isValidHashtagName("General"))
        #expect(HashtagUtilities.isValidHashtagName("TEST"))
        #expect(HashtagUtilities.isValidHashtagName("test-channel"))
        #expect(HashtagUtilities.isValidHashtagName("abc123"))
        #expect(HashtagUtilities.isValidHashtagName("a"))
    }

    @Test("isValidHashtagName rejects invalid names")
    func testIsValidRejects() {
        #expect(!HashtagUtilities.isValidHashtagName(""))
        #expect(!HashtagUtilities.isValidHashtagName("-bad"))
        #expect(!HashtagUtilities.isValidHashtagName("test_underscore"))
        #expect(!HashtagUtilities.isValidHashtagName("test.dot"))
        #expect(!HashtagUtilities.isValidHashtagName("bad!"))
    }

    // MARK: - normalizeHashtagName Tests

    @Test("normalizeHashtagName lowercases and strips prefix")
    func testNormalize() {
        #expect(HashtagUtilities.normalizeHashtagName("#General") == "general")
        #expect(HashtagUtilities.normalizeHashtagName("#TEST") == "test")
        #expect(HashtagUtilities.normalizeHashtagName("general") == "general")
    }

    @Test("sanitizeHashtagNameInput lowercases and strips invalid characters")
    func testSanitizeInput() {
        #expect(HashtagUtilities.sanitizeHashtagNameInput("General") == "general")
        #expect(HashtagUtilities.sanitizeHashtagNameInput("-General") == "general")
        #expect(HashtagUtilities.sanitizeHashtagNameInput("gen_eral") == "general")
    }
}
