import Foundation
import PocketMeshServices

/// Formats message routing path for display in message bubbles
enum MessagePathFormatter {
    /// Formats the routing path for display
    /// - Parameter message: The message DTO containing path information
    /// - Returns: Formatted path string (e.g., "Direct", "A3,7F,42", or "A3,7F…B2,C1")
    static func format(_ message: MessageDTO) -> String {
        // Direct or unknown path
        if message.pathLength == 0 || message.pathLength == 0xFF {
            return L10n.Chats.Chats.Message.Path.direct
        }

        // Destination marker: single 0xFF byte indicates direct message
        if let pathNodes = message.pathNodes,
           pathNodes.count == 1,
           pathNodes[0] == 0xFF {
            return L10n.Chats.Chats.Message.Path.direct
        }

        let nodes = message.pathNodesHex

        // Fallback when path nodes unavailable
        if nodes.isEmpty {
            return L10n.Chats.Chats.Message.Path.unavailable
        }

        // Truncate if more than 6 nodes: show first 3 + ellipsis + last 3
        if nodes.count > 6 {
            let first = nodes.prefix(3).joined(separator: ",")
            let last = nodes.suffix(3).joined(separator: ",")
            return "\(first)…\(last)"
        }

        return nodes.joined(separator: ",")
    }
}
