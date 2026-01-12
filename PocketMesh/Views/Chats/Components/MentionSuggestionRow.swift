import SwiftUI
import PocketMeshServices

/// A single row in the mention suggestions popup
struct MentionSuggestionRow: View {
    let contact: ContactDTO

    var body: some View {
        HStack(spacing: 12) {
            ContactAvatar(contact: contact, size: 32)

            Text(contact.displayName)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mention \(contact.displayName)")
        .accessibilityHint("Double tap to insert")
    }
}
