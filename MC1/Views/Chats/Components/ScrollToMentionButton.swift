import SwiftUI

/// Button to scroll to unread mentions
struct ScrollToMentionButton: View {
    let unreadMentionCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "at")
                .font(.body.bold())
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .contentShape(.circle)
        .liquidGlassInteractive(in: .circle)
        .overlay(alignment: .topTrailing) {
            unreadBadge
        }
        .accessibilityLabel(L10n.Chats.Chats.ScrollButton.ScrollToMention.accessibilityLabel)
        .accessibilityValue(L10n.Chats.Chats.ScrollButton.ScrollToMention.accessibilityValue(unreadMentionCount))
        .accessibilityHint(L10n.Chats.Chats.ScrollButton.ScrollToMention.accessibilityHint)
    }

    @ViewBuilder
    private var unreadBadge: some View {
        if unreadMentionCount > 0 {
            Text(unreadMentionCount > 99 ? L10n.Chats.Chats.ScrollButton.Badge.overflow : "\(unreadMentionCount)")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.red, in: .capsule)
                .offset(x: 8, y: -8)
        }
    }
}

#Preview("With multiple") {
    ScrollToMentionButton(unreadMentionCount: 5, onTap: {})
        .padding(50)
}

#Preview("With one") {
    ScrollToMentionButton(unreadMentionCount: 1, onTap: {})
        .padding(50)
}
