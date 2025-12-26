import SwiftUI
import MapKit
import PocketMeshServices

/// Detailed view for a single contact
struct ContactDetailView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let contact: ContactDTO
    let showFromDirectChat: Bool

    /// Sheet types for the contact detail view
    private enum ActiveSheet: Identifiable, Hashable {
        case repeaterAuth
        case repeaterStatus(RemoteNodeSessionDTO)

        var id: String {
            switch self {
            case .repeaterAuth: return "auth"
            case .repeaterStatus(let session): return "status-\(session.id)"
            }
        }
    }

    @State private var currentContact: ContactDTO
    @State private var nickname = ""
    @State private var isEditingNickname = false
    @State private var showingBlockAlert = false
    @State private var showingDeleteAlert = false
    @State private var showingShareSheet = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var pathViewModel = PathManagementViewModel()
    @State private var showAdvanced = false
    @State private var showRoomJoinSheet = false
    @State private var activeSheet: ActiveSheet?
    @State private var pendingSheet: ActiveSheet?
    @State private var showRoomConversation = false
    @State private var connectedRoomSession: RemoteNodeSessionDTO?
    // Admin access navigation state (separate from telemetry sheet flow)
    @State private var showRepeaterAdminAuth = false
    @State private var adminSession: RemoteNodeSessionDTO?
    @State private var navigateToSettings = false
    // QR sharing state
    @State private var showQRShareSheet = false

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

            // Network path controls
            networkPathSection

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
        .task {
            pathViewModel.configure(appState: appState) {
                Task { @MainActor in
                    await refreshContact()
                }
            }
            await pathViewModel.loadContacts(deviceID: currentContact.deviceID)

            // Fetch fresh contact data from device to catch external changes
            // (e.g., user modified path in official MeshCore app)
            if let freshContact = try? await appState.services?.contactService.getContact(
                deviceID: currentContact.deviceID,
                publicKey: currentContact.publicKey
            ) {
                currentContact = freshContact
            }

            // Wire up path discovery response handler to receive push notifications
            await appState.services?.advertisementService.setPathDiscoveryHandler { [weak pathViewModel] response in
                Task { @MainActor in
                    pathViewModel?.handleDiscoveryResponse(hopCount: response.outPath.count)
                }
            }
        }
        .onDisappear {
            pathViewModel.cancelDiscovery()
        }
        .sheet(isPresented: $pathViewModel.showingPathEditor) {
            PathEditingSheet(viewModel: pathViewModel, contact: currentContact)
        }
        .alert("Path Error", isPresented: $pathViewModel.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(pathViewModel.errorMessage ?? "An unknown error occurred")
        }
        .alert("Path Discovery", isPresented: $pathViewModel.showDiscoveryResult) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(pathViewModel.discoveryResult?.description ?? "")
        }
        .sheet(isPresented: $showRoomJoinSheet) {
            if let role = RemoteNodeRole(contactType: currentContact.type) {
                NodeAuthenticationSheet(contact: currentContact, role: role) { session in
                    // Navigate to Chats tab with the room conversation
                    appState.navigateToRoom(with: session)
                }
                .presentationSizing(.page)
            }
        }
        .sheet(item: $activeSheet, onDismiss: presentPendingSheet) { sheet in
            switch sheet {
            case .repeaterAuth:
                if let role = RemoteNodeRole(contactType: currentContact.type) {
                    NodeAuthenticationSheet(
                        contact: currentContact,
                        role: role,
                        customTitle: "Telemetry Access"
                    ) { session in
                        pendingSheet = .repeaterStatus(session)
                        activeSheet = nil  // Triggers dismissal, then onDismiss fires
                    }
                    .presentationSizing(.page)
                }
            case .repeaterStatus(let session):
                RepeaterStatusView(session: session)
            }
        }
        .navigationDestination(isPresented: $showRoomConversation) {
            if let session = connectedRoomSession {
                RoomConversationView(session: session)
            }
        }
        .sheet(isPresented: $showRepeaterAdminAuth, onDismiss: {
            // Trigger navigation after sheet is fully dismissed to avoid race conditions
            if adminSession != nil {
                navigateToSettings = true
            }
        }) {
            if let role = RemoteNodeRole(contactType: currentContact.type) {
                NodeAuthenticationSheet(contact: currentContact, role: role) { session in
                    adminSession = session
                    showRepeaterAdminAuth = false
                    // Navigation triggers in onDismiss above
                }
                .presentationSizing(.page)
            }
        }
        .sheet(isPresented: $showQRShareSheet) {
            ContactQRShareSheet(
                contactName: currentContact.name,
                publicKey: currentContact.publicKey,
                contactType: currentContact.type
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .navigationDestination(isPresented: $navigateToSettings) {
            if let session = adminSession {
                RepeaterSettingsView(session: session)
            }
        }
    }

    // MARK: - Sheet Management

    private func presentPendingSheet() {
        if let next = pendingSheet {
            pendingSheet = nil
            activeSheet = next
        }
    }

    // MARK: - Actions

    private func toggleFavorite() async {
        do {
            try await appState.services?.contactService.updateContactPreferences(
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
            try await appState.services?.contactService.updateContactPreferences(
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
            try await appState.services?.contactService.removeContact(
                deviceID: currentContact.deviceID,
                publicKey: currentContact.publicKey
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func shareContact() async {
        do {
            try await appState.services?.contactService.shareContact(publicKey: currentContact.publicKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshContact() async {
        if let updated = try? await appState.services?.dataStore.fetchContact(id: currentContact.id) {
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
            // Role-specific actions based on contact type
            switch currentContact.type {
            case .room:
                // Room server actions
                Button {
                    showRoomJoinSheet = true
                } label: {
                    Label("Join Room", systemImage: "door.left.hand.open")
                }

            case .repeater:
                // Telemetry button - shows read-only status sheet after auth
                Button {
                    activeSheet = .repeaterAuth
                } label: {
                    Label("Telemetry", systemImage: "chart.line.uptrend.xyaxis")
                }

                // Admin Access - navigates to settings view after auth
                Button {
                    adminSession = nil  // Clear stale session before presenting sheet
                    showRepeaterAdminAuth = true
                } label: {
                    Label("Admin Access", systemImage: "gearshape.2")
                }

            case .chat:
                // Send message - only show when NOT from direct chat and NOT blocked
                if !showFromDirectChat && !currentContact.isBlocked {
                    Button {
                        appState.navigateToChat(with: currentContact)
                    } label: {
                        Label("Send Message", systemImage: "message.fill")
                    }
                }
            }

            // Toggle favorite (for all contact types)
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

            // Share Contact via QR
            Button {
                showQRShareSheet = true
            } label: {
                Label("Share Contact", systemImage: "square.and.arrow.up")
            }

            // Share Contact via Advert
            Button {
                Task {
                    await shareContact()
                }
            } label: {
                Label("Share Contact via Advert", systemImage: "antenna.radiowaves.left.and.right")
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

            // Last advert
            if currentContact.lastAdvertTimestamp > 0 {
                HStack {
                    Text("Last Advert")
                    Spacer()
                    ConversationTimestamp(date: Date(timeIntervalSince1970: TimeInterval(currentContact.lastAdvertTimestamp)))
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

    // MARK: - Network Path Section

    private var networkPathSection: some View {
        Section {
            // Current routing path
            VStack(alignment: .leading, spacing: 4) {
                Text("Route")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(routeDisplayText)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(pathAccessibilityLabel)

            // Path Discovery button (prominent)
            if pathViewModel.isDiscovering {
                HStack {
                    Label("Discovering path...", systemImage: "antenna.radiowaves.left.and.right")
                    Spacer()
                    ProgressView()
                    Button("Cancel") {
                        pathViewModel.cancelDiscovery()
                    }
                    .buttonStyle(.borderless)
                    .font(.subheadline)
                }
            } else {
                Button {
                    Task {
                        await pathViewModel.discoverPath(for: currentContact)
                    }
                } label: {
                    Label("Discover Path", systemImage: "antenna.radiowaves.left.and.right")
                }
            }

            // Edit Path button (secondary)
            Button {
                Task {
                    await pathViewModel.loadContacts(deviceID: currentContact.deviceID)
                }
                pathViewModel.initializeEditablePath(from: currentContact)
                pathViewModel.showingPathEditor = true
            } label: {
                Label("Edit Path", systemImage: "pencil")
            }

            // Reset Path button (destructive, disabled when already flood)
            Button(role: .destructive) {
                Task {
                    await pathViewModel.resetPath(for: currentContact)
                    await refreshContact()
                }
            } label: {
                HStack {
                    Label("Reset Path", systemImage: "arrow.triangle.2.circlepath")
                    if pathViewModel.isSettingPath {
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
            }
            .disabled(pathViewModel.isSettingPath || currentContact.isFloodRouted)
        } header: {
            Text("Network Path")
        } footer: {
            Text(networkPathFooterText)
        }
    }

    // Computed property for path display with resolved names
    private var pathDisplayWithNames: String {
        let pathData = currentContact.outPath
        let pathLength = Int(max(0, currentContact.outPathLength))
        guard pathLength > 0 else { return "Direct" }

        let relevantPath = pathData.prefix(pathLength)
        return relevantPath.map { byte in
            if let name = pathViewModel.resolveHashToName(byte) {
                return "\(name)"
            }
            return String(format: "%02X", byte)
        }.joined(separator: " \u{2192} ")
    }

    // Route display text for simplified view
    private var routeDisplayText: String {
        if currentContact.isFloodRouted {
            return "Flood"
        } else if currentContact.outPathLength == 0 {
            return "Direct"
        } else {
            return pathDisplayWithNames
        }
    }

    // Footer text for network path section
    private var networkPathFooterText: String {
        if currentContact.isFloodRouted {
            return "Messages are broadcast to all nodes. Discover Path to find an optimal route."
        } else {
            return "Messages route through the path shown. Reset Path to use flood routing instead."
        }
    }

    // VoiceOver accessibility label for path
    private var pathAccessibilityLabel: String {
        if currentContact.isFloodRouted {
            return "Route: Flood"
        } else if currentContact.outPathLength == 0 {
            return "Route: Direct"
        } else {
            return "Route: \(pathDisplayWithNames)"
        }
    }

    // MARK: - Technical Section

    private var technicalSection: some View {
        Section {
            // Public key
            VStack(alignment: .leading, spacing: 4) {
                Text("Public Key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(currentContact.publicKey.hexString(separator: " "))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }

            // Contact type
            HStack {
                Text("Type")
                Spacer()
                Text(contactTypeLabel)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Technical")
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

    private func saveNickname() async {
        isSaving = true
        do {
            try await appState.services?.contactService.updateContactPreferences(
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
