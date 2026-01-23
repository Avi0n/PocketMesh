import Foundation

/// Notification level for conversations (channels, rooms, contacts)
public enum NotificationLevel: Int, Sendable, Codable, CaseIterable {
    case muted = 0
    case mentionsOnly = 1
    case all = 2

    /// SF Symbol name for this notification level
    public var iconName: String {
        switch self {
        case .muted: "bell.slash"
        case .mentionsOnly: "at"
        case .all: "bell.fill"
        }
    }

    /// Display label for UI
    public var displayName: String {
        switch self {
        case .muted: "Muted"
        case .mentionsOnly: "Mentions"
        case .all: "All"
        }
    }

    /// Accessibility description
    public var accessibilityDescription: String {
        switch self {
        case .muted: "Muted, no notifications"
        case .mentionsOnly: "Mentions only"
        case .all: "All notifications"
        }
    }

    /// Levels available for channels (which support mention tracking)
    public static let channelLevels: [NotificationLevel] = [.muted, .mentionsOnly, .all]

    /// Levels available for rooms (no mention tracking infrastructure)
    public static let roomLevels: [NotificationLevel] = [.muted, .all]
}
