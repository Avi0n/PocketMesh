import SwiftUI
import PocketMeshServices

struct NotificationLevelIndicator: View {
    let level: NotificationLevel

    var body: some View {
        switch level {
        case .muted:
            Image(systemName: "bell.slash")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityLabel(L10n.Chats.Chats.Row.muted)
        case .mentionsOnly:
            Image(systemName: "at")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityLabel(L10n.Chats.Chats.Row.mentionsOnly)
        case .all:
            EmptyView()
        }
    }
}

// Keep old name for compatibility during migration
typealias MutedIndicator = NotificationLevelIndicator

extension NotificationLevelIndicator {
    /// Backwards-compatible initializer
    init(isMuted: Bool) {
        self.level = isMuted ? .muted : .all
    }
}
