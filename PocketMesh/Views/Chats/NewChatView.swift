import SwiftUI
import PocketMeshServices

struct NewChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let viewModel: ChatViewModel
    let onSelectContact: (ContactDTO) -> Void

    @State private var contacts: [ContactDTO] = []
    @State private var searchText = ""
    @State private var isLoading = false

    private var filteredContacts: [ContactDTO] {
        let eligible = contacts.filter { !$0.isBlocked && $0.type != .repeater }
        guard !searchText.isEmpty else { return eligible }
        return eligible.filter { contact in
            contact.displayName.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if contacts.isEmpty {
                    ContentUnavailableView(
                        "No Contacts",
                        systemImage: "person.2",
                        description: Text("Contacts will appear when discovered")
                    )
                } else {
                    List(filteredContacts) { contact in
                        Button {
                            onSelectContact(contact)
                        } label: {
                            HStack(spacing: 12) {
                                ContactAvatar(contact: contact, size: 40)

                                VStack(alignment: .leading) {
                                    Text(contact.displayName)
                                        .font(.headline)

                                    Text(contactTypeLabel(for: contact))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("New Chat")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search contacts")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadContacts()
            }
        }
    }

    private func loadContacts() async {
        guard let deviceID = appState.connectedDevice?.id else { return }

        isLoading = true
        contacts = (try? await appState.services?.dataStore.fetchContacts(deviceID: deviceID)) ?? []
        isLoading = false
    }

    private func contactTypeLabel(for contact: ContactDTO) -> String {
        switch contact.type {
        case .chat:
            return contact.isFloodRouted ? "Flood routing" : "Direct"
        case .repeater:
            return "Repeater"
        case .room:
            return "Room"
        }
    }
}
