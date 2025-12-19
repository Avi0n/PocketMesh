import Foundation

/// Utilities for working with MeshCore mention format: @[nodeContactName]
public enum MentionUtilities {
    /// The regex pattern for matching mentions: @[name]
    public static let mentionPattern = #"@\[([^\]]+)\]"#

    /// Creates a mention string from a node contact name
    /// - Parameter name: The mesh network contact name (not nickname)
    /// - Returns: Formatted mention string "@[name]"
    public static func createMention(for name: String) -> String {
        "@[\(name)]"
    }

    /// Extracts all mentions from message text
    /// - Parameter text: The message text to parse
    /// - Returns: Array of mentioned contact names (without @[] wrapper)
    public static func extractMentions(from text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: mentionPattern) else {
            return []
        }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        return matches.compactMap { match in
            guard let captureRange = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[captureRange])
        }
    }
}
