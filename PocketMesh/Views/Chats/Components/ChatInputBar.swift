import SwiftUI
import PocketMeshServices

/// Reusable chat input bar with configurable styling
struct ChatInputBar: View {
    @Environment(\.appState) private var appState
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let placeholder: String
    let maxBytes: Int
    let onSend: () -> Void

    private var byteCount: Int {
        text.utf8.count
    }

    private var isOverLimit: Bool {
        byteCount > maxBytes
    }

    private var shouldShowCharacterCount: Bool {
        // Show when within 20 bytes of limit or over limit
        byteCount >= maxBytes - 20
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
            .accessibilityLabel(L10n.Chats.Chats.Input.accessibilityLabel)
            .accessibilityHint(L10n.Chats.Chats.Input.accessibilityHint)
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
        Text("\(byteCount)/\(maxBytes)")
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(isOverLimit ? .red : .secondary)
            .accessibilityLabel(L10n.Chats.Chats.Input.characterCount(byteCount, maxBytes))
    }

    @ViewBuilder
    private var sendButton: some View {
        if #available(iOS 26.0, *) {
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? AppColors.Message.outgoingBubble : .secondary)
            }
            .buttonStyle(.glass)
            .disabled(!canSend)
            .accessibilityLabel(sendAccessibilityLabel)
            .accessibilityHint(sendAccessibilityHint)
        } else {
            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundStyle(canSend ? AppColors.Message.outgoingBubble : .secondary)
            }
            .disabled(!canSend)
            .accessibilityLabel(sendAccessibilityLabel)
            .accessibilityHint(sendAccessibilityHint)
        }
    }

    private var sendAccessibilityLabel: String {
        if isOverLimit {
            return L10n.Chats.Chats.Input.tooLong
        } else {
            return L10n.Chats.Chats.Input.sendMessage
        }
    }

    private var sendAccessibilityHint: String {
        if isOverLimit {
            return L10n.Chats.Chats.Input.removeCharacters(byteCount - maxBytes)
        } else if appState.connectionState != .ready {
            return L10n.Chats.Chats.Input.requiresConnection
        } else if canSend {
            return L10n.Chats.Chats.Input.tapToSend
        } else {
            return L10n.Chats.Chats.Input.typeFirst
        }
    }

    private var canSend: Bool {
        appState.connectionState == .ready &&
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
