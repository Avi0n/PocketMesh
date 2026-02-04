import SwiftUI
import PocketMeshServices

struct ConversationListContent: View {
    enum ListMode {
        case selection(Binding<ChatRoute?>)
        case navigation(onNavigate: (ChatRoute) -> Void, onRequestRoomAuth: (RemoteNodeSessionDTO) -> Void)
    }

    private let viewModel: ChatViewModel
    private let favoriteConversations: [Conversation]
    private let otherConversations: [Conversation]
    private let mode: ListMode
    private let onDeleteConversation: (Conversation) -> Void

    init(
        viewModel: ChatViewModel,
        favoriteConversations: [Conversation],
        otherConversations: [Conversation],
        selection: Binding<ChatRoute?>,
        onDeleteConversation: @escaping (Conversation) -> Void
    ) {
        self.viewModel = viewModel
        self.favoriteConversations = favoriteConversations
        self.otherConversations = otherConversations
        self.mode = .selection(selection)
        self.onDeleteConversation = onDeleteConversation
    }

    init(
        viewModel: ChatViewModel,
        favoriteConversations: [Conversation],
        otherConversations: [Conversation],
        onNavigate: @escaping (ChatRoute) -> Void,
        onRequestRoomAuth: @escaping (RemoteNodeSessionDTO) -> Void,
        onDeleteConversation: @escaping (Conversation) -> Void
    ) {
        self.viewModel = viewModel
        self.favoriteConversations = favoriteConversations
        self.otherConversations = otherConversations
        self.mode = .navigation(onNavigate: onNavigate, onRequestRoomAuth: onRequestRoomAuth)
        self.onDeleteConversation = onDeleteConversation
    }

    @ViewBuilder
    private func conversationRow(for conversation: Conversation) -> some View {
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

    @ViewBuilder
    private func navigationRow(
        for conversation: Conversation,
        onNavigate: @escaping (ChatRoute) -> Void,
        onRequestRoomAuth: @escaping (RemoteNodeSessionDTO) -> Void
    ) -> some View {
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

    var body: some View {
        switch mode {
        case .selection(let selection):
            List(selection: selection) {
                Section {
                    ForEach(favoriteConversations) { conversation in
                        conversationRow(for: conversation)
                    }
                }
                .accessibilityLabel(L10n.Chats.Chats.Section.favorites)
                .accessibilityHidden(favoriteConversations.isEmpty)

                Section {
                    ForEach(otherConversations) { conversation in
                        conversationRow(for: conversation)
                    }
                }
                .accessibilityLabel(L10n.Chats.Chats.Section.conversations)
                .accessibilityHidden(otherConversations.isEmpty)
            }
            .listStyle(.plain)

        case .navigation(let onNavigate, let onRequestRoomAuth):
            List {
                Section {
                    ForEach(favoriteConversations) { conversation in
                        navigationRow(for: conversation, onNavigate: onNavigate, onRequestRoomAuth: onRequestRoomAuth)
                    }
                }
                .accessibilityLabel(L10n.Chats.Chats.Section.favorites)
                .accessibilityHidden(favoriteConversations.isEmpty)

                Section {
                    ForEach(otherConversations) { conversation in
                        navigationRow(for: conversation, onNavigate: onNavigate, onRequestRoomAuth: onRequestRoomAuth)
                    }
                }
                .accessibilityLabel(L10n.Chats.Chats.Section.conversations)
                .accessibilityHidden(otherConversations.isEmpty)
            }
            .listStyle(.plain)
        }
    }
}
