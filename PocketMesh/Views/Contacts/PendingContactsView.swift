import PocketMeshKit
import SwiftData
import SwiftUI

struct PendingContactsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var coordinator: AppCoordinator

    @Query(
        filter: #Predicate<Contact> { contact in
            contact.isPending == true
        },
        sort: [SortDescriptor(\.lastAdvertisement, order: .reverse)],
    ) private var pendingContacts: [Contact]

    var body: some View {
        NavigationStack {
            Group {
                if pendingContacts.isEmpty {
                    ContentUnavailableView(
                        "No Pending Contacts",
                        systemImage: "person.crop.circle.badge.questionmark",
                        description: Text("New contacts discovered nearby will appear here for approval."),
                    )
                } else {
                    List {
                        ForEach(pendingContacts) { contact in
                            PendingContactRow(contact: contact)
                        }
                    }
                }
            }
            .navigationTitle("Pending Contacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                if !pendingContacts.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Approve All") {
                            approveAllContacts()
                        }
                    }
                }
            }
        }
    }

    private func approveAllContacts() {
        let repository = ContactRepository(modelContext: modelContext)

        for contact in pendingContacts {
            Task {
                try? await repository.approveContact(contact)
            }
        }
    }
}

struct PendingContactRow: View {
    let contact: Contact
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var coordinator: AppCoordinator

    var body: some View {
        HStack(spacing: 12) {
            // Contact type icon
            Image(systemName: contact.type.iconName)
                .font(.title2)
                .foregroundStyle(contact.type.color)
                .frame(width: 40, height: 40)
                .background(contact.type.color.opacity(0.1))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(contact.name)
                    .font(.headline)

                HStack(spacing: 4) {
                    Text(contact.type.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let lastAdvert = contact.lastAdvertisement {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(lastAdvert, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Action buttons
            HStack(spacing: 8) {
                Button {
                    rejectContact()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)

                Button {
                    approveContact()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func approveContact() {
        let repository = ContactRepository(modelContext: modelContext)
        Task {
            try? await repository.approveContact(contact)
        }
    }

    private func rejectContact() {
        let repository = ContactRepository(modelContext: modelContext)
        Task {
            try? await repository.rejectContact(contact)
        }
    }
}

// Preview
#Preview {
    PendingContactsView()
        .environmentObject(AppCoordinator())
}
