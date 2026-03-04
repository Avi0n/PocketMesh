import SwiftUI

/// Horizontal row of emoji buttons for quick reaction selection.
/// Uses `ViewThatFits` to center when content fits, scrolling when it overflows.
struct EmojiPickerRow: View {
    let emojis: [String]
    let onSelect: (String) -> Void
    let onOpenKeyboard: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            EmojiButtonRow(emojis: emojis, onSelect: onSelect, onOpenKeyboard: onOpenKeyboard)
                .padding(.horizontal)

            ScrollView(.horizontal) {
                EmojiButtonRow(emojis: emojis, onSelect: onSelect, onOpenKeyboard: onOpenKeyboard)
                    .padding(.horizontal)
            }
            .scrollIndicators(.hidden)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

private struct EmojiButtonRow: View {
    let emojis: [String]
    let onSelect: (String) -> Void
    let onOpenKeyboard: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ForEach(emojis, id: \.self) { emoji in
                Button {
                    onSelect(emoji)
                } label: {
                    Text(emoji)
                        .font(.title)
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: .circle)
                .accessibilityLabel(emojiAccessibilityName(emoji))
            }

            Button(L10n.Chats.Reactions.moreEmojis, systemImage: "plus") {
                onOpenKeyboard()
            }
            .font(.title2)
            .foregroundStyle(.secondary)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial, in: .circle)
        }
    }

    /// Gets the accessibility name for an emoji using Unicode name transformation
    private func emojiAccessibilityName(_ emoji: String) -> String {
        let cfstr = NSMutableString(string: emoji) as CFMutableString
        CFStringTransform(cfstr, nil, kCFStringTransformToUnicodeName, false)
        let name = cfstr as String
        return name
            .replacing("\\N{", with: "")
            .replacing("}", with: "")
            .lowercased()
    }
}

#Preview {
    EmojiPickerRow(
        emojis: ["👍", "👎", "❤️", "😂", "😮", "😢"],
        onSelect: { print("Selected: \($0)") },
        onOpenKeyboard: { print("Open keyboard") }
    )
    .padding()
    .background(.gray.opacity(0.3))
}
