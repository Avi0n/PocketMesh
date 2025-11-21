import PocketMeshKit
import SwiftData
import SwiftUI

struct ContactsListView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: AppCoordinator

    @Query(
        filter: #Predicate<Contact> { contact in
            contact.isPending == false
        },
        sort: \Contact.name,
    ) private var contacts: [Contact]

    @Query(
        filter: #Predicate<Contact> { contact in
            contact.isPending == true
        },
    ) private var pendingContacts: [Contact]

    @State private var searchText = ""
    @State private var isSendingAdvertisement = false
    @State private var showSendSuccess = false
    @State private var showingPendingContacts = false

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
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingPendingContacts = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "person.crop.circle.badge.questionmark")
                                .symbolVariant(pendingContacts.isEmpty ? .none : .fill)
                            if !pendingContacts.isEmpty {
                                Text("\(pendingContacts.count)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                            }
                        }
                        .foregroundColor(pendingContacts.isEmpty ? .secondary : .blue)
                    }
                }

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
                        Image(systemName: isSendingAdvertisement
                            ? "antenna.radiowaves.left.and.right.slash"
                            : "antenna.radiowaves.left.and.right")
                    }
                    .disabled(isSendingAdvertisement)
                }
            }
            .alert("Advertisement Sent", isPresented: $showSendSuccess) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Your advertisement has been broadcast to the mesh network.")
            }
            .overlay {
                if contacts.isEmpty {
                    ContentUnavailableView(
                        "No Contacts",
                        systemImage: "person.2",
                        description: Text("Send an advertisement to discover nearby mesh contacts"),
                    )
                }
            }
            .sheet(isPresented: $showingPendingContacts) {
                PendingContactsView()
                    .environmentObject(coordinator)
            }
        }
    }

    private var filteredContacts: [Contact] {
        if searchText.isEmpty {
            contacts
        } else {
            contacts.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
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

    private var contactIcon: String {
        switch contact.type {
        case .companion:
            "person.circle.fill"
        case .repeater:
            "antenna.radiowaves.left.and.right"
        case .room:
            "person.3.fill"
        case .sensor:
            "sensor.fill"
        case .none:
            "questionmark.circle"
        }
    }

    private var contactColor: Color {
        switch contact.type {
        case .companion:
            .blue
        case .repeater:
            .purple
        case .room:
            .green
        case .sensor:
            .orange
        case .none:
            .gray
        }
    }

    var body: some View {
        HStack {
            // Avatar
            Image(systemName: contactIcon)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(contactColor)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.8), lineWidth: 1.5),
                )

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

            if contact.latitude != nil, contact.longitude != nil {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}
