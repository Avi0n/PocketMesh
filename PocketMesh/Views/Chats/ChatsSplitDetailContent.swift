import SwiftUI
import PocketMeshServices

struct ChatsSplitDetailContent: View {
    @Environment(\.appState) private var appState

    let viewModel: ChatViewModel

    var body: some View {
        switch appState.chatsSelectedRoute {
        case .direct(let contact):
            ChatView(contact: contact, parentViewModel: viewModel)
                .id(contact.id)
        case .channel(let channel):
            ChannelChatView(channel: channel, parentViewModel: viewModel)
                .id(channel.id)
        case .room(let session):
            RoomConversationView(session: session)
                .id(session.id)
        case .none:
            ContentUnavailableView(L10n.Chats.Chats.EmptyState.selectConversation, systemImage: "message")
        }
    }
}
