// PocketMesh/Views/Chats/Reactions/ReactionDetailsSheet.swift
import SwiftUI
import PocketMeshServices

/// Element X-style sheet showing who reacted with each emoji.
struct ReactionDetailsSheet: View {
    let messageID: UUID

    @Environment(\.appState) private var appState

    @State private var reactions: [ReactionDTO] = []
    @State private var selectedEmoji: String?
    @State private var isLoading = true

    private var emojiGroups: [(emoji: String, reactions: [ReactionDTO])] {
        Dictionary(grouping: reactions, by: \.emoji)
            .map { (emoji: $0.key, reactions: $0.value) }
            .sorted { $0.reactions.count > $1.reactions.count }
    }

    private var selectedReactions: [ReactionDTO] {
        emojiGroups.first { $0.emoji == selectedEmoji }?.reactions ?? []
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if reactions.isEmpty {
                    ContentUnavailableView(
                        L10n.Chats.Reactions.EmptyState.title,
                        systemImage: "face.smiling",
                        description: Text(L10n.Chats.Reactions.EmptyState.description)
                    )
                } else {
                    emojiTabsView
                    Divider()
                    senderListView
                }
            }
            .navigationTitle(L10n.Chats.Reactions.title)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadReactions()
            }
        }
    }

    private var emojiTabsView: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(emojiGroups, id: \.emoji) { group in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedEmoji = group.emoji
                        }
                    } label: {
                        EmojiTab(
                            emoji: group.emoji,
                            count: group.reactions.count,
                            isSelected: selectedEmoji == group.emoji
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .scrollIndicators(.hidden)
    }

    private var senderListView: some View {
        List(selectedReactions) { reaction in
            HStack {
                Text(reaction.senderName)
                Spacer()
                Text(reaction.receivedAt, format: .relative(presentation: .named))
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .listStyle(.plain)
    }

    private func loadReactions() async {
        guard let dataStore = appState.services?.dataStore else {
            isLoading = false
            return
        }

        do {
            reactions = try await dataStore.fetchReactions(for: messageID)
            if let first = emojiGroups.first {
                selectedEmoji = first.emoji
            }
        } catch {
            // Empty state is acceptable
        }

        isLoading = false
    }
}

private struct EmojiTab: View {
    let emoji: String
    let count: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 4) {
            Text(emoji)
            Text(count, format: .number)
                .font(.caption)
                .bold()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor : Color.clear, in: .capsule)
        .foregroundStyle(isSelected ? .white : .primary)
    }
}

#Preview {
    ReactionDetailsSheet(messageID: UUID())
        .environment(\.appState, AppState())
}
