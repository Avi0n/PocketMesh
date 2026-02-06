import Accessibility
import MapKit
import os
import PocketMeshServices
import SwiftUI

/// Result of a ping operation
enum PingResult {
    case success(latencyMs: Int, snrThere: Double, snrBack: Double)
    case error(String)
}

private enum PingError: Error {
    case notConnected
    case timeout
}

/// Displays ping result with latency and bidirectional SNR
struct PingResultRow: View {
    let result: PingResult

    var body: some View {
        switch result {
        case .success(let latencyMs, let snrThere, let snrBack):
            let snrFormat = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2))
            Label {
                Text("\(latencyMs) ms  ·  SNR ↑ \(snrThere, format: snrFormat) dB  ↓ \(snrBack, format: snrFormat) dB")
                    .font(.subheadline)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L10n.Contacts.Contacts.Detail.pingSuccessLabel(latencyMs, Int(snrThere), Int(snrBack)))
        case .error(let message):
            Label {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L10n.Contacts.Contacts.Detail.pingFailureLabel(message))
        }
    }
}

/// Detailed view for a single contact
struct ContactDetailView: View {
    @Environment(\.appState) private var appState
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
    @State private var isTogglingFavorite = false
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
    // Ping state
    @State private var isPinging = false
    @State private var pingResult: PingResult?

    private let pingLogger = Logger(subsystem: "com.pocketmesh", category: "Ping")

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
        .navigationTitle(contactTypeLabel)
        .navigationBarTitleDisplayMode(.inline)
        .alert(L10n.Contacts.Contacts.Detail.Alert.Block.title, isPresented: $showingBlockAlert) {
            Button(L10n.Contacts.Contacts.Common.cancel, role: .cancel) { }
            Button(L10n.Contacts.Contacts.Swipe.block, role: .destructive) {
                Task {
                    await toggleBlocked()
                }
            }
        } message: {
            Text(L10n.Contacts.Contacts.Detail.Alert.Block.message(currentContact.displayName))
        }
        .alert(L10n.Contacts.Contacts.Detail.Alert.Delete.title(contactTypeLabel), isPresented: $showingDeleteAlert) {
            Button(L10n.Contacts.Contacts.Common.cancel, role: .cancel) { }
            Button(L10n.Contacts.Contacts.Common.delete, role: .destructive) {
                Task {
                    await deleteContact()
                }
            }
        } message: {
            Text(L10n.Contacts.Contacts.Detail.Alert.Delete.message(currentContact.displayName))
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
        .alert(L10n.Contacts.Contacts.Detail.Alert.pathError, isPresented: $pathViewModel.showError) {
            Button(L10n.Contacts.Contacts.Common.ok, role: .cancel) { }
        } message: {
            Text(pathViewModel.errorMessage ?? L10n.Contacts.Contacts.Common.errorOccurred)
        }
        .alert(L10n.Contacts.Contacts.Detail.Alert.pathDiscovery, isPresented: $pathViewModel.showDiscoveryResult) {
            Button(L10n.Contacts.Contacts.Common.ok, role: .cancel) { }
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
                        customTitle: L10n.Contacts.Contacts.Detail.telemetryAccess
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
        isTogglingFavorite = true
        defer { isTogglingFavorite = false }

        do {
            try await appState.services?.contactService.setContactFavorite(
                currentContact.id,
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

    private func pingRepeater() async {
        guard !isPinging else { return }
        isPinging = true
        pingResult = nil

        let startTime = ContinuousClock.now
        let tag = UInt32.random(in: 0..<UInt32.max)

        do {
            guard let services = appState.services else {
                throw PingError.notConnected
            }

            let pathData = Data(currentContact.publicKey.prefix(6))

            // Task group: listener starts BEFORE sendTrace to avoid race with fast responses
            let (snrThere, snrBack) = try await withThrowingTaskGroup(
                of: (snrThere: Double, snrBack: Double).self
            ) { group in
                // Listen for 0x88 rxLogData trace response (arrives before 0x89 traceData)
                group.addTask {
                    for await notification in NotificationCenter.default.notifications(named: .rxLogTraceReceived) {
                        if let notifTag = notification.userInfo?["tag"] as? UInt32, notifTag == tag {
                            let localSnr = notification.userInfo?["localSnr"] as? Double
                            let remoteSnr = notification.userInfo?["remoteSnr"] as? Double
                            return (snrThere: remoteSnr ?? 0, snrBack: localSnr ?? 0)
                        }
                    }
                    throw CancellationError()
                }

                // Send trace (listeners are already active above)
                let sentInfo = try await services.binaryProtocolService.sendTrace(tag: tag, path: pathData)

                // Timeout using actual suggested timeout from device
                group.addTask {
                    try await Task.sleep(for: .milliseconds(sentInfo.suggestedTimeoutMs))
                    throw PingError.timeout
                }

                guard let result = try await group.next() else {
                    throw PingError.timeout
                }
                group.cancelAll()
                return result
            }

            let elapsed = ContinuousClock.now - startTime
            let latencyMs = Int(elapsed / .milliseconds(1))

            pingResult = .success(latencyMs: latencyMs, snrThere: snrThere, snrBack: snrBack)
            let announcement = L10n.Contacts.Contacts.Detail.pingSuccessAnnouncement(latencyMs)
            AccessibilityNotification.Announcement(announcement).post()
        } catch {
            pingLogger.error("Ping failed: \(error.localizedDescription)")
            pingResult = .error(L10n.Contacts.Contacts.Detail.pingNoResponse)
            let announcement = L10n.Contacts.Contacts.Detail.pingFailureAnnouncement
            AccessibilityNotification.Announcement(announcement).post()
        }

        isPinging = false
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
                avatarView

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
                            Label(L10n.Contacts.Contacts.Detail.favorite, systemImage: "star.fill")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                        }

                        if currentContact.isBlocked {
                            Label(L10n.Contacts.Contacts.Detail.blocked, systemImage: "hand.raised.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }

                        if currentContact.hasLocation {
                            Label(L10n.Contacts.Contacts.Detail.hasLocation, systemImage: "location.fill")
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

    @ViewBuilder
    private var avatarView: some View {
        switch currentContact.type {
        case .chat:
            ContactAvatar(contact: currentContact, size: 100)
        case .repeater:
            NodeAvatar(publicKey: currentContact.publicKey, role: .repeater, size: 100)
        case .room:
            NodeAvatar(publicKey: currentContact.publicKey, role: .roomServer, size: 100)
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
                    Label(L10n.Contacts.Contacts.Detail.joinRoom, systemImage: "door.left.hand.open")
                }

            case .repeater:
                // Telemetry button - shows read-only status sheet after auth
                Button {
                    activeSheet = .repeaterAuth
                } label: {
                    Label(L10n.Contacts.Contacts.Detail.telemetry, systemImage: "chart.line.uptrend.xyaxis")
                }

                // Admin Access - navigates to settings view after auth
                Button {
                    adminSession = nil  // Clear stale session before presenting sheet
                    showRepeaterAdminAuth = true
                } label: {
                    Label(L10n.Contacts.Contacts.Detail.adminAccess, systemImage: "gearshape.2")
                }

            case .chat:
                // Send message - only show when NOT from direct chat and NOT blocked
                if !showFromDirectChat && !currentContact.isBlocked {
                    Button {
                        appState.navigateToChat(with: currentContact)
                    } label: {
                        Label(L10n.Contacts.Contacts.Detail.sendMessage, systemImage: "message.fill")
                    }
                    .radioDisabled(for: appState.connectionState)
                }
            }

            // Toggle favorite (for all contact types)
            Button {
                Task {
                    await toggleFavorite()
                }
            } label: {
                HStack {
                    Label(
                        currentContact.isFavorite ? L10n.Contacts.Contacts.Detail.removeFromFavorites : L10n.Contacts.Contacts.Detail.addToFavorites,
                        systemImage: currentContact.isFavorite ? "star.slash" : "star"
                    )
                    if isTogglingFavorite {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isTogglingFavorite)
            .radioDisabled(for: appState.connectionState)

            // Share Contact via QR
            Button {
                showQRShareSheet = true
            } label: {
                Label(L10n.Contacts.Contacts.Detail.shareContact, systemImage: "square.and.arrow.up")
            }

            // Share Contact via Advert
            Button {
                Task {
                    await shareContact()
                }
            } label: {
                Label(L10n.Contacts.Contacts.Detail.shareViaAdvert, systemImage: "antenna.radiowaves.left.and.right")
            }
            .radioDisabled(for: appState.connectionState)

            // Ping Repeater (repeater-only)
            if currentContact.type == .repeater {
                Button {
                    Task { await pingRepeater() }
                } label: {
                    HStack {
                        Label(L10n.Contacts.Contacts.Detail.pingRepeater, systemImage: "wave.3.right")
                        if isPinging {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isPinging)
                .radioDisabled(for: appState.connectionState)

                // Ping result row
                if let result = pingResult {
                    PingResultRow(result: result)
                }
            }
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        Section {
            // Nickname
            HStack {
                Text(L10n.Contacts.Contacts.Detail.nickname)

                Spacer()

                if isEditingNickname {
                    TextField(L10n.Contacts.Contacts.Detail.nickname, text: $nickname)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 150)
                        .onSubmit {
                            Task {
                                await saveNickname()
                            }
                        }

                    Button(L10n.Contacts.Contacts.Common.save) {
                        Task {
                            await saveNickname()
                        }
                    }
                    .disabled(isSaving)
                } else {
                    Text(currentContact.nickname ?? L10n.Contacts.Contacts.Detail.nicknameNone)
                        .foregroundStyle(.secondary)

                    Button(L10n.Contacts.Contacts.Common.edit) {
                        isEditingNickname = true
                    }
                    .buttonStyle(.borderless)
                }
            }

            // Original name
            HStack {
                Text(L10n.Contacts.Contacts.Detail.name)
                Spacer()
                Text(currentContact.name)
                    .foregroundStyle(.secondary)
            }

            // Last advert
            if currentContact.lastAdvertTimestamp > 0 {
                HStack {
                    Text(L10n.Contacts.Contacts.Detail.lastAdvert)
                    Spacer()
                    ConversationTimestamp(date: Date(timeIntervalSince1970: TimeInterval(currentContact.lastAdvertTimestamp)), font: .body)
                }
            }

            // Unread count
            if currentContact.unreadCount > 0 {
                HStack {
                    Text(L10n.Contacts.Contacts.Detail.unreadMessages)
                    Spacer()
                    Text(currentContact.unreadCount, format: .number)
                        .foregroundStyle(.blue)
                }
            }
        } header: {
            Text(L10n.Contacts.Contacts.Detail.info)
        }
    }

    // MARK: - Location Section

    private var locationSection: some View {
        Section {
            // Mini map
            Map(position: .constant(.region(MKCoordinateRegion(
                center: contactCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
            )))) {
                Marker(currentContact.displayName, coordinate: contactCoordinate)
            }
            .frame(height: 200)
            .clipShape(.rect(cornerRadius: 12))
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            // Coordinates
            HStack {
                Text(L10n.Contacts.Contacts.Detail.coordinates)
                Spacer()
                Text("\(currentContact.latitude, format: .number.precision(.fractionLength(4))), \(currentContact.longitude, format: .number.precision(.fractionLength(4)))")
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(
                UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            )

            // Open in Maps
            Button {
                openInMaps()
            } label: {
                Label(L10n.Contacts.Contacts.Detail.openInMaps, systemImage: "map")
            }
        } header: {
            Text(L10n.Contacts.Contacts.Detail.location)
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
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.Contacts.Contacts.Detail.route)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text(routeDisplayText)
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                }
            } icon: {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(pathAccessibilityLabel)

            // Hops away (only when path is known)
            if !currentContact.isFloodRouted {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n.Contacts.Contacts.Detail.hopsAway)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text(currentContact.outPathLength, format: .number)
                            .font(.caption.monospaced())
                            .foregroundStyle(.primary)
                    }
                } icon: {
                    Image(systemName: "chevron.forward.2")
                        .foregroundStyle(.secondary)
                }
            }

            // Path Discovery button (prominent)
            if pathViewModel.isDiscovering {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Label(L10n.Contacts.Contacts.Detail.discoveringPath, systemImage: "antenna.radiowaves.left.and.right")
                        Spacer()
                        ProgressView()
                        Button(L10n.Contacts.Contacts.Common.cancel) {
                            pathViewModel.cancelDiscovery()
                        }
                        .buttonStyle(.borderless)
                        .font(.subheadline)
                    }

                    if let remaining = pathViewModel.discoverySecondsRemaining, remaining > 0 {
                        Text(L10n.Contacts.Contacts.Detail.secondsRemaining(remaining))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Button {
                    Task {
                        await pathViewModel.discoverPath(for: currentContact)
                    }
                } label: {
                    Label(L10n.Contacts.Contacts.Detail.discoverPath, systemImage: "antenna.radiowaves.left.and.right")
                }
                .radioDisabled(for: appState.connectionState)
            }

            // Edit Path button (secondary)
            Button {
                Task {
                    await pathViewModel.loadContacts(deviceID: currentContact.deviceID)
                    pathViewModel.initializeEditablePath(from: currentContact)
                    pathViewModel.showingPathEditor = true
                }
            } label: {
                Label(L10n.Contacts.Contacts.Detail.editPath, systemImage: "pencil")
            }
            .radioDisabled(for: appState.connectionState)

            // Reset Path button (destructive, disabled when already flood)
            Button(role: .destructive) {
                Task {
                    await pathViewModel.resetPath(for: currentContact)
                    await refreshContact()
                }
            } label: {
                HStack {
                    Label(L10n.Contacts.Contacts.Detail.resetPath, systemImage: "arrow.triangle.2.circlepath")
                    if pathViewModel.isSettingPath {
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
            }
            .radioDisabled(for: appState.connectionState, or: pathViewModel.isSettingPath || currentContact.isFloodRouted)
        } header: {
            Text(L10n.Contacts.Contacts.Detail.networkPath)
        } footer: {
            Text(networkPathFooterText)
        }
    }

    // Computed property for path display with resolved names
    private var pathDisplayWithNames: String {
        let pathData = currentContact.outPath
        let pathLength = Int(max(0, currentContact.outPathLength))
        guard pathLength > 0 else { return L10n.Contacts.Contacts.Route.direct }

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
            return L10n.Contacts.Contacts.Route.flood
        } else if currentContact.outPathLength == 0 {
            return L10n.Contacts.Contacts.Route.direct
        } else {
            return pathDisplayWithNames
        }
    }

    // Footer text for network path section
    private var networkPathFooterText: String {
        if currentContact.isFloodRouted {
            return L10n.Contacts.Contacts.Detail.floodFooter
        } else {
            return L10n.Contacts.Contacts.Detail.pathFooter
        }
    }

    // VoiceOver accessibility label for path
    private var pathAccessibilityLabel: String {
        if currentContact.isFloodRouted {
            return L10n.Contacts.Contacts.Detail.routeFlood
        } else if currentContact.outPathLength == 0 {
            return L10n.Contacts.Contacts.Detail.routeDirect
        } else {
            return L10n.Contacts.Contacts.Detail.routePrefix(pathDisplayWithNames)
        }
    }

    // MARK: - Technical Section

    private var technicalSection: some View {
        Section {
            // Public key
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.Contacts.Contacts.Detail.publicKey)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(currentContact.publicKey.hexString(separator: " "))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }

            // Contact type
            HStack {
                Text(L10n.Contacts.Contacts.Detail.type)
                Spacer()
                Text(contactTypeLabel)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text(L10n.Contacts.Contacts.Detail.technical)
        }
    }

    // MARK: - Danger Section

    private var dangerSection: some View {
        Section {
            if currentContact.type == .chat {
                Button {
                    if currentContact.isBlocked {
                        Task {
                            await toggleBlocked()
                        }
                    } else {
                        showingBlockAlert = true
                    }
                } label: {
                    Label(
                        currentContact.isBlocked ? L10n.Contacts.Contacts.Detail.unblockContact : L10n.Contacts.Contacts.Detail.blockContact,
                        systemImage: currentContact.isBlocked ? "hand.raised.slash" : "hand.raised"
                    )
                }
                .radioDisabled(for: appState.connectionState)
            }

            Button(role: .destructive) {
                showingDeleteAlert = true
            } label: {
                Label(L10n.Contacts.Contacts.Detail.deleteType(contactTypeLabel), systemImage: "trash")
            }
            .radioDisabled(for: appState.connectionState)
        } header: {
            Text(L10n.Contacts.Contacts.Detail.dangerZone)
        }
    }

    // MARK: - Helpers

    private var contactTypeLabel: String {
        switch currentContact.type {
        case .chat: return L10n.Contacts.Contacts.NodeKind.contact
        case .repeater: return L10n.Contacts.Contacts.NodeKind.repeater
        case .room: return L10n.Contacts.Contacts.NodeKind.room
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
    .environment(\.appState, AppState())
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
    .environment(\.appState, AppState())
}
