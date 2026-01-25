import SwiftUI

struct ConversationSwipeActionsModifier: ViewModifier {
    @Environment(\.appState) private var appState

    let conversation: Conversation
    let viewModel: ChatViewModel
    let onDelete: () -> Void

    private var isConnected: Bool {
        appState.connectionState == .ready
    }

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label(L10n.Chats.Chats.SwipeAction.delete, systemImage: "trash")
                }
                .disabled(!isConnected)

                Button {
                    Task {
                        await viewModel.toggleMute(conversation)
                    }
                } label: {
                    Label(
                        conversation.isMuted ? L10n.Chats.Chats.SwipeAction.unmute : L10n.Chats.Chats.SwipeAction.mute,
                        systemImage: conversation.isMuted ? "bell" : "bell.slash"
                    )
                }
                .tint(.indigo)
                .disabled(!isConnected)
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button {
                    Task {
                        await viewModel.toggleFavorite(conversation, disableAnimation: true)
                    }
                } label: {
                    Label(
                        conversation.isFavorite ? L10n.Chats.Chats.SwipeAction.unfavorite : L10n.Chats.Chats.SwipeAction.favorite,
                        systemImage: conversation.isFavorite ? "star.slash" : "star.fill"
                    )
                }
                .tint(.yellow)
                .disabled(!isConnected)
            }
    }
}

extension View {
    func conversationSwipeActions(
        conversation: Conversation,
        viewModel: ChatViewModel,
        onDelete: @escaping () -> Void
    ) -> some View {
        modifier(ConversationSwipeActionsModifier(
            conversation: conversation,
            viewModel: viewModel,
            onDelete: onDelete
        ))
    }
}
