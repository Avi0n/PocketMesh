import Foundation

/// Utilities for detecting and processing hashtag channel references in messages
public enum HashtagUtilities {

    public static let hashtagPattern = "#[A-Za-z0-9][A-Za-z0-9-]*"

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
        guard let first = name.unicodeScalars.first else { return false }
        guard isAllowedHashtagNameScalar(first, allowsHyphen: false) else { return false }
        return name.unicodeScalars.allSatisfy { scalar in
            isAllowedHashtagNameScalar(scalar, allowsHyphen: true)
        }
    }

    public static func sanitizeHashtagNameInput(_ input: String) -> String {
        var result = String()
        result.reserveCapacity(input.count)

        for scalar in input.lowercased().unicodeScalars {
            guard isAllowedHashtagNameScalar(scalar, allowsHyphen: true) else { continue }
            result.unicodeScalars.append(scalar)
        }

        while result.hasPrefix("-") {
            result.removeFirst()
        }

        return result
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

    private static func isAllowedHashtagNameScalar(_ scalar: UnicodeScalar, allowsHyphen: Bool) -> Bool {
        switch scalar.value {
        case 48...57, 65...90, 97...122:
            return true
        case 45:
            return allowsHyphen
        default:
            return false
        }
    }

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
