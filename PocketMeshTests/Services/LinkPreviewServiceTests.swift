import Testing

@testable import PocketMesh

@Suite("LinkPreviewService Tests")
@MainActor
struct LinkPreviewServiceTests {
    let service = LinkPreviewService()

    @Test("Extracts HTTPS URL from text")
    func extractsHTTPSURL() {
        let text = "Check out https://example.com/article for more info"
        let url = service.extractFirstURL(from: text)
        #expect(url?.absoluteString == "https://example.com/article")
    }

    @Test("Extracts HTTP URL from text")
    func extractsHTTPURL() {
        let text = "Visit http://example.com"
        let url = service.extractFirstURL(from: text)
        #expect(url?.scheme == "http")
    }

    @Test("Returns nil for text without URLs")
    func returnsNilForNoURL() {
        let text = "Just some plain text without links"
        let url = service.extractFirstURL(from: text)
        #expect(url == nil)
    }

    @Test("Extracts first URL when multiple URLs present")
    func extractsFirstURLOnly() {
        let text = "First https://first.com then https://second.com"
        let url = service.extractFirstURL(from: text)
        #expect(url?.host == "first.com")
    }

    @Test("Ignores non-HTTP schemes like tel: and mailto:")
    func ignoresNonHTTPSchemes() {
        let text = "Call me at tel:+1234567890 or mailto:test@example.com"
        let url = service.extractFirstURL(from: text)
        #expect(url == nil)
    }

    @Test("Extracts URL with path and query string")
    func extractsURLWithPath() {
        let text = "Read https://example.com/blog/2024/article-title?ref=social"
        let url = service.extractFirstURL(from: text)
        #expect(url?.path == "/blog/2024/article-title")
        #expect(url?.query == "ref=social")
    }

    @Test("Extracts URL at beginning of text")
    func extractsURLAtBeginning() {
        let text = "https://example.com is a great site"
        let url = service.extractFirstURL(from: text)
        #expect(url?.absoluteString == "https://example.com")
    }

    @Test("Extracts URL at end of text")
    func extractsURLAtEnd() {
        let text = "Check this out: https://example.com"
        let url = service.extractFirstURL(from: text)
        #expect(url?.absoluteString == "https://example.com")
    }

    @Test("Returns nil for empty text")
    func returnsNilForEmptyText() {
        let text = ""
        let url = service.extractFirstURL(from: text)
        #expect(url == nil)
    }

    @Test("Handles URL with fragment")
    func handlesURLWithFragment() {
        let text = "See https://example.com/page#section"
        let url = service.extractFirstURL(from: text)
        #expect(url?.fragment == "section")
    }
}
