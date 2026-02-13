import Foundation
import ImageIO
import UIKit

/// Detects image URLs and resolves hosting service URLs to direct image links
enum ImageURLDetector {

    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "heic"
    ]

    /// Max pixel dimension for inline image display (280pt × 3x scale)
    private static let inlineMaxPixelSize: CGFloat = 900

    // MARK: - Image Decoding

    /// Decodes an image at a reduced size using ImageIO, avoiding full-resolution decode.
    /// Falls back to `UIImage(data:)` if thumbnail generation fails.
    static func downsampledImage(from data: Data) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, options as CFDictionary) else {
            return UIImage(data: data)
        }
        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: inlineMaxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Direct Image Detection

    /// Returns `true` if the URL's path extension is a known image type
    static func isDirectImageURL(_ url: URL) -> Bool {
        imageExtensions.contains(url.pathExtension.lowercased())
    }

    /// Returns `true` if the data begins with the GIF magic bytes (`GIF8`)
    static func isGIFData(_ data: Data) -> Bool {
        guard data.count >= 4 else { return false }
        return data[data.startIndex] == 0x47     // G
            && data[data.startIndex + 1] == 0x49 // I
            && data[data.startIndex + 2] == 0x46 // F
            && data[data.startIndex + 3] == 0x38 // 8
    }

    /// Decodes GIF data into an animated UIImage using CGImageSource.
    /// Returns `nil` if the data is not valid GIF data.
    static func decodeGIFImage(from data: Data) -> UIImage? {
        guard isGIFData(data),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }

        let count = CGImageSourceGetCount(source)
        guard count > 1 else {
            return downsampledImage(from: data)
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: inlineMaxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]

        var frames: [UIImage] = []
        var totalDuration: TimeInterval = 0

        for i in 0..<count {
            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, i, thumbnailOptions as CFDictionary) else { continue }
            frames.append(UIImage(cgImage: cgImage))

            let properties = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
            let gifDict = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = gifDict?[kCGImagePropertyGIFUnclampedDelayTime] as? Double
                ?? gifDict?[kCGImagePropertyGIFDelayTime] as? Double
                ?? 0.1
            totalDuration += max(delay, 0.02)
        }

        guard !frames.isEmpty else { return nil }
        return UIImage.animatedImage(with: frames, duration: totalDuration)
    }

    // MARK: - Hosting Service Resolution

    /// Returns the direct image URL for known hosting page URLs, or `nil` if not resolvable
    static func resolveImageURL(_ url: URL) -> URL? {
        guard let host = url.host()?.lowercased() else { return nil }

        if host == "giphy.com" || host == "www.giphy.com" {
            return resolveGiphyURL(url)
        }

        if host == "media.giphy.com" || host == "i.giphy.com" {
            // Already a direct Giphy media URL
            return nil
        }

        return nil
    }

    /// Returns `true` if the URL points to a direct image or a resolvable hosting page
    static func isImageURL(_ url: URL) -> Bool {
        isDirectImageURL(url) || resolveImageURL(url) != nil
    }

    /// Returns the direct image URL: the URL itself for direct images,
    /// or the resolved URL for hosting pages
    static func directImageURL(for url: URL) -> URL {
        if isDirectImageURL(url) { return url }
        return resolveImageURL(url) ?? url
    }

    // MARK: - Giphy Resolution

    /// Resolves Giphy page URLs to direct GIF URLs.
    ///
    /// Supported patterns:
    /// - `giphy.com/gifs/{slug}-{ID}` or `giphy.com/gifs/{ID}`
    /// - `giphy.com/embed/{ID}`
    private static func resolveGiphyURL(_ url: URL) -> URL? {
        let pathComponents = url.pathComponents // ["/" , "gifs", "slug-ID"] etc.

        guard pathComponents.count >= 3 else { return nil }

        let section = pathComponents[1].lowercased()
        guard section == "gifs" || section == "embed" else { return nil }

        let lastComponent = pathComponents[2]

        // Extract ID: for gifs it may be "slug-text-ID", take last segment after "-"
        let giphyID: String
        if section == "gifs" {
            giphyID = lastComponent.components(separatedBy: "-").last ?? lastComponent
        } else {
            giphyID = lastComponent
        }

        guard !giphyID.isEmpty else { return nil }

        return URL(string: "https://i.giphy.com/media/\(giphyID)/giphy.gif")
    }
}
