import SwiftUI
import PocketMeshServices

struct ChannelConversationRow: View {
    private typealias Strings = L10n.Chats.Chats.Row
    let channel: ChannelDTO
    let viewModel: ChatViewModel

    var body: some View {
        HStack(spacing: 12) {
            ChannelAvatar(channel: channel, size: 44)
                .overlay(alignment: .topTrailing) {
                    UnreadCountBadge(count: channel.unreadCount)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(channel.name.isEmpty ? L10n.Chats.Chats.Channel.defaultName(Int(channel.index)) : channel.name)
                        .font(.headline)
                        .lineLimit(1)

                    if channel.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.system(size: 13.2))
                            .accessibilityLabel(Strings.favorite)
                    }

                    Spacer()

                    NotificationLevelIndicator(level: channel.notificationLevel)

                    if let date = channel.lastMessageDate {
                        ConversationTimestamp(date: date)
                    }
                }

                HStack {
                    Text(viewModel.lastMessagePreview(for: channel) ?? Strings.noMessages)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()
                }
            }
            .alignmentGuide(.listRowSeparatorLeading) { d in
                d[.leading]
            }
        }
        .padding(.vertical, 4)
    }
}
