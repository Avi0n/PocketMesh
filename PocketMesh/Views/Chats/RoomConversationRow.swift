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
                        if session.isMuted {
                            Image(systemName: "bell.slash")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Muted")
                        }
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

                    if session.unreadCount > 0 {
                        Text(session.unreadCount, format: .number)
                            .font(.caption2)
                            .bold()
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(session.isMuted ? Color.secondary : Color.blue, in: .capsule)
                    }
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
