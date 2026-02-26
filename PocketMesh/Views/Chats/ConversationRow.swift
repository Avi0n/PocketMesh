import SwiftUI
import PocketMeshServices

struct ConversationRow: View {
    let contact: ContactDTO
    let viewModel: ChatViewModel

    var body: some View {
        HStack(spacing: 12) {
            ContactAvatar(contact: contact, size: 44)
                .overlay(alignment: .topTrailing) {
                    UnreadCountBadge(count: contact.unreadCount)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(contact.displayName)
                        .font(.headline)
                        .lineLimit(1)

                    if viewModel.togglingFavoriteID == contact.id {
                        ProgressView()
                            .controlSize(.small)
                    } else if contact.isFavorite {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                            .font(.system(size: 13.2))
                            .accessibilityLabel(L10n.Chats.Chats.Row.favorite)
                    }

                    Spacer()

                    MutedIndicator(isMuted: contact.isMuted)

                    if let date = contact.lastMessageDate {
                        ConversationTimestamp(date: date)
                    }
                }

                HStack {
                    Text(viewModel.lastMessagePreview(for: contact) ?? L10n.Chats.Chats.Row.noMessages)
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
