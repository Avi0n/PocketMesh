import Testing
import SwiftUI
@testable import PocketMesh

@Suite("MessageText Tests")
@MainActor
struct MessageTextTests {

    // MARK: - URL in Mention Tests

    @Test("URL-like text in mention should not be parsed as a link")
    func urlInMentionShouldNotBeParsedAsLink() {
        // Username contains a domain-like string: "Ferret PocketMesh WCMesh.com"
        let text = "Hey @[Ferret PocketMesh WCMesh.com], check this out!"
        let messageText = MessageText(text)

        // Extract the attributed string by accessing the formatted output
        let formatted = messageText.testableFormattedText

        // The mention "@Ferret PocketMesh WCMesh.com" should be styled as a mention (bold)
        // but "WCMesh.com" should NOT have a link attribute

        // Find the range of "WCMesh.com" in the formatted string
        let content = String(formatted.characters)
        guard let wcMeshRange = content.range(of: "WCMesh.com") else {
            Issue.record("Could not find 'WCMesh.com' in formatted text")
            return
        }

        // Convert to AttributedString index
        guard let attrRange = Range(wcMeshRange, in: formatted) else {
            Issue.record("Could not convert range to AttributedString range")
            return
        }

        // Check that WCMesh.com does NOT have a link attribute
        let linkValue = formatted[attrRange].link
        #expect(linkValue == nil, "WCMesh.com should not be parsed as a URL when it's part of a mention")

        // Verify it has mention styling (bold)
        let intent = formatted[attrRange].inlinePresentationIntent
        #expect(intent == .stronglyEmphasized, "WCMesh.com should have mention styling (bold)")
    }

    @Test("URL-like text in mention with IP address should not be parsed as link")
    func ipAddressInMentionShouldNotBeParsedAsLink() {
        let text = "Message from @[Node 192.168.1.100]"
        let messageText = MessageText(text)
        let formatted = messageText.testableFormattedText

        let content = String(formatted.characters)
        guard let ipRange = content.range(of: "192.168.1.100") else {
            Issue.record("Could not find IP address in formatted text")
            return
        }

        guard let attrRange = Range(ipRange, in: formatted) else {
            Issue.record("Could not convert range to AttributedString range")
            return
        }

        // IP should not be a link
        let linkValue = formatted[attrRange].link
        #expect(linkValue == nil, "IP address should not be parsed as URL when in mention")
    }

    @Test("Regular URL outside mention should still be parsed as link")
    func regularUrlShouldStillBeParsedAsLink() {
        let text = "Check https://example.com for details"
        let messageText = MessageText(text)
        let formatted = messageText.testableFormattedText

        let content = String(formatted.characters)
        guard let urlRange = content.range(of: "https://example.com") else {
            Issue.record("Could not find URL in formatted text")
            return
        }

        guard let attrRange = Range(urlRange, in: formatted) else {
            Issue.record("Could not convert range to AttributedString range")
            return
        }

        // URL should have link attribute
        let linkValue = formatted[attrRange].link
        #expect(linkValue != nil, "Regular URL should be parsed as a link")
        #expect(linkValue?.absoluteString == "https://example.com", "Link URL should match")
    }

    @Test("Message with both mention containing URL-like text and real URL")
    func mentionWithUrlLikeTextAndRealUrl() {
        let text = "@[Server node.example.com] says check https://docs.example.com"
        let messageText = MessageText(text)
        let formatted = messageText.testableFormattedText

        let content = String(formatted.characters)

        // node.example.com in mention should NOT be a link
        if let nodeRange = content.range(of: "node.example.com"),
           let attrRange = Range(nodeRange, in: formatted) {
            let linkValue = formatted[attrRange].link
            #expect(linkValue == nil, "node.example.com in mention should not be a link")
        } else {
            Issue.record("Could not find node.example.com in formatted text")
        }

        // docs.example.com URL should be a link
        if let docsRange = content.range(of: "https://docs.example.com"),
           let attrRange = Range(docsRange, in: formatted) {
            let linkValue = formatted[attrRange].link
            #expect(linkValue != nil, "Real URL should be parsed as a link")
        } else {
            Issue.record("Could not find https://docs.example.com in formatted text")
        }
    }
}
