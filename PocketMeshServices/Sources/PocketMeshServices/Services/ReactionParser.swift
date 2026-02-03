import Foundation
import CryptoKit

/// Parsed reaction data extracted from wire format
public struct ParsedReaction: Sendable, Equatable {
    public let emoji: String
    public let targetSender: String
    public let contentPreview: String
    public let messageHash: String  // 8 hex chars

    public init(
        emoji: String,
        targetSender: String,
        contentPreview: String,
        messageHash: String
    ) {
        self.emoji = emoji
        self.targetSender = targetSender
        self.contentPreview = contentPreview
        self.messageHash = messageHash
    }
}

/// Parses reaction wire format using end-to-start strategy.
/// Format: `{emoji} @[{sender}] {preview} [xxxxxxxx]`
public enum ReactionParser {

    /// Parses reaction text, returns nil if format doesn't match
    public static func parse(_ text: String) -> ParsedReaction? {
        // Step 1: Match hash suffix ` [xxxxxxxx]` at end (8 hex chars)
        let hashPattern = #/ \[([0-9a-f]{8})\]$/#
        guard let hashMatch = text.firstMatch(of: hashPattern) else {
            return nil
        }

        let messageHash = String(hashMatch.1)

        // Remove hash suffix
        let withoutHash = String(text[..<hashMatch.range.lowerBound])

        // Step 2: Find ` @[` to locate sender start
        guard let atBracketIndex = withoutHash.range(of: " @[") else {
            return nil
        }

        let emoji = String(withoutHash[..<atBracketIndex.lowerBound])

        // Validate emoji is not empty and starts with emoji character
        guard !emoji.isEmpty, emoji.first?.isEmoji == true else {
            return nil
        }

        let afterAtBracket = withoutHash[atBracketIndex.upperBound...]

        // Step 3: Find `] ` to extract sender and split from content
        guard let closeBracketIndex = afterAtBracket.range(of: "] ") else {
            return nil
        }

        let sender = String(afterAtBracket[..<closeBracketIndex.lowerBound])
        let preview = String(afterAtBracket[closeBracketIndex.upperBound...])

        guard !sender.isEmpty, !preview.isEmpty else {
            return nil
        }

        return ParsedReaction(
            emoji: emoji,
            targetSender: sender,
            contentPreview: preview,
            messageHash: messageHash
        )
    }

    /// Generates message hash for reaction wire format
    public static func generateMessageHash(text: String, timestamp: UInt32) -> String {
        var data = Data(text.utf8)
        withUnsafeBytes(of: timestamp.littleEndian) { data.append(contentsOf: $0) }
        let hash = SHA256.hash(data: data)
        return hash.prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    /// Generates content preview that fits within byte limit
    /// Uses character-based truncation for universal language support (including CJK)
    /// - Parameters:
    ///   - text: Original message text
    ///   - maxBytes: Maximum bytes available for preview
    /// - Returns: Preview truncated to fit, with "..." if needed
    public static func generateContentPreview(_ text: String, maxBytes: Int) -> String {
        let ellipsis = "..."
        let ellipsisBytes = ellipsis.utf8.count

        // If entire text fits, return it
        if text.utf8.count <= maxBytes {
            return text
        }

        // Need at least space for ellipsis
        guard maxBytes > ellipsisBytes else {
            return String(ellipsis.prefix(maxBytes))
        }

        // Truncate by character until it fits (works for all languages)
        var truncated = text
        while !truncated.isEmpty && (truncated.utf8.count + ellipsisBytes) > maxBytes {
            truncated = String(truncated.dropLast())
        }

        return truncated.isEmpty ? ellipsis : truncated + ellipsis
    }

    /// Builds summary string from emoji counts, sorted by count descending
    public static func buildSummary(from reactions: [(emoji: String, count: Int)]) -> String {
        reactions
            .sorted { $0.count > $1.count }
            .map { "\($0.emoji):\($0.count)" }
            .joined(separator: ",")
    }

    /// Parses summary string into emoji/count pairs
    public static func parseSummary(_ summary: String?) -> [(emoji: String, count: Int)] {
        guard let summary, !summary.isEmpty else { return [] }

        return summary.split(separator: ",").compactMap { part in
            let components = part.split(separator: ":")
            guard components.count == 2,
                  let count = Int(components[1]) else { return nil }
            return (String(components[0]), count)
        }
    }
}

// MARK: - Character Extension for Emoji Detection

extension Character {
    var isEmoji: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.properties.isEmoji && (scalar.value > 0x238C || unicodeScalars.count > 1)
    }
}
