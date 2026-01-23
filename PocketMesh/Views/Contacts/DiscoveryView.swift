import SwiftUI
import PocketMeshServices

/// Shows contacts discovered via advertisement that haven't been added to the device
struct DiscoveryView: View {
    @Environment(\.appState) private var appState
    @State private var discoveredContacts: [ContactDTO] = []
    @State private var isLoading = false
    @State private var hasLoadedOnce = false
    @State private var addingContactID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if !hasLoadedOnce {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if discoveredContacts.isEmpty {
                emptyView
            } else {
                contactsList
            }
        }
        .navigationTitle(L10n.Contacts.Contacts.Discovery.title)
        .task {
            await loadDiscoveredContacts()
        }
        .onChange(of: appState.contactsVersion) { _, _ in
            Task {
                await loadDiscoveredContacts()
            }
        }
        .alert(L10n.Contacts.Contacts.Common.error, isPresented: .constant(errorMessage != nil)) {
            Button(L10n.Contacts.Contacts.Common.ok) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var emptyView: some View {
        ContentUnavailableView(
            L10n.Contacts.Contacts.Discovery.Empty.title,
            systemImage: "antenna.radiowaves.left.and.right",
            description: Text(L10n.Contacts.Contacts.Discovery.Empty.description)
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
            avatarView(for: contact)

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
                    Text(L10n.Contacts.Contacts.Discovery.add)
                        .frame(width: 60)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(addingContactID != nil)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func avatarView(for contact: ContactDTO) -> some View {
        switch contact.type {
        case .chat:
            ContactAvatar(contact: contact, size: 44)
        case .repeater:
            NodeAvatar(publicKey: contact.publicKey, role: .repeater, size: 44)
        case .room:
            NodeAvatar(publicKey: contact.publicKey, role: .roomServer, size: 44)
        }
    }

    private func contactTypeLabel(for contact: ContactDTO) -> String {
        switch contact.type {
        case .chat: return L10n.Contacts.Contacts.Type.chat
        case .repeater: return L10n.Contacts.Contacts.Type.repeater
        case .room: return L10n.Contacts.Contacts.Type.room
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
        hasLoadedOnce = true
        isLoading = false
    }

    private func addContact(_ contact: ContactDTO) async {
        guard let contactService = appState.services?.contactService,
              let dataStore = appState.services?.dataStore else {
            errorMessage = L10n.Contacts.Contacts.Discovery.Error.servicesUnavailable
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
    .environment(\.appState, AppState())
}
