import SwiftUI
import PocketMeshServices

/// Reusable chat input bar with configurable styling
struct ChatInputBar: View {
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let placeholder: String
    let accentColor: Color
    let maxCharacters: Int
    let onSend: () -> Void

    private var characterCount: Int {
        text.utf8.count
    }

    private var isOverLimit: Bool {
        characterCount > maxCharacters
    }

    private var shouldShowCharacterCount: Bool {
        // Show when within 20 characters of limit or over limit
        characterCount >= maxCharacters - 20
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            textField
            sendButtonWithCounter
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

    private var sendButtonWithCounter: some View {
        VStack(spacing: 4) {
            sendButton
            if shouldShowCharacterCount {
                characterCountLabel
            }
        }
    }

    private var characterCountLabel: some View {
        Text("\(characterCount)/\(maxCharacters)")
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(isOverLimit ? .red : .secondary)
            .accessibilityLabel("\(characterCount) of \(maxCharacters) characters")
    }

    @ViewBuilder
    private var sendButton: some View {
        if #available(iOS 26.0, *) {
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? accentColor : .secondary)
            }
            .buttonStyle(.glass)
            .disabled(!canSend)
            .accessibilityLabel(sendAccessibilityLabel)
            .accessibilityHint(sendAccessibilityHint)
        } else {
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? accentColor : .secondary)
            }
            .disabled(!canSend)
            .accessibilityLabel(sendAccessibilityLabel)
            .accessibilityHint(sendAccessibilityHint)
        }
    }

    private var sendAccessibilityLabel: String {
        if isOverLimit {
            return "Message too long"
        } else {
            return "Send message"
        }
    }

    private var sendAccessibilityHint: String {
        if isOverLimit {
            return "Remove \(characterCount - maxCharacters) characters to send"
        } else if canSend {
            return "Tap to send your message"
        } else {
            return "Type a message first"
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isOverLimit
    }
}

// MARK: - Platform-Conditional Styling

private extension View {
    @ViewBuilder
    func textFieldBackground() -> some View {
        if #available(iOS 26.0, *) {
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
            self
        } else {
            self.background(.bar)
        }
    }
}
