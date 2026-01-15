import SwiftUI
import PocketMeshServices

/// Chat input bar wrapper (mention suggestions are rendered at the parent view level)
struct MentionInputBar: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let placeholder: String
    let maxCharacters: Int
    let contacts: [ContactDTO]
    let onSend: () -> Void

    var body: some View {
        ChatInputBar(
            text: $text,
            isFocused: $isFocused,
            placeholder: placeholder,
            maxCharacters: maxCharacters,
            onSend: onSend
        )
    }
}
