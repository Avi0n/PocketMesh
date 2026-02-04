import SwiftUI
import PocketMeshServices

struct ChannelConversationRow: View {
    let channel: ChannelDTO
    let viewModel: ChatViewModel

    var body: some View {
        HStack(spacing: 12) {
            ChannelAvatar(channel: channel, size: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(channel.name.isEmpty ? L10n.Chats.Chats.Channel.defaultName(Int(channel.index)) : channel.name)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    NotificationLevelIndicator(level: channel.notificationLevel)

                    if channel.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.caption)
                            .accessibilityLabel(L10n.Chats.Chats.Row.favorite)
                    }

                    if let date = channel.lastMessageDate {
                        ConversationTimestamp(date: date)
                    }
                }

                HStack {
                    Text(viewModel.lastMessagePreview(for: channel) ?? L10n.Chats.Chats.Row.noMessages)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    UnreadBadges(
                        unreadCount: channel.unreadCount,
                        unreadMentionCount: channel.unreadMentionCount,
                        notificationLevel: channel.notificationLevel
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
