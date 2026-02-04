import SwiftUI
import PocketMeshServices

private typealias Strings = L10n.RemoteNodes.RemoteNodes.Room

struct RoomInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.chatViewModel) private var viewModel

    let session: RemoteNodeSessionDTO

    @State private var notificationLevel: NotificationLevel
    @State private var isFavorite: Bool
    @State private var notificationTask: Task<Void, Never>?
    @State private var favoriteTask: Task<Void, Never>?

    init(session: RemoteNodeSessionDTO) {
        self.session = session
        self._notificationLevel = State(initialValue: session.notificationLevel)
        self._isFavorite = State(initialValue: session.isFavorite)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Spacer()
                        NodeAvatar(publicKey: session.publicKey, role: .roomServer, size: 80)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                ConversationQuickActionsSection(
                    notificationLevel: $notificationLevel,
                    isFavorite: $isFavorite,
                    availableLevels: NotificationLevel.roomLevels
                )
                .onChange(of: notificationLevel) { _, newValue in
                    notificationTask?.cancel()
                    notificationTask = Task {
                        await viewModel?.setNotificationLevel(.room(session), level: newValue)
                    }
                }
                .onChange(of: isFavorite) { _, newValue in
                    favoriteTask?.cancel()
                    favoriteTask = Task {
                        await viewModel?.setFavorite(.room(session), isFavorite: newValue)
                    }
                }
                .onDisappear {
                    notificationTask?.cancel()
                    favoriteTask?.cancel()
                }

                Section(Strings.details) {
                    LabeledContent(L10n.RemoteNodes.RemoteNodes.name, value: session.name)
                    LabeledContent(Strings.permission, value: session.permissionLevel.displayName)
                    if session.isConnected {
                        LabeledContent(Strings.status, value: Strings.connected)
                    }
                }

                if let lastConnected = session.lastConnectedDate {
                    Section(Strings.activity) {
                        LabeledContent(Strings.lastConnected) {
                            Text(lastConnected, format: .relative(presentation: .named))
                        }
                    }
                }

                Section(Strings.identification) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Strings.publicKey)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(session.publicKeyHex)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle(Strings.infoTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Localizable.Common.done) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
