import SwiftUI

struct ConversationSwipeActionsModifier: ViewModifier {
    let conversation: Conversation
    let viewModel: ChatViewModel
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }

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
