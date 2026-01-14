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
                        if channel.isMuted {
                            Image(systemName: "bell.slash")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Muted")
                        }
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

                    HStack(spacing: 4) {
                        if channel.unreadMentionCount > 0 {
                            Text("@")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(channel.isMuted ? Color.secondary : Color.blue, in: .circle)
                        }

                        if channel.unreadCount > 0 {
                            Text(channel.unreadCount, format: .number)
                                .font(.caption2)
                                .bold()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(channel.isMuted ? Color.secondary : Color.blue, in: .capsule)
                        }
                    }
                }
            }
            .alignmentGuide(.listRowSeparatorLeading) { d in
                d[.leading]
            }
        }
        .padding(.vertical, 4)
    }
}
