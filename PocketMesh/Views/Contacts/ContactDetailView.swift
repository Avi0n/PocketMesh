import SwiftUI
import MapKit
import PocketMeshKit

/// Detailed view for a single contact
struct ContactDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let contact: ContactDTO
    let showFromDirectChat: Bool

    @State private var currentContact: ContactDTO
    @State private var nickname = ""
    @State private var isEditingNickname = false
    @State private var showingBlockAlert = false
    @State private var showingDeleteAlert = false
    @State private var showingShareSheet = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(contact: ContactDTO, showFromDirectChat: Bool = false) {
        self.contact = contact
        self.showFromDirectChat = showFromDirectChat
        self._currentContact = State(initialValue: contact)
    }

    var body: some View {
        List {
            // Profile header
            profileSection

            // Quick actions
            actionsSection

            // Info section
            infoSection

            // Location section (if available)
            if currentContact.hasLocation {
                locationSection
            }

            // Technical details
            technicalSection

            // Danger zone
            dangerSection
        }
        .navigationTitle("Contact")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Block Contact", isPresented: $showingBlockAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Block", role: .destructive) {
                Task {
                    await toggleBlocked()
                }
            }
        } message: {
            Text("You won't receive messages from \(currentContact.displayName). You can unblock them later.")
        }
        .alert("Delete Contact", isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task {
                    await deleteContact()
                }
            }
        } message: {
            Text("This will remove \(currentContact.displayName) from your contacts. This action cannot be undone.")
        }
        .onAppear {
            nickname = currentContact.nickname ?? ""
        }
    }

    // MARK: - Actions

    private func toggleFavorite() async {
        do {
            try await appState.contactService.updateContactPreferences(
                contactID: currentContact.id,
                isFavorite: !currentContact.isFavorite
            )
            await refreshContact()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func toggleBlocked() async {
        do {
            try await appState.contactService.updateContactPreferences(
                contactID: currentContact.id,
                isBlocked: !currentContact.isBlocked
            )
            await refreshContact()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteContact() async {
        do {
            try await appState.contactService.removeContact(
                deviceID: currentContact.deviceID,
                publicKey: currentContact.publicKey
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetPath() async {
        do {
            try await appState.contactService.resetPath(
                deviceID: currentContact.deviceID,
                publicKey: currentContact.publicKey
            )
            await refreshContact()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func shareContact() async {
        do {
            try await appState.contactService.shareContact(publicKey: currentContact.publicKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshContact() async {
        if let updated = try? await appState.dataStore.fetchContact(id: currentContact.id) {
            currentContact = updated
        }
    }

    // MARK: - Profile Section

    private var profileSection: some View {
        Section {
            VStack(spacing: 16) {
                ContactAvatar(contact: currentContact, size: 100)

                VStack(spacing: 4) {
                    Text(currentContact.displayName)
                        .font(.title2)
                        .bold()

                    Text(contactTypeLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // Status indicators
                    HStack(spacing: 12) {
                        if currentContact.isFavorite {
                            Label("Favorite", systemImage: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                        }

                        if currentContact.isBlocked {
                            Label("Blocked", systemImage: "hand.raised.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        if currentContact.hasLocation {
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
            // Send message - only show when NOT from direct chat
            if !showFromDirectChat {
                Button {
                    appState.navigateToChat(with: currentContact)
                } label: {
                    Label("Send Message", systemImage: "message.fill")
                }
            }

            // Toggle favorite
            Button {
                Task {
                    await toggleFavorite()
                }
            } label: {
                Label(
                    currentContact.isFavorite ? "Remove from Favorites" : "Add to Favorites",
                    systemImage: currentContact.isFavorite ? "star.slash" : "star"
                )
            }

            // Share contact
            Button {
                Task {
                    await shareContact()
                }
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
                            Task {
                                await saveNickname()
                            }
                        }

                    Button("Save") {
                        Task {
                            await saveNickname()
                        }
                    }
                    .disabled(isSaving)
                } else {
                    Text(currentContact.nickname ?? "None")
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
                Text(currentContact.name)
                    .foregroundStyle(.secondary)
            }

            // Last seen
            if currentContact.lastAdvertTimestamp > 0 {
                HStack {
                    Text("Last Seen")
                    Spacer()
                    Text(Date(timeIntervalSince1970: TimeInterval(currentContact.lastAdvertTimestamp)), style: .relative)
                        .foregroundStyle(.secondary)
                }
            }

            // Unread count
            if currentContact.unreadCount > 0 {
                HStack {
                    Text("Unread Messages")
                    Spacer()
                    Text(currentContact.unreadCount, format: .number)
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
                Marker(currentContact.displayName, coordinate: contactCoordinate)
            }
            .frame(height: 200)
            .clipShape(.rect(cornerRadius: 12))
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            // Coordinates
            HStack {
                Text("Coordinates")
                Spacer()
                Text("\(currentContact.latitude, format: .number.precision(.fractionLength(4))), \(currentContact.longitude, format: .number.precision(.fractionLength(4)))")
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
            latitude: currentContact.latitude,
            longitude: currentContact.longitude
        )
    }

    private func openInMaps() {
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: contactCoordinate))
        mapItem.name = currentContact.displayName
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
            if !currentContact.isFloodRouted && currentContact.outPathLength >= 0 {
                HStack {
                    Text("Hops")
                    Spacer()
                    Text(currentContact.outPathLength, format: .number)
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
                Task {
                    await resetPath()
                }
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
            Button(role: currentContact.isBlocked ? nil : .destructive) {
                if currentContact.isBlocked {
                    // Unblock directly
                    Task {
                        await toggleBlocked()
                    }
                } else {
                    showingBlockAlert = true
                }
            } label: {
                Label(
                    currentContact.isBlocked ? "Unblock Contact" : "Block Contact",
                    systemImage: currentContact.isBlocked ? "hand.raised.slash" : "hand.raised"
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
        switch currentContact.type {
        case .chat: return "Chat Contact"
        case .repeater: return "Repeater"
        case .room: return "Room"
        }
    }

    private var publicKeyHex: String {
        currentContact.publicKeyPrefix.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private var routingInfo: String {
        if currentContact.isFloodRouted {
            return "Flood (broadcast)"
        } else if currentContact.outPathLength == 0 {
            return "Direct"
        } else {
            return "Multi-hop"
        }
    }

    private func saveNickname() async {
        isSaving = true
        do {
            try await appState.contactService.updateContactPreferences(
                contactID: currentContact.id,
                nickname: nickname.isEmpty ? nil : nickname
            )
            await refreshContact()
        } catch {
            errorMessage = error.localizedDescription
        }
        isEditingNickname = false
        isSaving = false
    }
}

#Preview("Default") {
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

#Preview("From Direct Chat") {
    NavigationStack {
        ContactDetailView(
            contact: ContactDTO(from: Contact(
                deviceID: UUID(),
                publicKey: Data(repeating: 0x42, count: 32),
                name: "Alice",
                latitude: 37.7749,
                longitude: -122.4194,
                isFavorite: true
            )),
            showFromDirectChat: true
        )
    }
    .environment(AppState())
}
