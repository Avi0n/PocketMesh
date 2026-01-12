import SwiftUI
import PocketMeshServices

/// Chat input bar with mention autocomplete support
struct MentionInputBar: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let placeholder: String
    let accentColor: Color
    let maxCharacters: Int
    let contacts: [ContactDTO]
    let onSend: () -> Void

    /// Filtered contacts matching the current mention query
    private var suggestions: [ContactDTO] {
        guard let query = MentionUtilities.detectActiveMention(in: text) else {
            return []
        }
        return MentionUtilities.filterContacts(contacts, query: query)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !suggestions.isEmpty {
                MentionSuggestionView(contacts: suggestions) { contact in
                    insertMention(for: contact)
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            ChatInputBar(
                text: $text,
                isFocused: $isFocused,
                placeholder: placeholder,
                accentColor: accentColor,
                maxCharacters: maxCharacters,
                onSend: onSend
            )
        }
        .animation(.easeInOut(duration: 0.15), value: suggestions.isEmpty)
    }

    /// Inserts a mention for the selected contact, replacing the @query
    private func insertMention(for contact: ContactDTO) {
        guard let query = MentionUtilities.detectActiveMention(in: text) else { return }

        // Find the @query to replace
        let searchPattern = "@" + query
        if let range = text.range(of: searchPattern, options: .backwards) {
            let mention = MentionUtilities.createMention(for: contact.name)
            text.replaceSubrange(range, with: mention + " ")
        }
    }
}
