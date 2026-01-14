import SwiftUI
import PocketMeshServices

struct ChannelAvatar: View {
    let channel: ChannelDTO
    let size: CGFloat

    var body: some View {
        Image(systemName: channel.isPublicChannel ? "globe" : "number")
            .font(.system(size: size * 0.4, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(avatarColor, in: .circle)
    }

    private var avatarColor: Color {
        if channel.isPublicChannel {
            return .green
        }
        let colors: [Color] = [.blue, .orange, .purple, .pink, .cyan, .indigo, .mint]
        return colors[Int(channel.index - 1) % colors.count]
    }
}
