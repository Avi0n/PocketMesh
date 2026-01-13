import SwiftUI

/// Floating action button to scroll to latest message with unread badge
struct ScrollToBottomFAB: View {
    let isVisible: Bool
    let unreadCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "chevron.down")
                .font(.body.bold())
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .contentShape(.circle)
        .glassEffect(.regular.interactive(), in: .circle)
        .overlay(alignment: .topTrailing) {
            unreadBadge
        }
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.5)
        .animation(.snappy(duration: 0.2), value: isVisible)
        .accessibilityLabel("Scroll to latest message")
        .accessibilityValue(unreadCount > 0 ? "\(unreadCount) unread" : "")
        .accessibilityHidden(!isVisible)
    }

    @ViewBuilder
    private var unreadBadge: some View {
        if unreadCount > 0 {
            Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.blue, in: .capsule)
                .offset(x: 8, y: -8)
        }
    }
}

#Preview("Visible with unread") {
    ScrollToBottomFAB(isVisible: true, unreadCount: 5, onTap: {})
        .padding(50)
}

#Preview("Visible no unread") {
    ScrollToBottomFAB(isVisible: true, unreadCount: 0, onTap: {})
        .padding(50)
}

#Preview("Hidden") {
    ScrollToBottomFAB(isVisible: false, unreadCount: 3, onTap: {})
        .padding(50)
}
