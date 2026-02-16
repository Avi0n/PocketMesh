import SwiftUI
import PocketMeshServices

struct ChatsStackRootContent: View {
    @Environment(\.appState) private var appState

    let viewModel: ChatViewModel
    let filteredFavorites: [Conversation]
    let filteredOthers: [Conversation]
    let filteredConversations: [Conversation]
    let emptyStateMessage: (title: String, description: String, systemImage: String)
    let hasLoadedOnce: Bool

    @Binding var selectedFilter: ChatFilter?
    @Binding var searchText: String
    @Binding var showingNewChat: Bool
    @Binding var showingChannelOptions: Bool
    @Binding var showOfflineRefreshAlert: Bool
    @Binding var roomToAuthenticate: RemoteNodeSessionDTO?
    @Binding var navigationPath: NavigationPath

    let onNavigate: (ChatRoute) -> Void
    let onDeleteConversation: (Conversation) -> Void
    let onRefreshConversations: () async -> Void
    let onLoadConversations: () async -> Void
    let onHandlePendingNavigation: () -> Void
    let onHandlePendingChannelNavigation: () -> Void
    let onHandlePendingRoomNavigation: () -> Void
    let onAnnounceOfflineStateIfNeeded: () -> Void

    var body: some View {
        applyChatsListModifiers(
            to: conversationListState {
                ConversationListContent(
                    viewModel: viewModel,
                    favoriteConversations: filteredFavorites,
                    otherConversations: filteredOthers,
                    onNavigate: { route in
                        navigationPath.append(route)
                    },
                    onRequestRoomAuth: { session in
                        roomToAuthenticate = session
                    },
                    onDeleteConversation: onDeleteConversation
                )
            },
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

    // MARK: - Helpers

    @ViewBuilder
    private func conversationListState<Content: View>(
        @ViewBuilder listContent: () -> Content
    ) -> some View {
        if !hasLoadedOnce {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredConversations.isEmpty {
            ContentUnavailableView {
                Label(emptyStateMessage.title, systemImage: emptyStateMessage.systemImage)
            } description: {
                Text(emptyStateMessage.description)
            } actions: {
                if selectedFilter != nil {
                    Button(L10n.Chats.Chats.Filter.clear) {
                        selectedFilter = nil
                    }
                }
            }
        } else {
            listContent()
        }
    }

    private func applyChatsListModifiers<Content: View>(
        to content: Content,
        onTaskStart: @escaping () async -> Void
    ) -> some View {
        content
            .navigationTitle(L10n.Chats.Chats.title)
            .searchable(text: $searchText, prompt: L10n.Chats.Chats.Search.placeholder)
            .searchScopes($selectedFilter, activation: .onSearchPresentation) {
                Text(L10n.Chats.Chats.Filter.all).tag(nil as ChatFilter?)
                ForEach(ChatFilter.allCases) { filter in
                    Text(filter.localizedName).tag(filter as ChatFilter?)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    BLEStatusIndicatorView()
                }
                ToolbarItem(placement: .topBarTrailing) {
                    ChatsFilterMenu(selectedFilter: $selectedFilter)
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
            .refreshable {
                if appState.connectionState != .ready {
                    showOfflineRefreshAlert = true
                } else {
                    await onRefreshConversations()
                }
            }
            .alert(L10n.Chats.Chats.Alert.CannotRefresh.title, isPresented: $showOfflineRefreshAlert) {
                Button(L10n.Chats.Chats.Common.ok, role: .cancel) { }
            } message: {
                Text(L10n.Chats.Chats.Alert.CannotRefresh.message)
            }
            .task {
                await onTaskStart()
            }
            .onChange(of: appState.pendingChatContact) { _, _ in
                onHandlePendingNavigation()
            }
            .onChange(of: appState.pendingChannel) { _, _ in
                onHandlePendingChannelNavigation()
            }
            .onChange(of: appState.pendingRoomSession) { _, _ in
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
