import Foundation
import PocketMeshServices

/// State of link preview loading for a message
enum PreviewLoadState: Sendable, Hashable {
    case idle           // Not yet requested (URL detected but fetch not started)
    case loading        // Fetch in progress
    case loaded         // Preview data available in loadedPreview
    case noPreview      // Fetch completed, no preview available
    case disabled       // User has previews disabled
}

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

    // Preview state (owned by ViewModel, not view)
    let previewState: PreviewLoadState
    let loadedPreview: LinkPreviewDataDTO?

    var id: UUID { messageID }
}
