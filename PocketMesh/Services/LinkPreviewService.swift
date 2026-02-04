import Foundation
import LinkPresentation
import os
import PocketMeshServices
import UIKit
import UniformTypeIdentifiers

/// Metadata extracted from a URL for link previews
struct LinkPreviewMetadata: Sendable {
    let url: URL
    let title: String?
    let imageData: Data?
    let iconData: Data?
}

/// Service for extracting URLs from text and fetching link metadata
final class LinkPreviewService: Sendable {
    private let logger = Logger(subsystem: "com.pocketmesh", category: "LinkPreviewService")

    /// Shared URL detector instance to avoid creating NSDataDetector on every call
    private static let urlDetector: NSDataDetector? = {
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }()

    /// Extracts the first HTTP/HTTPS URL from text, excluding URLs within mentions.
    /// - Parameter text: Message text to scan
    /// - Returns: First HTTP(S) URL found outside mentions, or nil
    static func extractFirstURL(from text: String) -> URL? {
        guard !text.isEmpty, let detector = urlDetector else { return nil }

        // Find mention ranges to exclude (format: @[name])
        let mentionRanges = extractMentionRanges(from: text)

        let range = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, options: [], range: range)

        for match in matches {
            guard let url = match.url,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                continue
            }

            // Skip URLs that overlap with mention ranges
            let urlRange = match.range
            let overlapsWithMention = mentionRanges.contains { mentionRange in
                NSIntersectionRange(urlRange, mentionRange).length > 0
            }
            if overlapsWithMention {
                continue
            }

            return url
        }

        return nil
    }

    /// Extracts ranges of all mentions in the text (format: @[name])
    private static func extractMentionRanges(from text: String) -> [NSRange] {
        guard let regex = try? NSRegularExpression(pattern: MentionUtilities.mentionPattern) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).map(\.range)
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

    /// Maximum image size in bytes (500KB)
    private static let maxImageSize = 500 * 1024

    /// Loads image data from an NSItemProvider, compressing if necessary
    private func loadData(from provider: NSItemProvider) async -> Data? {
        let rawData = await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(for: .image) { data, error in
                if let error {
                    self.logger.debug("Failed to load image data: \(error.localizedDescription)")
                }
                continuation.resume(returning: data)
            }
        }

        guard let data = rawData else { return nil }

        // If within size limit, return as-is
        if data.count <= Self.maxImageSize {
            return data
        }

        // Compress the image
        return compressImage(data: data, maxSize: Self.maxImageSize)
    }

    /// Compresses image data to fit within a maximum size
    private func compressImage(data: Data, maxSize: Int) -> Data? {
        guard let image = UIImage(data: data) else { return data }

        // Start with high quality and reduce until within size
        var quality: CGFloat = 0.8
        var compressed = image.jpegData(compressionQuality: quality)

        while let compressedData = compressed, compressedData.count > maxSize, quality > 0.1 {
            quality -= 0.1
            compressed = image.jpegData(compressionQuality: quality)
        }

        // If still too large, scale down the image
        if let compressedData = compressed, compressedData.count > maxSize {
            let scale = sqrt(Double(maxSize) / Double(compressedData.count))
            let newSize = CGSize(
                width: image.size.width * scale,
                height: image.size.height * scale
            )

            let renderer = UIGraphicsImageRenderer(size: newSize)
            let resized = renderer.image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
            compressed = resized.jpegData(compressionQuality: 0.7)
        }

        logger.debug("Compressed image from \(data.count) to \(compressed?.count ?? 0) bytes")
        return compressed
    }

    /// Fetches link preview for a message and persists to SwiftData
    /// - Parameters:
    ///   - message: The message to fetch preview for
    ///   - dataStore: Persistence store for saving preview data
    func fetchAndPersist(for message: MessageDTO, using dataStore: PersistenceStore) async {
        // Skip if already fetched
        guard !message.linkPreviewFetched else { return }

        // Extract URL from message text
        guard let url = Self.extractFirstURL(from: message.text) else {
            // No URL found, mark as fetched
            do {
                try await dataStore.updateMessageLinkPreview(
                    id: message.id,
                    url: nil,
                    title: nil,
                    imageData: nil,
                    iconData: nil,
                    fetched: true
                )
            } catch {
                logger.error("Failed to mark message \(message.id) as fetched: \(error.localizedDescription)")
            }
            return
        }

        // Fetch metadata
        var previewURL: String? = url.absoluteString
        var previewTitle: String?
        var previewImageData: Data?
        var previewIconData: Data?

        if let metadata = await fetchMetadata(for: url) {
            previewURL = metadata.url.absoluteString
            previewTitle = metadata.title
            previewImageData = metadata.imageData
            previewIconData = metadata.iconData
        }

        // Persist to database
        do {
            try await dataStore.updateMessageLinkPreview(
                id: message.id,
                url: previewURL,
                title: previewTitle,
                imageData: previewImageData,
                iconData: previewIconData,
                fetched: true
            )
        } catch {
            logger.error("Failed to persist link preview for message \(message.id): \(error.localizedDescription)")
        }
    }
}
