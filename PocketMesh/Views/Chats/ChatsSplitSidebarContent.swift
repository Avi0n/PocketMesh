import SwiftUI
import PocketMeshServices
import OSLog

private let splitSidebarLogger = Logger(subsystem: "com.pocketmesh", category: "ChatsView")

struct ChatsSplitSidebarContent: View {
    @Environment(\.appState) private var appState

    let viewModel: ChatViewModel
    let filteredFavorites: [Conversation]
    let filteredOthers: [Conversation]
    let filteredConversations: [Conversation]
    let emptyStateMessage: (title: String, description: String, systemImage: String)
    let hasLoadedOnce: Bool

    @Binding var selectedRoute: ChatRoute?
    @Binding var selectedFilter: ChatFilter?
    @Binding var searchText: String
    @Binding var showingNewChat: Bool
    @Binding var showingChannelOptions: Bool
    @Binding var showOfflineRefreshAlert: Bool
    @Binding var roomToAuthenticate: RemoteNodeSessionDTO?
    @Binding var lastSelectedRoomIsConnected: Bool?
    @Binding var routeBeingDeleted: ChatRoute?

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
                    selection: $selectedRoute,
                    onDeleteConversation: onDeleteConversation
                )
            },
            onTaskStart: {
                splitSidebarLogger.debug("ChatsView: task started, services=\(appState.services != nil)")
                viewModel.configure(appState: appState)
                await onLoadConversations()
                splitSidebarLogger.debug("ChatsView: loaded, conversations=\(viewModel.conversations.count), channels=\(viewModel.channels.count), rooms=\(viewModel.roomSessions.count)")
                onAnnounceOfflineStateIfNeeded()
                onHandlePendingNavigation()
                onHandlePendingChannelNavigation()
                onHandlePendingRoomNavigation()
            }
        )
        .onChange(of: selectedRoute) { oldValue, newValue in
            // Reload conversations when navigating away (but not when clearing for deletion)
            if oldValue != nil {
                let didClearSelectionForDeletion = (newValue == nil && oldValue == routeBeingDeleted)
                if !didClearSelectionForDeletion {
                    Task {
                        await onLoadConversations()
                    }
                }
            }

            if case .room(let session) = newValue, !session.isConnected {
                roomToAuthenticate = session
                selectedRoute = nil
                appState.chatsSelectedRoute = nil
                lastSelectedRoomIsConnected = nil
                routeBeingDeleted = nil
                return
            }

            lastSelectedRoomIsConnected = {
                guard case .room(let session) = newValue else { return nil }
                return session.isConnected
            }()

            // Sync sidebar selection to AppState for detail pane (non-nil only;
            // nil cases are handled explicitly by deletion methods and disconnected room path)
            if let newValue {
                appState.chatsSelectedRoute = newValue
            }
        }
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
