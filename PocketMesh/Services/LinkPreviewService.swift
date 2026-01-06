import Foundation
import LinkPresentation
import os
import UniformTypeIdentifiers

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

    /// Shared URL detector instance to avoid creating NSDataDetector on every call
    private static let urlDetector: NSDataDetector? = {
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }()

    /// Extracts the first HTTP/HTTPS URL from text
    /// - Parameter text: Message text to scan
    /// - Returns: First HTTP(S) URL found, or nil
    static func extractFirstURL(from text: String) -> URL? {
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

    /// Fetches metadata for a URL using LinkPresentation framework
    /// - Parameter url: The URL to fetch metadata for
    /// - Returns: Metadata if successful, nil on failure
    func fetchMetadata(for url: URL) async -> LinkPreviewMetadata? {
        let provider = LPMetadataProvider()
        provider.timeout = 10

        do {
            let metadata = try await provider.startFetchingMetadata(for: url)

            // Extract image data
            var imageData: Data?
            if let imageProvider = metadata.imageProvider {
                imageData = await loadData(from: imageProvider)
            }

            // Extract icon data
            var iconData: Data?
            if let iconProvider = metadata.iconProvider {
                iconData = await loadData(from: iconProvider)
            }

            return LinkPreviewMetadata(
                url: url,
                title: metadata.title,
                imageData: imageData,
                iconData: iconData
            )
        } catch {
            logger.warning("Failed to fetch metadata for \(url): \(error.localizedDescription)")
            return nil
        }
    }

    /// Loads image data from an NSItemProvider
    private func loadData(from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(for: .image) { data, error in
                if let error {
                    self.logger.debug("Failed to load image data: \(error.localizedDescription)")
                }
                continuation.resume(returning: data)
            }
        }
    }
}
