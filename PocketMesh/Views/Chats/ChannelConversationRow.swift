import SwiftUI
import PocketMeshServices

struct ChannelConversationRow: View {
    let channel: ChannelDTO
    let viewModel: ChatViewModel

    var body: some View {
        HStack(spacing: 12) {
            ChannelAvatar(channel: channel, size: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(channel.name.isEmpty ? "Channel \(channel.index)" : channel.name)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    HStack(spacing: 4) {
                        MutedIndicator(isMuted: channel.isMuted)
                        if let date = channel.lastMessageDate {
                            ConversationTimestamp(date: date)
                        }
                    }
                }

                HStack {
                    Text(viewModel.lastMessagePreview(for: channel) ?? "No messages yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    UnreadBadges(
                        unreadCount: channel.unreadCount,
                        unreadMentionCount: channel.unreadMentionCount,
                        isMuted: channel.isMuted
                    )
                }
            }
            .alignmentGuide(.listRowSeparatorLeading) { d in
                d[.leading]
            }
        }
        .padding(.vertical, 4)
    }
}
