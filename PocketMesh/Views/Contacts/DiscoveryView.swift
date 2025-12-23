import SwiftUI
import PocketMeshServices

/// Shows contacts discovered via advertisement that haven't been added to the device
struct DiscoveryView: View {
    @Environment(AppState.self) private var appState
    @State private var discoveredContacts: [ContactDTO] = []
    @State private var isLoading = false
    @State private var addingContactID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading && discoveredContacts.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if discoveredContacts.isEmpty {
                emptyView
            } else {
                contactsList
            }
        }
        .navigationTitle("Discovery")
        .task {
            await loadDiscoveredContacts()
        }
        .onChange(of: appState.syncCoordinator?.contactsVersion) { _, _ in
            Task {
                await loadDiscoveredContacts()
            }
        }
        .alert("Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var emptyView: some View {
        ContentUnavailableView(
            "No Discovered Contacts",
            systemImage: "antenna.radiowaves.left.and.right",
            description: Text("When Auto-Add Contacts is disabled, newly discovered contacts will appear here for you to add manually.")
        )
    }

    private var contactsList: some View {
        List {
            ForEach(discoveredContacts) { contact in
                discoveredContactRow(contact)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func discoveredContactRow(_ contact: ContactDTO) -> some View {
        HStack {
            ContactAvatar(contact: contact, size: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.displayName)
                    .font(.body)
                    .fontWeight(.medium)

                Text(contactTypeLabel(for: contact))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task {
                    await addContact(contact)
                }
            } label: {
                if addingContactID == contact.id {
                    ProgressView()
                        .frame(width: 60)
                } else {
                    Text("Add")
                        .frame(width: 60)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(addingContactID != nil)
        }
        .padding(.vertical, 4)
    }

    private func contactTypeLabel(for contact: ContactDTO) -> String {
        switch contact.type {
        case .chat: return "Chat"
        case .repeater: return "Repeater"
        case .room: return "Room"
        }
    }

    private func loadDiscoveredContacts() async {
        guard let deviceID = appState.connectedDevice?.id,
              let dataStore = appState.services?.dataStore else { return }

        isLoading = true
        do {
            discoveredContacts = try await dataStore.fetchDiscoveredContacts(deviceID: deviceID)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func addContact(_ contact: ContactDTO) async {
        guard let contactService = appState.services?.contactService,
              let dataStore = appState.services?.dataStore else {
            errorMessage = "Services not available"
            return
        }

        addingContactID = contact.id

        do {
            // Send to device
            try await contactService.addOrUpdateContact(
                deviceID: contact.deviceID,
                contact: contact.toContactFrame()
            )

            // Mark as confirmed locally
            try await dataStore.confirmContact(id: contact.id)

            // Remove from local list
            discoveredContacts.removeAll { $0.id == contact.id }
        } catch {
            errorMessage = error.localizedDescription
        }

        addingContactID = nil
    }
}

#Preview {
    NavigationStack {
        DiscoveryView()
    }
    .environment(AppState())
}
