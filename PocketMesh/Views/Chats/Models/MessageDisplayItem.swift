import Foundation

/// Pre-computed display properties for message cells.
/// Stores message ID reference only (not full DTO) to avoid memory overhead.
struct MessageDisplayItem: Identifiable, Hashable, Sendable {
    let messageID: UUID
    let showTimestamp: Bool
    let showDirectionGap: Bool
    let detectedURL: URL?

    // Forwarded properties from message (lightweight copies)
    let isOutgoing: Bool
    let containsSelfMention: Bool
    let mentionSeen: Bool

    var id: UUID { messageID }
}
