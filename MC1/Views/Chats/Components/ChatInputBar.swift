import SwiftUI
import PocketMeshServices

/// Reusable chat input bar with configurable styling
struct ChatInputBar: View {
    @Environment(\.appState) private var appState
    @Binding var text: String
    @FocusState.Binding var isFocused: Bool
    let placeholder: String
    let maxBytes: Int
    let isEncrypted: Bool
    let onSend: (String) -> Void

    @State private var isCoolingDown = false

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
            ChatInputTextField(text: $text, placeholder: placeholder, isFocused: $isFocused, isEncrypted: isEncrypted)
            ChatSendButtonWithCounter(
                canSend: canSend,
                isOverLimit: isOverLimit,
                shouldShowCharacterCount: shouldShowCharacterCount,
                byteCount: byteCount,
                maxBytes: maxBytes,
                sendAccessibilityLabel: sendAccessibilityLabel,
                sendAccessibilityHint: sendAccessibilityHint,
                onSend: send
            )
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .inputBarBackground()
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
        !isCoolingDown &&
        appState.connectionState == .ready &&
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isOverLimit
    }

    private func send() {
        let captured = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !captured.isEmpty else { return }
        isCoolingDown = true
        text = ""
        onSend(captured)
        Task {
            try? await Task.sleep(for: .seconds(1))
            isCoolingDown = false
        }
    }
}

// MARK: - Extracted Views

private struct ChatInputTextField: View {
    @Binding var text: String
    let placeholder: String
    @FocusState.Binding var isFocused: Bool
    let isEncrypted: Bool

    var body: some View {
        TextField(placeholder, text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .padding(.leading, 12)
            .padding(.trailing, 28)
            .padding(.vertical, 8)
            .overlay(alignment: .trailing) {
                Image(systemName: isEncrypted ? "lock.fill" : "lock.open.fill")
                    .font(.footnote)
                    .foregroundStyle(isEncrypted ? .blue : .orange)
                    .padding(.trailing, 10)
                    .accessibilityHidden(true)
            }
            .textFieldBackground()
            .lineLimit(1...5)
            .focused($isFocused)
            .accessibilityLabel(L10n.Chats.Chats.Input.accessibilityLabel)
            .accessibilityHint(L10n.Chats.Chats.Input.accessibilityHint)
            .accessibilityValue(isEncrypted ? L10n.Chats.Chats.Input.encrypted : L10n.Chats.Chats.Input.notEncrypted)
    }
}

private struct ChatSendButtonWithCounter: View {
    let canSend: Bool
    let isOverLimit: Bool
    let shouldShowCharacterCount: Bool
    let byteCount: Int
    let maxBytes: Int
    let sendAccessibilityLabel: String
    let sendAccessibilityHint: String
    let onSend: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            ChatSendButton(
                canSend: canSend,
                sendAccessibilityLabel: sendAccessibilityLabel,
                sendAccessibilityHint: sendAccessibilityHint,
                onSend: onSend
            )
            if shouldShowCharacterCount {
                ChatCharacterCountLabel(
                    byteCount: byteCount,
                    maxBytes: maxBytes,
                    isOverLimit: isOverLimit
                )
            }
        }
    }
}

private struct ChatCharacterCountLabel: View {
    let byteCount: Int
    let maxBytes: Int
    let isOverLimit: Bool

    var body: some View {
        Text("\(byteCount)/\(maxBytes)")
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(isOverLimit ? .red : .secondary)
            .accessibilityLabel(L10n.Chats.Chats.Input.characterCount(byteCount, maxBytes))
    }
}

private struct ChatSendButton: View {
    let canSend: Bool
    let sendAccessibilityLabel: String
    let sendAccessibilityHint: String
    let onSend: () -> Void

    private var sendButtonFont: Font {
        if #available(iOS 26.0, *) { .title2 } else { .title }
    }

    var body: some View {
        Button(action: onSend) {
            Image(systemName: "arrow.up.circle.fill")
                .font(sendButtonFont)
                .foregroundStyle(canSend ? AppColors.Message.outgoingBubble : .secondary)
        }
        .sendButtonStyle()
        .disabled(!canSend)
        .accessibilityLabel(sendAccessibilityLabel)
        .accessibilityHint(sendAccessibilityHint)
    }
}

// MARK: - Platform-Conditional Styling

private extension View {
    @ViewBuilder
    func sendButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.padding(.vertical, 4)
        }
    }

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
