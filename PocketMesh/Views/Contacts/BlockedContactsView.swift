import SwiftUI
import PocketMeshServices

/// View showing only blocked contacts for management
struct BlockedContactsView: View {
    @Environment(AppState.self) private var appState

    @State private var contacts: [ContactDTO] = []
    @State private var isLoading = false

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
            } else if contacts.isEmpty {
                ContentUnavailableView(
                    "No Blocked Contacts",
                    systemImage: "hand.raised.slash",
                    description: Text("Contacts you block will appear here.")
                )
            } else {
                List(contacts) { contact in
                    NavigationLink {
                        ContactDetailView(contact: contact)
                    } label: {
                        ContactRowView(contact: contact)
                    }
                }
            }
        }
        .navigationTitle("Blocked Contacts")
        .task {
            await loadBlockedContacts()
        }
        .onChange(of: appState.contactsVersion) { _, _ in
            Task {
                await loadBlockedContacts()
            }
        }
    }

    private func loadBlockedContacts() async {
        guard let services = appState.services,
              let deviceID = appState.connectedDevice?.id else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            contacts = try await services.dataStore.fetchBlockedContacts(
                deviceID: deviceID
            )
        } catch {
            contacts = []
        }
    }
}
