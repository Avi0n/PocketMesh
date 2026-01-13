import SwiftUI

/// Floating action button to scroll to unread mentions
struct ScrollToMentionFAB: View {
    let isVisible: Bool
    let unreadMentionCount: Int
    let onTap: () -> Void

    var body: some View {
        Button("Scroll to mention", systemImage: "at", action: onTap)
            .labelStyle(.iconOnly)
            .font(.body.bold())
            .buttonStyle(.glass)
        .frame(width: 44, height: 44)
        .clipShape(.circle)
        .overlay(alignment: .topTrailing) {
            unreadBadge
        }
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.5)
        .animation(.snappy(duration: 0.2), value: isVisible)
        .accessibilityLabel("Scroll to your oldest unread mention")
        .accessibilityValue(unreadMentionCount > 1
            ? "\(unreadMentionCount) unread mentions remaining"
            : "1 unread mention")
        .accessibilityHint("Double-tap to navigate to the message")
        .accessibilityHidden(!isVisible)
    }

    @ViewBuilder
    private var unreadBadge: some View {
        if unreadMentionCount > 1 {
            Text(unreadMentionCount > 99 ? "99+" : "\(unreadMentionCount)")
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
