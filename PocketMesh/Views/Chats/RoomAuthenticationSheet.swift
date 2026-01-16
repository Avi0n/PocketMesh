import SwiftUI
import PocketMeshServices

struct RoomAuthenticationSheet: View {
    @Environment(AppState.self) private var appState

    let session: RemoteNodeSessionDTO
    let onSuccess: (RemoteNodeSessionDTO) -> Void

    @State private var contact: ContactDTO?
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let contact {
                NodeAuthenticationSheet(
                    contact: contact,
                    role: .roomServer,
                    hideNodeDetails: true,
                    onSuccess: onSuccess
                )
            } else {
                ContentUnavailableView(
                    "Room Not Found",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Could not find the room contact")
                )
            }
        }
        .task {
            contact = try? await appState.services?.dataStore.fetchContact(
                deviceID: session.deviceID,
                publicKey: session.publicKey
            )
            isLoading = false
        }
    }
}
