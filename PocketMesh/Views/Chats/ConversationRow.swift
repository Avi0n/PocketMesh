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
                    Text(contact.displayName)
                        .font(.headline)
                        .lineLimit(1)

                    Spacer()

                    HStack(spacing: 4) {
                        if contact.isMuted {
                            Image(systemName: "bell.slash")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Muted")
                        }
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

                    HStack(spacing: 4) {
                        if contact.unreadMentionCount > 0 {
                            Text("@")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(contact.isMuted ? Color.secondary : Color.blue, in: .circle)
                        }

                        if contact.unreadCount > 0 {
                            Text(contact.unreadCount, format: .number)
                                .font(.caption2)
                                .bold()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(contact.isMuted ? Color.secondary : Color.blue, in: .capsule)
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
