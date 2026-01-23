import SwiftUI
import PocketMeshServices

struct RoomInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.chatViewModel) private var viewModel

    let session: RemoteNodeSessionDTO

    @State private var notificationLevel: NotificationLevel
    @State private var isFavorite: Bool

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
                    Task {
                        await viewModel?.setNotificationLevel(.room(session), level: newValue)
                    }
                }
                .onChange(of: isFavorite) { _, newValue in
                    Task {
                        await viewModel?.setFavorite(.room(session), isFavorite: newValue)
                    }
                }

                Section("Details") {
                    LabeledContent("Name", value: session.name)
                    LabeledContent("Permission", value: session.permissionLevel.displayName)
                    if session.isConnected {
                        LabeledContent("Status", value: "Connected")
                    }
                }

                if let lastConnected = session.lastConnectedDate {
                    Section("Activity") {
                        LabeledContent("Last Connected") {
                            Text(lastConnected, format: .relative(presentation: .named))
                        }
                    }
                }

                Section("Identification") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Public Key")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(session.publicKeyHex)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .navigationTitle("Room Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
