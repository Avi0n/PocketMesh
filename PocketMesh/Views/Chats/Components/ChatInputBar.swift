import SwiftUI

/// Reusable chat input bar with configurable styling
struct ChatInputBar: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let placeholder: String
    let accentColor: Color
    let isSending: Bool
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            textField
            sendButton
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .inputBarBackground()
    }

    private var textField: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .textFieldBackground()
            .lineLimit(1...5)
            .focused($isFocused)
            .accessibilityLabel("Message input")
            .accessibilityHint("Type your message here")
    }

    @ViewBuilder
    private var sendButton: some View {
        if #available(iOS 26.0, *) {
            Button(action: onSend) {
                Image(systemName: isSending ? "hourglass" : "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? accentColor : .secondary)
            }
            .buttonStyle(.glass)
            .disabled(!canSend)
            .accessibilityLabel(isSending ? "Sending message" : "Send message")
            .accessibilityHint(canSend ? "Tap to send your message" : "Type a message first")
        } else {
            Button(action: onSend) {
                Image(systemName: isSending ? "hourglass" : "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? accentColor : .secondary)
            }
            .disabled(!canSend)
            .accessibilityLabel(isSending ? "Sending message" : "Send message")
            .accessibilityHint(canSend ? "Tap to send your message" : "Type a message first")
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }
}

// MARK: - Platform-Conditional Styling

private extension View {
    @ViewBuilder
    func textFieldBackground() -> some View {
        if #available(iOS 26.0, *) {
            // Liquid Glass with interactive touch response, rounded rect for multi-line support
            self.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        } else {
            self
                .background(Color(.systemGray6))
                .clipShape(.rect(cornerRadius: 20))
        }
    }

    @ViewBuilder
    func inputBarBackground() -> some View {
        if #available(iOS 26.0, *) {
            // No background on iOS 26 - let glass effect on text field show through
            self
        } else {
            self.background(.bar)
        }
    }
}
