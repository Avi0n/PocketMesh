import SwiftUI
import PocketMeshServices
import OSLog

private let splitSidebarLogger = Logger(subsystem: "com.pocketmesh", category: "ChatsView")

struct ChatsSplitSidebarContent: View {
    @Environment(\.appState) private var appState

    let viewModel: ChatViewModel
    let filteredFavorites: [Conversation]
    let filteredOthers: [Conversation]
    let emptyStateMessage: (title: String, description: String, systemImage: String)
    let hasLoadedOnce: Bool

    @Binding var selectedRoute: ChatRoute?
    @Binding var selectedFilter: ChatFilter
    @Binding var searchText: String
    @Binding var showingNewChat: Bool
    @Binding var showingChannelOptions: Bool
    @Binding var roomToAuthenticate: RemoteNodeSessionDTO?
    @Binding var lastSelectedRoomIsConnected: Bool?
    @Binding var routeBeingDeleted: ChatRoute?

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
                selection: $selectedRoute,
                onDeleteConversation: onDeleteConversation
            ),
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
                appState.navigation.chatsSelectedRoute = nil
                lastSelectedRoomIsConnected = nil
                routeBeingDeleted = nil
                return
            }

            lastSelectedRoomIsConnected = {
                guard case .room(let session) = newValue else { return nil }
                return session.isConnected
            }()

            // Sync sidebar selection to AppState for detail pane (non-nil only;
            // nil is handled by deletion methods and disconnected room path)
            if let newValue {
                appState.navigation.chatsSelectedRoute = newValue
            }
        }
    }

    // MARK: - Helpers

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
                guard routeBeingDeleted == nil else { return }
                Task {
                    await onLoadConversations()
                }
            }
            .onChange(of: appState.conversationsVersion) { _, _ in
                guard routeBeingDeleted == nil else { return }
                Task {
                    await onLoadConversations()
                }
            }
    }
}
