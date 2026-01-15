import SwiftUI
import PocketMeshServices

struct ConversationListContent: View {
    enum ListMode {
        case selection(Binding<ChatRoute?>)
        case navigation(onNavigate: (ChatRoute) -> Void, onRequestRoomAuth: (RemoteNodeSessionDTO) -> Void)
    }

    private let viewModel: ChatViewModel
    private let conversations: [Conversation]
    private let mode: ListMode
    private let onDeleteConversation: (Conversation) -> Void

    init(
        viewModel: ChatViewModel,
        conversations: [Conversation],
        selection: Binding<ChatRoute?>,
        onDeleteConversation: @escaping (Conversation) -> Void
    ) {
        self.viewModel = viewModel
        self.conversations = conversations
        self.mode = .selection(selection)
        self.onDeleteConversation = onDeleteConversation
    }

    init(
        viewModel: ChatViewModel,
        conversations: [Conversation],
        onNavigate: @escaping (ChatRoute) -> Void,
        onRequestRoomAuth: @escaping (RemoteNodeSessionDTO) -> Void,
        onDeleteConversation: @escaping (Conversation) -> Void
    ) {
        self.viewModel = viewModel
        self.conversations = conversations
        self.mode = .navigation(onNavigate: onNavigate, onRequestRoomAuth: onRequestRoomAuth)
        self.onDeleteConversation = onDeleteConversation
    }

    var body: some View {
        switch mode {
        case .selection(let selection):
            List(selection: selection) {
                ForEach(conversations) { conversation in
                    let route = ChatRoute(conversation: conversation)
                    switch conversation {
                    case .direct(let contact):
                        ConversationRow(contact: contact, viewModel: viewModel)
                            .tag(route)
                            .conversationSwipeActions(conversation: conversation, viewModel: viewModel) {
                                onDeleteConversation(conversation)
                            }

                    case .channel(let channel):
                        ChannelConversationRow(channel: channel, viewModel: viewModel)
                            .tag(route)
                            .conversationSwipeActions(conversation: conversation, viewModel: viewModel) {
                                onDeleteConversation(conversation)
                            }

                    case .room(let session):
                        RoomConversationRow(session: session)
                            .tag(route)
                            .conversationSwipeActions(conversation: conversation, viewModel: viewModel) {
                                onDeleteConversation(conversation)
                            }
                    }
                }
            }
            .listStyle(.plain)

        case .navigation(let onNavigate, let onRequestRoomAuth):
            List {
                ForEach(conversations) { conversation in
                    let route = ChatRoute(conversation: conversation)
                    switch conversation {
                    case .direct(let contact):
                        NavigationLink(value: route) {
                            ConversationRow(contact: contact, viewModel: viewModel)
                        }
                        .conversationSwipeActions(conversation: conversation, viewModel: viewModel) {
                            onDeleteConversation(conversation)
                        }

                    case .channel(let channel):
                        NavigationLink(value: route) {
                            ChannelConversationRow(channel: channel, viewModel: viewModel)
                        }
                        .conversationSwipeActions(conversation: conversation, viewModel: viewModel) {
                            onDeleteConversation(conversation)
                        }

                    case .room(let session):
                        Button {
                            if session.isConnected {
                                onNavigate(route)
                            } else {
                                onRequestRoomAuth(session)
                            }
                        } label: {
                            RoomConversationRow(session: session)
                        }
                        .buttonStyle(.plain)
                        .conversationSwipeActions(conversation: conversation, viewModel: viewModel) {
                            onDeleteConversation(conversation)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }
}
