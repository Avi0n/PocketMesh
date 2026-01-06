import Foundation
import os

/// Metadata extracted from a URL for link previews
struct LinkPreviewMetadata: Sendable {
    let url: URL
    let title: String?
    let imageData: Data?
    let iconData: Data?
}

/// Service for extracting URLs from text and fetching link metadata
@MainActor @Observable
final class LinkPreviewService {
    private let logger = Logger(subsystem: "com.pocketmesh", category: "LinkPreviewService")
    private let urlDetector: NSDataDetector?

    init() {
        urlDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }

    /// Extracts the first HTTP/HTTPS URL from text
    /// - Parameter text: Message text to scan
    /// - Returns: First HTTP(S) URL found, or nil
    func extractFirstURL(from text: String) -> URL? {
        guard !text.isEmpty, let detector = urlDetector else { return nil }

        let range = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, options: [], range: range)

        for match in matches {
            guard let url = match.url,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                continue
            }
            return url
        }

        return nil
    }
}
