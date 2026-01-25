import SwiftUI

/// Floating action button to scroll to unread mentions
struct ScrollToMentionFAB: View {
    let isVisible: Bool
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
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.5)
        .animation(.snappy(duration: 0.2), value: isVisible)
        .accessibilityLabel(L10n.Chats.Chats.Fab.ScrollToMention.accessibilityLabel)
        .accessibilityValue(String(format: NSLocalizedString("chats.unreadMentions.accessibilityValue", tableName: "Chats", comment: ""), locale: .current, unreadMentionCount))
        .accessibilityHint(L10n.Chats.Chats.Fab.ScrollToMention.accessibilityHint)
        .accessibilityHidden(!isVisible)
    }

    @ViewBuilder
    private var unreadBadge: some View {
        if unreadMentionCount > 0 {
            Text(unreadMentionCount > 99 ? L10n.Chats.Chats.Fab.Badge.overflow : "\(unreadMentionCount)")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.red, in: .capsule)
                .offset(x: 8, y: -8)
        }
    }
}

#Preview("Visible with multiple") {
    ScrollToMentionFAB(isVisible: true, unreadMentionCount: 5, onTap: {})
        .padding(50)
}

#Preview("Visible with one") {
    ScrollToMentionFAB(isVisible: true, unreadMentionCount: 1, onTap: {})
        .padding(50)
}

#Preview("Hidden") {
    ScrollToMentionFAB(isVisible: false, unreadMentionCount: 3, onTap: {})
        .padding(50)
}
