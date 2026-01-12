import SwiftUI
import PocketMeshServices

/// Floating popup displaying mention suggestions
struct MentionSuggestionView: View {
    let contacts: [ContactDTO]
    let onSelect: (ContactDTO) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(contacts.prefix(20)) { contact in
                    Button {
                        onSelect(contact)
                    } label: {
                        MentionSuggestionRow(contact: contact)
                    }
                    .buttonStyle(.plain)

                    if contact.id != contacts.prefix(20).last?.id {
                        Divider()
                            .padding(.leading, 44)
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxHeight: 200)
        .background(.regularMaterial)
        .clipShape(.rect(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
        .accessibilityLabel("Mention suggestions")
    }
}
