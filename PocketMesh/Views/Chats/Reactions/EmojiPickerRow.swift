import SwiftUI

/// Horizontal row of emoji buttons for quick reaction selection.
/// Scrolls horizontally if buttons overflow at large accessibility text sizes.
struct EmojiPickerRow: View {
    let emojis: [String]
    let onSelect: (String) -> Void
    let onOpenKeyboard: () -> Void

    var body: some View {
        ScrollView(.horizontal) {
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
            .padding(.horizontal)
        }
        .scrollIndicators(.hidden)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }

    /// Gets the accessibility name for an emoji using Unicode name transformation
    private func emojiAccessibilityName(_ emoji: String) -> String {
        let cfstr = NSMutableString(string: emoji) as CFMutableString
        CFStringTransform(cfstr, nil, kCFStringTransformToUnicodeName, false)
        let name = cfstr as String
        // Remove \N{ prefix and } suffix, convert to lowercase
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
