import SwiftUI
import PocketMeshServices

/// Floating popup displaying mention suggestions
struct MentionSuggestionView: View {
    let contacts: [ContactDTO]
    let onSelect: (ContactDTO) -> Void

    private let maxHeight: CGFloat = 200
    private let rowHeight: CGFloat = 48  // Avatar 32 + vertical padding 16
    private let maxSuggestions = 20

    private var contentHeight: CGFloat {
        let count = min(contacts.count, maxSuggestions)
        let dividerHeight: CGFloat = 1
        let totalHeight = CGFloat(count) * rowHeight + CGFloat(max(0, count - 1)) * dividerHeight
        return min(totalHeight, maxHeight)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(contacts.prefix(maxSuggestions)) { contact in
                    Button {
                        onSelect(contact)
                    } label: {
                        MentionSuggestionRow(contact: contact)
                    }
                    .buttonStyle(.plain)

                    if contact.id != contacts.prefix(maxSuggestions).last?.id {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }
        }
        .frame(height: contentHeight)
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: contacts.count)
        .accessibilityLabel(L10n.Chats.Chats.Suggestions.accessibilityLabel)
    }
}
