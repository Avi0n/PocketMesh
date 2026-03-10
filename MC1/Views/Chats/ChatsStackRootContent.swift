import SwiftUI
import PocketMeshServices

struct ChatsStackRootContent: View {
    @Environment(\.appState) private var appState

    let viewModel: ChatViewModel
    let filteredFavorites: [Conversation]
    let filteredOthers: [Conversation]
    let emptyStateMessage: (title: String, description: String, systemImage: String)
    let hasLoadedOnce: Bool

    @Binding var selectedFilter: ChatFilter
    @Binding var searchText: String
    @Binding var showingNewChat: Bool
    @Binding var showingChannelOptions: Bool
    @Binding var roomToAuthenticate: RemoteNodeSessionDTO?
    @Binding var navigationPath: NavigationPath

    let onNavigate: (ChatRoute) -> Void
    let onDeleteConversation: (Conversation) -> Void
    let onLoadConversations: () async -> Void
    let onHandlePendingNavigation: () -> Void
    let onHandlePendingChannelNavigation: () -> Void
    let onHandlePendingRoomNavigation: () -> Void
    let onAnnounceOfflineStateIfNeeded: () -> Void

    var body: some View {
        applyChatsListModifiers(
            to: ConversationListContent(
                viewModel: viewModel,
                favoriteConversations: filteredFavorites,
                otherConversations: filteredOthers,
                selectedFilter: $selectedFilter,
                hasLoadedOnce: hasLoadedOnce,
                emptyStateMessage: emptyStateMessage,
                onNavigate: { navigationPath.append($0) },
                onRequestRoomAuth: { roomToAuthenticate = $0 },
                onDeleteConversation: onDeleteConversation
            ),
            onTaskStart: {
                viewModel.configure(appState: appState)
                await onLoadConversations()
                onAnnounceOfflineStateIfNeeded()
                onHandlePendingNavigation()
                onHandlePendingChannelNavigation()
                onHandlePendingRoomNavigation()
            }
        )
    }

    private func applyChatsListModifiers<Content: View>(
        to content: Content,
        onTaskStart: @escaping () async -> Void
    ) -> some View {
        content
            .navigationTitle(L10n.Chats.Chats.title)
            .searchable(text: $searchText, prompt: L10n.Chats.Chats.Search.placeholder)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    BLEStatusIndicatorView()
                }
                ToolbarItem(placement: .automatic) {
                    Menu {
                        Button {
                            showingNewChat = true
                        } label: {
                            Label(L10n.Chats.Chats.Compose.newChat, systemImage: "person")
                        }

                        Button {
                            showingChannelOptions = true
                        } label: {
                            Label(L10n.Chats.Chats.Compose.newChannel, systemImage: "number")
                        }
                    } label: {
                        Label(L10n.Chats.Chats.Compose.newMessage, systemImage: "square.and.pencil")
                    }
                }
            }
            .task {
                await onTaskStart()
            }
            .onChange(of: appState.navigation.pendingChatContact) { _, _ in
                onHandlePendingNavigation()
            }
            .onChange(of: appState.navigation.pendingChannel) { _, _ in
                onHandlePendingChannelNavigation()
            }
            .onChange(of: appState.navigation.pendingRoomSession) { _, _ in
                onHandlePendingRoomNavigation()
            }
            .onChange(of: appState.servicesVersion) { _, _ in
                Task {
                    await onLoadConversations()
                }
            }
            .onChange(of: appState.conversationsVersion) { _, _ in
                Task {
                    await onLoadConversations()
                }
            }
    }
}
