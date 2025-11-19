import SwiftUI
import SwiftData
import PocketMeshKit

struct ContactsListView: View {

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: AppCoordinator

    @Query(sort: \Contact.name) private var contacts: [Contact]
    @State private var searchText = ""
    @State private var isSendingAdvertisement = false
    @State private var showSendSuccess = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredContacts) { contact in
                    NavigationLink(value: contact) {
                        ContactRow(contact: contact)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deleteContact(contact)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search contacts")
            .navigationTitle("Contacts")
            .navigationDestination(for: Contact.self) { contact in
                ContactDetailView(contact: contact)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            sendAdvertisement(floodMode: false)
                        } label: {
                            Label("Nearby (Zero Hop)", systemImage: "antenna.radiowaves.left.and.right")
                        }

                        Button {
                            sendAdvertisement(floodMode: true)
                        } label: {
                            Label("Network-wide (Flood)", systemImage: "network")
                        }
                    } label: {
                        Image(systemName: isSendingAdvertisement ? "antenna.radiowaves.left.and.right.slash" : "antenna.radiowaves.left.and.right")
                    }
                    .disabled(isSendingAdvertisement)
                }
            }
            .alert("Advertisement Sent", isPresented: $showSendSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("Your advertisement has been broadcast to the mesh network.")
            }
            .overlay {
                if contacts.isEmpty {
                    ContentUnavailableView(
                        "No Contacts",
                        systemImage: "person.2",
                        description: Text("Send an advertisement to discover nearby mesh contacts")
                    )
                }
            }
        }
    }

    private var filteredContacts: [Contact] {
        if searchText.isEmpty {
            return contacts
        } else {
            return contacts.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }

    private func deleteContact(_ contact: Contact) {
        modelContext.delete(contact)
        try? modelContext.save()
    }

    private func sendAdvertisement(floodMode: Bool) {
        guard let advertisementService = coordinator.advertisementService else { return }

        isSendingAdvertisement = true

        Task {
            do {
                try await advertisementService.sendAdvertisement(floodMode: floodMode)
                await MainActor.run {
                    isSendingAdvertisement = false
                    showSendSuccess = true
                }
            } catch {
                print("Failed to send advertisement: \(error)")
                await MainActor.run {
                    isSendingAdvertisement = false
                }
            }
        }
    }
}

struct ContactRow: View {
    let contact: Contact

    var body: some View {
        HStack {
            // Avatar
            Circle()
                .fill(Color.green.gradient)
                .frame(width: 40, height: 40)
                .overlay {
                    Text(contact.name.prefix(1).uppercased())
                        .foregroundStyle(.white)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.headline)

                if let lastAdvert = contact.lastAdvertisement {
                    Text("Last seen \(lastAdvert, style: .relative)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if contact.latitude != nil && contact.longitude != nil {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}
