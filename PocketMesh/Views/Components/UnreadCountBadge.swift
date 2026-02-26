import SwiftUI

/// Red badge with unread count, displayed as an overlay on avatars.
/// Matches iOS app icon badge style.
struct UnreadCountBadge: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(count, format: .number)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .frame(minWidth: 18, minHeight: 18)
                .background(.red, in: .capsule)
                .offset(x: 4, y: -4)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        Circle()
            .fill(.blue)
            .frame(width: 44, height: 44)
            .overlay(alignment: .topTrailing) {
                UnreadCountBadge(count: 3)
            }

        Circle()
            .fill(.blue)
            .frame(width: 44, height: 44)
            .overlay(alignment: .topTrailing) {
                UnreadCountBadge(count: 42)
            }

        Circle()
            .fill(.blue)
            .frame(width: 44, height: 44)
            .overlay(alignment: .topTrailing) {
                UnreadCountBadge(count: 0)
            }
    }
    .padding()
}
