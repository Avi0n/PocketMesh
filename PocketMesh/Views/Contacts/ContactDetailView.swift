import SwiftUI
import MapKit
import PocketMeshKit

/// Detailed view for a single contact
struct ContactDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let contact: ContactDTO

    @State private var nickname = ""
    @State private var isEditingNickname = false
    @State private var showingBlockAlert = false
    @State private var showingDeleteAlert = false
    @State private var showingShareSheet = false
    @State private var isSaving = false

    var body: some View {
        List {
            // Profile header
            profileSection

            // Quick actions
            actionsSection

            // Info section
            infoSection

            // Location section (if available)
            if contact.hasLocation {
                locationSection
            }

            // Technical details
            technicalSection

            // Danger zone
            dangerSection
        }
        .navigationTitle("Contact")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Message", systemImage: "message.fill") {
                    // Navigate to chat
                    dismiss()
                }
            }
        }
        .alert("Block Contact", isPresented: $showingBlockAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Block", role: .destructive) {
                // Handle blocking
            }
        } message: {
            Text("You won't receive messages from \(contact.displayName). You can unblock them later.")
        }
        .alert("Delete Contact", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                // Handle deletion
                dismiss()
            }
        } message: {
            Text("This will remove \(contact.displayName) from your contacts. This action cannot be undone.")
        }
        .onAppear {
            nickname = contact.nickname ?? ""
        }
    }

    // MARK: - Profile Section

    private var profileSection: some View {
        Section {
            VStack(spacing: 16) {
                ContactAvatar(contact: contact, size: 100)

                VStack(spacing: 4) {
                    Text(contact.displayName)
                        .font(.title2)
                        .bold()

                    Text(contactTypeLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // Status indicators
                    HStack(spacing: 12) {
                        if contact.isFavorite {
                            Label("Favorite", systemImage: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                        }

                        if contact.isBlocked {
                            Label("Blocked", systemImage: "hand.raised.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        if contact.hasLocation {
                            Label("Has Location", systemImage: "location.fill")
                                .font(.caption)
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        Section {
            // Send message
            NavigationLink {
                ChatView(contact: contact)
            } label: {
                Label("Send Message", systemImage: "message.fill")
            }

            // Toggle favorite
            Button {
                // Toggle favorite
            } label: {
                Label(
                    contact.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: contact.isFavorite ? "star.slash" : "star"
                )
            }

            // Share contact
            Button {
                showingShareSheet = true
            } label: {
                Label("Share Contact", systemImage: "square.and.arrow.up")
            }
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        Section {
            // Nickname
            HStack {
                Text("Nickname")

                Spacer()

                if isEditingNickname {
                    TextField("Nickname", text: $nickname)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .onSubmit {
                            saveNickname()
                        }

                    Button("Save") {
                        saveNickname()
                    }
                    .disabled(isSaving)
                } else {
                    Text(contact.nickname ?? "None")
                        .foregroundStyle(.secondary)

                    Button("Edit") {
                        isEditingNickname = true
                    }
                    .buttonStyle(.borderless)
                }
            }

            // Original name
            HStack {
                Text("Name")
                Spacer()
                Text(contact.name)
                    .foregroundStyle(.secondary)
            }

            // Last seen
            if contact.lastAdvertTimestamp > 0 {
                HStack {
                    Text("Last Seen")
                    Spacer()
                    Text(Date(timeIntervalSince1970: TimeInterval(contact.lastAdvertTimestamp)), style: .relative)
                        .foregroundStyle(.secondary)
                }
            }

            // Unread count
            if contact.unreadCount > 0 {
                HStack {
                    Text("Unread Messages")
                    Spacer()
                    Text(contact.unreadCount, format: .number)
                        .foregroundStyle(.blue)
                }
            }
        } header: {
            Text("Info")
        }
    }

    // MARK: - Location Section

    private var locationSection: some View {
        Section {
            // Mini map
            Map {
                Marker(contact.displayName, coordinate: contactCoordinate)
            }
            .frame(height: 200)
            .clipShape(.rect(cornerRadius: 12))
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            // Coordinates
            HStack {
                Text("Coordinates")
                Spacer()
                Text("\(contact.latitude, format: .number.precision(.fractionLength(4))), \(contact.longitude, format: .number.precision(.fractionLength(4)))")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            // Open in Maps
            Button {
                openInMaps()
            } label: {
                Label("Open in Maps", systemImage: "map")
            }
        } header: {
            Text("Location")
        }
    }

    private var contactCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: CLLocationDegrees(contact.latitude),
            longitude: CLLocationDegrees(contact.longitude)
        )
    }

    private func openInMaps() {
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: contactCoordinate))
        mapItem.name = contact.displayName
        mapItem.openInMaps()
    }

    // MARK: - Technical Section

    private var technicalSection: some View {
        Section {
            // Public key prefix
            HStack {
                Text("Public Key")
                Spacer()
                Text(publicKeyHex)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }

            // Routing info
            HStack {
                Text("Routing")
                Spacer()
                Text(routingInfo)
                    .foregroundStyle(.secondary)
            }

            // Path length
            if !contact.isFloodRouted && contact.outPathLength >= 0 {
                HStack {
                    Text("Hops")
                    Spacer()
                    Text(contact.outPathLength, format: .number)
                        .foregroundStyle(.secondary)
                }
            }

            // Contact type
            HStack {
                Text("Type")
                Spacer()
                Text(contactTypeLabel)
                    .foregroundStyle(.secondary)
            }

            // Reset path button
            Button {
                // Reset path
            } label: {
                Label("Reset Path", systemImage: "arrow.triangle.2.circlepath")
            }
        } header: {
            Text("Technical")
        } footer: {
            Text("Resetting the path will force the device to rediscover the best route to this contact.")
        }
    }

    // MARK: - Danger Section

    private var dangerSection: some View {
        Section {
            Button(role: contact.isBlocked ? nil : .destructive) {
                if !contact.isBlocked {
                    showingBlockAlert = true
                }
                // Else unblock directly
            } label: {
                Label(
                    contact.isBlocked ? "Unblock Contact" : "Block Contact",
                    systemImage: contact.isBlocked ? "hand.raised.slash" : "hand.raised"
                )
            }

            Button(role: .destructive) {
                showingDeleteAlert = true
            } label: {
                Label("Delete Contact", systemImage: "trash")
            }
        } header: {
            Text("Danger Zone")
        }
    }

    // MARK: - Helpers

    private var contactTypeLabel: String {
        switch contact.type {
        case .chat: return "Chat Contact"
        case .repeater: return "Repeater"
        case .room: return "Room"
        }
    }

    private var publicKeyHex: String {
        contact.publicKeyPrefix.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private var routingInfo: String {
        if contact.isFloodRouted {
            return "Flood (broadcast)"
        } else if contact.outPathLength == 0 {
            return "Direct"
        } else {
            return "Multi-hop"
        }
    }

    private func saveNickname() {
        isSaving = true
        // Save nickname through view model
        isEditingNickname = false
        isSaving = false
    }
}

#Preview {
    NavigationStack {
        ContactDetailView(contact: ContactDTO(from: Contact(
            deviceID: UUID(),
            publicKey: Data(repeating: 0x42, count: 32),
            name: "Alice",
            latitude: 37.7749,
            longitude: -122.4194,
            isFavorite: true
        )))
    }
    .environment(AppState())
}
