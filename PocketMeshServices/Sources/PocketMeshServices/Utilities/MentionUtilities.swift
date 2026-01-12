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

    /// Detects an active mention query from input text.
    /// Returns the search query (text after @) if user is typing a mention, nil otherwise.
    /// Only triggers when @ is at start or after whitespace, and has at least one character after.
    public static func detectActiveMention(in text: String) -> String? {
        guard !text.isEmpty else { return nil }

        // Find the last @ that could start a mention
        var searchStart = text.endIndex

        while let atIndex = text[..<searchStart].lastIndex(of: "@") {
            // Check if @ is at start or preceded by whitespace
            let isAtStart = atIndex == text.startIndex
            let isAfterWhitespace = !isAtStart && text[text.index(before: atIndex)].isWhitespace

            guard isAtStart || isAfterWhitespace else {
                // @ is mid-word (like email@), try earlier @
                searchStart = atIndex
                continue
            }

            // Get text after @
            let afterAt = text[text.index(after: atIndex)...]

            // Must have at least one character after @
            guard !afterAt.isEmpty else { return nil }

            // If first char after @ is whitespace or another @, not a mention
            guard let firstChar = afterAt.first, !firstChar.isWhitespace, firstChar != "@" else { return nil }

            // Check if this is a completed mention @[...]
            if afterAt.hasPrefix("[") {
                if let closeBracket = afterAt.firstIndex(of: "]") {
                    // Completed mention, check for more text after
                    let afterMention = afterAt[afterAt.index(after: closeBracket)...]
                    if afterMention.isEmpty {
                        return nil
                    }
                    // Continue searching for another @
                    searchStart = atIndex
                    continue
                }
            }

            // Extract query until space or end
            let query = afterAt.prefix(while: { !$0.isWhitespace })
            return String(query)
        }

        return nil
    }

    /// Filters contacts for mention suggestions.
    /// - Parameters:
    ///   - contacts: All available contacts
    ///   - query: Search query (text after @)
    /// - Returns: Chat-type contacts matching query, sorted alphabetically
    public static func filterContacts(
        _ contacts: [ContactDTO],
        query: String
    ) -> [ContactDTO] {
        contacts
            .filter { $0.type == .chat }
            .filter { query.isEmpty || $0.displayName.localizedStandardContains(query) }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}
