import SwiftUI
import MC1Services

struct ChatsStackLayout<RootContent: View>: View {
    @Environment(\.appState) private var appState

    let viewModel: ChatViewModel
    @Binding var navigationPath: NavigationPath
    @Binding var activeRoute: ChatRoute?

    let onLoadConversations: () async -> Void
    @ViewBuilder let rootContent: () -> RootContent

    var body: some View {
        NavigationStack(path: $navigationPath) {
            rootContent()
                .navigationDestination(for: ChatRoute.self) { route in
                    switch route {
                    case .direct(let contact):
                        ChatConversationView(conversationType: .dm(contact), parentViewModel: viewModel)
                            .id(contact.id)
                            .onAppear {
                                activeRoute = route
                                appState.navigation.tabBarVisibility = .hidden
                            }

                    case .channel(let channel):
                        ChatConversationView(conversationType: .channel(channel), parentViewModel: viewModel)
                            .id(channel.id)
                            .onAppear {
                                activeRoute = route
                                appState.navigation.tabBarVisibility = .hidden
                            }

                    case .room(let session):
                        RoomConversationView(session: session)
                            .id(session.id)
                            .onAppear {
                                activeRoute = route
                                appState.navigation.tabBarVisibility = .hidden
                            }
                    }
                }
                .onChange(of: navigationPath) { _, newPath in
                    if newPath.isEmpty {
                        activeRoute = nil
                        appState.navigation.tabBarVisibility = .visible
                        Task {
                            await onLoadConversations()
                        }
                    }
                }
                .toolbarVisibility(appState.navigation.tabBarVisibility, for: .tabBar)
        }
    }
}
