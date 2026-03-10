import SwiftUI
import PocketMeshServices

/// Horizontal row of reaction badges displayed below message bubbles
struct ReactionBadgesView: View {
    let summary: String?  // Format: "👍:3,❤️:2,😂:1"
    let onTapReaction: (String) -> Void
    let onLongPress: () -> Void

    @State private var longPressTriggered = false

    private var reactions: [(emoji: String, count: Int)] {
        ReactionParser.parseSummary(summary)
    }

    private var visibleReactions: [(emoji: String, count: Int)] {
        Array(reactions.prefix(3))
    }

    private var overflowCount: Int {
        max(0, reactions.count - 3)
    }

    private func emojiAccessibilityName(_ emoji: String) -> String {
        let cfstr = NSMutableString(string: emoji) as CFMutableString
        CFStringTransform(cfstr, nil, kCFStringTransformToUnicodeName, false)
        let name = cfstr as String
        return name.replacing("\\N{", with: "").replacing("}", with: "").lowercased()
    }

    var body: some View {
        if !reactions.isEmpty {
            HStack(spacing: 0) {
                ForEach(visibleReactions, id: \.emoji) { reaction in
                    Button {
                        onTapReaction(reaction.emoji)
                    } label: {
                        ReactionBadge(emoji: reaction.emoji, count: reaction.count)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.Chats.Reactions.badge(emojiAccessibilityName(reaction.emoji), reaction.count))
                    .accessibilityHint(L10n.Chats.Reactions.badgeHint)
                }

                if overflowCount > 0 {
                    Button {
                        onLongPress()
                    } label: {
                        OverflowBadge(count: overflowCount)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.Chats.Reactions.moreBadge(overflowCount))
                    .accessibilityHint(L10n.Chats.Reactions.moreBadgeHint)
                }
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.3)
                    .onEnded { _ in
                        longPressTriggered.toggle()
                        onLongPress()
                    }
            )
            .sensoryFeedback(.impact(weight: .medium), trigger: longPressTriggered)
            .accessibilityAction(named: L10n.Chats.Reactions.viewDetails) {
                onLongPress()
            }
        }
    }
}

private struct ReactionBadge: View {
    let emoji: String
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Text(emoji)
                .font(.subheadline)
            if count > 1 {
                Text(count, format: .number)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(AppColors.Message.incomingBubble, in: .capsule)
        .overlay(Capsule().strokeBorder(Color(.systemBackground), lineWidth: 2))
    }
}

private struct OverflowBadge: View {
    let count: Int

    var body: some View {
        Text("+\(count)")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(AppColors.Message.incomingBubble, in: .capsule)
            .overlay(Capsule().strokeBorder(Color(.systemBackground), lineWidth: 2))
    }
}

#Preview {
    VStack(spacing: 20) {
        ReactionBadgesView(
            summary: "👍:3,❤️:2,😂:1",
            onTapReaction: { _ in },
            onLongPress: {}
        )

        ReactionBadgesView(
            summary: "👍:5,❤️:3,😂:2,😮:1,😢:1,🎉:1",
            onTapReaction: { _ in },
            onLongPress: {}
        )

        ReactionBadgesView(
            summary: nil,
            onTapReaction: { _ in },
            onLongPress: {}
        )
    }
    .padding()
}
