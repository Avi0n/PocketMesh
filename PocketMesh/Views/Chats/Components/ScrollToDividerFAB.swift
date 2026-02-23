import SwiftUI

/// Floating action button to scroll to the new messages divider
struct ScrollToDividerFAB: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "chevron.up")
                .font(.body.bold())
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .contentShape(.circle)
        .liquidGlassInteractive(in: .circle)
        .accessibilityLabel(L10n.Chats.Chats.Fab.ScrollToDivider.accessibilityLabel)
        .accessibilityHint(L10n.Chats.Chats.Fab.ScrollToDivider.accessibilityHint)
    }
}

#Preview {
    ScrollToDividerFAB(onTap: {})
        .padding(50)
}
