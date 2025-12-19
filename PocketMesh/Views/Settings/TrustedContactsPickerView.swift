import SwiftUI
import PocketMeshServices

/// Picker for selecting trusted contacts for telemetry
struct TrustedContactsPickerView: View {
    @Environment(AppState.self) private var appState
    @State private var contacts: [ContactDTO] = []
    @State private var trustedManager = TrustedContactsManager()

    var body: some View {
        List {
            if contacts.isEmpty {
                ContentUnavailableView(
                    "No Contacts",
                    systemImage: "person.2.slash",
                    description: Text("Add contacts to select trusted ones")
                )
            } else {
                ForEach(contacts) { contact in
                    let isTrusted = trustedManager.isTrusted(publicKeyPrefix: Data(contact.publicKey.prefix(6)))

                    Button {
                        toggleTrusted(contact)
                    } label: {
                        HStack {
                            Text(contact.displayName)
                            Spacer()
                            if isTrusted {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle("Trusted Contacts")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadContacts()
        }
    }

    private func loadContacts() async {
        guard let deviceID = appState.connectedDevice?.id,
              let contactService = appState.services?.contactService else { return }
        do {
            contacts = try await contactService.getContacts(deviceID: deviceID)
        } catch {
            // Silently fail
        }
    }

    private func toggleTrusted(_ contact: ContactDTO) {
        let prefix = Data(contact.publicKey.prefix(6))
        if trustedManager.isTrusted(publicKeyPrefix: prefix) {
            trustedManager.removeTrusted(publicKeyPrefix: prefix)
        } else {
            trustedManager.addTrusted(publicKeyPrefix: prefix)
        }
    }
}
