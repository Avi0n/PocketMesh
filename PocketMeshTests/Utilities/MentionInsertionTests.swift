import Testing
import Foundation
@testable import PocketMeshServices

@Suite("Mention Insertion Tests")
struct MentionInsertionTests {

    @Test("insertMention replaces @query with mention format")
    func testInsertMention() {
        var text = "hey @ali"
        let query = MentionUtilities.detectActiveMention(in: text)!
        let searchPattern = "@" + query

        if let range = text.range(of: searchPattern, options: .backwards) {
            let mention = MentionUtilities.createMention(for: "Alice")
            text.replaceSubrange(range, with: mention + " ")
        }

        #expect(text == "hey @[Alice] ")
    }

    @Test("insertMention handles query at start of text")
    func testInsertMentionAtStart() {
        var text = "@bob"
        let query = MentionUtilities.detectActiveMention(in: text)!
        let searchPattern = "@" + query

        if let range = text.range(of: searchPattern, options: .backwards) {
            let mention = MentionUtilities.createMention(for: "Bob")
            text.replaceSubrange(range, with: mention + " ")
        }

        #expect(text == "@[Bob] ")
    }

    @Test("insertMention preserves preceding text")
    func testInsertMentionPreservesText() {
        var text = "Hello @[Alice] and @jo"
        let query = MentionUtilities.detectActiveMention(in: text)!
        let searchPattern = "@" + query

        if let range = text.range(of: searchPattern, options: .backwards) {
            let mention = MentionUtilities.createMention(for: "John")
            text.replaceSubrange(range, with: mention + " ")
        }

        #expect(text == "Hello @[Alice] and @[John] ")
    }

    @Test("insertMention uses contact name not nickname")
    func testInsertMentionUsesNodeName() {
        // Simulates: user searches "Bob" (nickname), selects contact with name "Bob's Solar Node"
        var text = "@bob"
        let contactNodeName = "Bob's Solar Node"

        let query = MentionUtilities.detectActiveMention(in: text)!
        let searchPattern = "@" + query

        if let range = text.range(of: searchPattern, options: .backwards) {
            let mention = MentionUtilities.createMention(for: contactNodeName)
            text.replaceSubrange(range, with: mention + " ")
        }

        #expect(text == "@[Bob's Solar Node] ")
    }
}
