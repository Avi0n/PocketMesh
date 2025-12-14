import SwiftUI
import PocketMeshKit

/// Avatar view for remote nodes (room servers and repeaters)
struct NodeAvatar: View {
    let publicKey: Data
    let role: RemoteNodeRole
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(avatarColor)

            Image(systemName: iconName)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }

    private var iconName: String {
        switch role {
        case .roomServer:
            return "door.left.hand.open"
        case .repeater:
            return "antenna.radiowaves.left.and.right"
        }
    }

    private var avatarColor: Color {
        let hash = publicKey.prefix(4).reduce(0) { $0 ^ Int($1) }
        let colors: [Color] = role == .roomServer
            ? [.orange, .red, .pink, .purple]
            : [.blue, .cyan, .teal, .indigo]
        return colors[abs(hash) % colors.count]
    }
}

#Preview("Room Server") {
    NodeAvatar(
        publicKey: Data(repeating: 0x42, count: 32),
        role: .roomServer,
        size: 60
    )
}

#Preview("Repeater") {
    NodeAvatar(
        publicKey: Data(repeating: 0x55, count: 32),
        role: .repeater,
        size: 60
    )
}
