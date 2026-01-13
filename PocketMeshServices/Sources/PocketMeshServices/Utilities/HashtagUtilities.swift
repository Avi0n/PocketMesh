import Foundation

/// Utilities for detecting and processing hashtag channel references in messages
public enum HashtagUtilities {

    /// Regex pattern for valid hashtag channels: #[a-z0-9-]+
    /// Only matches lowercase letters, numbers, and hyphens after #
    public static let hashtagPattern = "#[a-z0-9][a-z0-9-]*"

    /// Represents a detected hashtag with its location in the source text
    public struct DetectedHashtag: Equatable, Sendable {
        public let name: String
        public let range: Range<String.Index>

        public init(name: String, range: Range<String.Index>) {
            self.name = name
            self.range = range
        }
    }

    /// Extracts all valid hashtags from text, excluding those within URLs
    /// - Parameter text: The message text to search
    /// - Returns: Array of detected hashtags with their ranges
    public static func extractHashtags(from text: String) -> [DetectedHashtag] {
        guard !text.isEmpty else { return [] }

        // First, find all URL ranges to exclude
        let urlRanges = findURLRanges(in: text)

        // Find all hashtag matches
        guard let regex = try? NSRegularExpression(pattern: hashtagPattern) else {
            return []
        }

        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: nsRange)

        return matches.compactMap { match -> DetectedHashtag? in
            guard let range = Range(match.range, in: text) else { return nil }

            // Skip hashtags that fall within URL ranges
            let matchStart = text.distance(from: text.startIndex, to: range.lowerBound)
            let matchEnd = text.distance(from: text.startIndex, to: range.upperBound)

            for urlRange in urlRanges {
                let urlStart = text.distance(from: text.startIndex, to: urlRange.lowerBound)
                let urlEnd = text.distance(from: text.startIndex, to: urlRange.upperBound)

                if matchStart >= urlStart && matchEnd <= urlEnd {
                    return nil
                }
            }

            let name = String(text[range])
            return DetectedHashtag(name: name, range: range)
        }
    }

    /// Validates that a channel name contains only valid characters
    /// - Parameter name: Channel name without # prefix
    /// - Returns: True if valid (starts with alphanumeric, then lowercase letters, numbers, hyphens only)
    public static func isValidHashtagName(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        guard let first = name.first, first.isLowercase || first.isNumber else { return false }
        return name.allSatisfy { char in
            char.isLowercase || char.isNumber || char == "-"
        }
    }

    /// Normalizes a hashtag name by lowercasing and removing # prefix
    /// - Parameter name: The hashtag name (with or without #)
    /// - Returns: Normalized lowercase name without prefix
    public static func normalizeHashtagName(_ name: String) -> String {
        var normalized = name.lowercased()
        if normalized.hasPrefix("#") {
            normalized.removeFirst()
        }
        return normalized
    }

    // MARK: - Private Helpers

    private static let urlDetector: NSDataDetector? = {
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
    }()

    private static func findURLRanges(in text: String) -> [Range<String.Index>] {
        guard let detector = urlDetector else { return [] }

        let nsRange = NSRange(text.startIndex..., in: text)
        let matches = detector.matches(in: text, options: [], range: nsRange)

        return matches.compactMap { match -> Range<String.Index>? in
            guard let url = match.url,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                return nil
            }
            return Range(match.range, in: text)
        }
    }
}
