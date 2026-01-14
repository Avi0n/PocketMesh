import SwiftUI
import PocketMeshServices

struct ConversationListContent: View {
    private let viewModel: ChatViewModel
    private let conversations: [Conversation]
    private let selection: Binding<ChatRoute?>?
    private let onNavigate: ((ChatRoute) -> Void)?
    private let onRequestRoomAuth: ((RemoteNodeSessionDTO) -> Void)?
    private let onDeleteConversation: (Conversation) -> Void

    init(
        viewModel: ChatViewModel,
        conversations: [Conversation],
        selection: Binding<ChatRoute?>,
        onDeleteConversation: @escaping (Conversation) -> Void
    ) {
        self.viewModel = viewModel
        self.conversations = conversations
        self.selection = selection
        self.onNavigate = nil
        self.onRequestRoomAuth = nil
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
        self.selection = nil
        self.onNavigate = onNavigate
        self.onRequestRoomAuth = onRequestRoomAuth
        self.onDeleteConversation = onDeleteConversation
    }

    var body: some View {
        if let selection {
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
        } else {
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
                                onNavigate?(route)
                            } else {
                                onRequestRoomAuth?(session)
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
