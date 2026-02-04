import SwiftUI
import PocketMeshServices

struct RoomConversationRow: View {
    let session: RemoteNodeSessionDTO

    var body: some View {
        HStack(spacing: 12) {
            NodeAvatar(publicKey: session.publicKey, role: .roomServer, size: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(session.name)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    NotificationLevelIndicator(level: session.notificationLevel)

                    if session.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                            .accessibilityLabel(L10n.Chats.Chats.Row.favorite)
                    }

                    if let date = session.lastMessageDate {
                        ConversationTimestamp(date: date)
                    }
                }

                HStack {
                    if session.isConnected {
                        Label(L10n.Chats.Chats.Room.connected, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Text(L10n.Chats.Chats.Room.tapToReconnect)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    UnreadBadges(
                        unreadCount: session.unreadCount,
                        notificationLevel: session.notificationLevel
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
