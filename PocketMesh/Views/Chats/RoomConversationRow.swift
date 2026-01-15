import SwiftUI
import PocketMeshServices

struct RoomConversationRow: View {
    let session: RemoteNodeSessionDTO

    var body: some View {
        HStack(spacing: 12) {
            NodeAvatar(publicKey: session.publicKey, role: .roomServer, size: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(session.name)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    HStack(spacing: 4) {
                        MutedIndicator(isMuted: session.isMuted)
                        if let date = session.lastConnectedDate {
                            ConversationTimestamp(date: date)
                        }
                    }
                }

                HStack {
                    if session.isConnected {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Text("Tap to reconnect")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    UnreadBadges(
                        unreadCount: session.unreadCount,
                        isMuted: session.isMuted
                    )
                }
            }
            .alignmentGuide(.listRowSeparatorLeading) { d in
                d[.leading]
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
    }
}
