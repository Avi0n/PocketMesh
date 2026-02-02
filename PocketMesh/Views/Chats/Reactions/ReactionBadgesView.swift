import SwiftUI
import PocketMeshServices

/// Horizontal row of reaction badges displayed below message bubbles
struct ReactionBadgesView: View {
    let summary: String?  // Format: "👍:3,❤️:2,😂:1"
    let onTapReaction: (String) -> Void
    let onLongPress: () -> Void

    private var reactions: [(emoji: String, count: Int)] {
        ReactionParser.parseSummary(summary)
    }

    private var visibleReactions: [(emoji: String, count: Int)] {
        Array(reactions.prefix(5))
    }

    private var overflowCount: Int {
        max(0, reactions.count - 5)
    }

    var body: some View {
        if !reactions.isEmpty {
            HStack(spacing: 6) {
                ForEach(visibleReactions, id: \.emoji) { reaction in
                    ReactionBadge(emoji: reaction.emoji, count: reaction.count)
                        .onTapGesture {
                            onTapReaction(reaction.emoji)
                        }
                }

                if overflowCount > 0 {
                    OverflowBadge(count: overflowCount)
                        .onTapGesture {
                            onLongPress()
                        }
                }
            }
            .onLongPressGesture {
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
            Text(count, format: .number)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary, in: .capsule)
    }
}

private struct OverflowBadge: View {
    let count: Int

    var body: some View {
        Text("+\(count)")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary, in: .capsule)
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
