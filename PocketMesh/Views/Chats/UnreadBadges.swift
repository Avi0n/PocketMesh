import SwiftUI

struct UnreadBadges: View {
    let unreadCount: Int
    var unreadMentionCount: Int = 0
    var isMuted: Bool = false

    private var badgeColor: Color {
        isMuted ? .secondary : .blue
    }

    var body: some View {
        HStack(spacing: 4) {
            if unreadMentionCount > 0 {
                Text("@")
                    .font(.caption.bold())
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(badgeColor, in: .circle)
            }

            if unreadCount > 0 {
                Text(unreadCount, format: .number)
                    .font(.caption2)
                    .bold()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(badgeColor, in: .capsule)
            }
        }
    }
}
