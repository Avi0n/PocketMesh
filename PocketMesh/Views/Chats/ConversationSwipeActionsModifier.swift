import SwiftUI

struct ConversationSwipeActionsModifier: ViewModifier {
    @Environment(AppState.self) private var appState: AppState?

    let conversation: Conversation
    let viewModel: ChatViewModel
    let onDelete: () -> Void

    private var isConnected: Bool {
        appState?.connectionState == .ready
    }

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(!isConnected)

                Button {
                    Task {
                        await viewModel.toggleMute(conversation)
                    }
                } label: {
                    Label(
                        conversation.isMuted ? "Unmute" : "Mute",
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
                        conversation.isFavorite ? "Unfavorite" : "Favorite",
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
