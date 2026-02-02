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
/// Format: `{emoji} @{sender}: {preview} [xxxxxxxx]`
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

        // Step 2: Find ` @` to locate sender start
        guard let atIndex = withoutHash.range(of: " @") else {
            return nil
        }

        let emoji = String(withoutHash[..<atIndex.lowerBound])

        // Validate emoji is not empty and starts with emoji character
        guard !emoji.isEmpty, emoji.first?.isEmoji == true else {
            return nil
        }

        let afterAt = withoutHash[atIndex.upperBound...]

        // Step 3: Find `: ` after @ to split sender from content (use LAST occurrence)
        guard let colonIndex = afterAt.range(of: ": ", options: .backwards) else {
            return nil
        }

        let sender = String(afterAt[..<colonIndex.lowerBound])
        let preview = String(afterAt[colonIndex.upperBound...])

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

    /// Generates content preview for reaction wire format
    /// - Parameters:
    ///   - text: Original message text
    ///   - maxWords: Maximum words to include (default 4)
    /// - Returns: Preview with "..." appended if truncated
    public static func generateContentPreview(_ text: String, maxWords: Int = 4) -> String {
        let words = text.split(separator: " ", omittingEmptySubsequences: true)

        if words.count <= maxWords {
            return text
        }

        let preview = words.prefix(maxWords).joined(separator: " ")
        return "\(preview)..."
    }
}

// MARK: - Character Extension for Emoji Detection

extension Character {
    var isEmoji: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.properties.isEmoji && (scalar.value > 0x238C || unicodeScalars.count > 1)
    }
}
