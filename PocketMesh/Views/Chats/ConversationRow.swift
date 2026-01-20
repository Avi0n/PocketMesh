import SwiftUI
import PocketMeshServices

struct ConversationRow: View {
    let contact: ContactDTO
    let viewModel: ChatViewModel

    var body: some View {
        HStack(spacing: 12) {
            ContactAvatar(contact: contact, size: 44)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    HStack(spacing: 4) {
                        Text(contact.displayName)
                            .font(.headline)
                            .lineLimit(1)

                        if contact.isFavorite {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                                .font(.caption)
                                .accessibilityLabel("Favorite")
                        }
                    }

                    Spacer()

                    HStack(spacing: 4) {
                        MutedIndicator(isMuted: contact.isMuted)
                        if let date = contact.lastMessageDate {
                            ConversationTimestamp(date: date)
                        }
                    }
                }

                HStack {
                    Text(viewModel.lastMessagePreview(for: contact) ?? "No messages yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    UnreadBadges(
                        unreadCount: contact.unreadCount,
                        unreadMentionCount: contact.unreadMentionCount,
                        isMuted: contact.isMuted
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
