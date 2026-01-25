import os
import SwiftUI
import PocketMeshServices

private let logger = Logger(subsystem: "com.pocketmesh", category: "NodeAuthenticationSheet")

/// Reusable password entry sheet for both room servers and repeaters
struct NodeAuthenticationSheet: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss

    let contact: ContactDTO
    let role: RemoteNodeRole
    /// When true, hides the Node Details section (used when re-joining known rooms from chat list)
    let hideNodeDetails: Bool
    /// Optional custom title. If nil, uses default based on role ("Join Room" or "Admin Access")
    let customTitle: String?
    let onSuccess: (RemoteNodeSessionDTO) -> Void

    @State private var password: String = ""
    @State private var rememberPassword = true
    @State private var isAuthenticating = false
    @State private var errorMessage: String?
    @State private var hasSavedPassword = false

    // Countdown state
    @State private var authSecondsRemaining: Int?
    @State private var authStartTime: Date?
    @State private var authTimeoutSeconds: Int?
    @State private var countdownTask: Task<Void, Never>?

    private let maxPasswordLength = 15

    init(
        contact: ContactDTO,
        role: RemoteNodeRole,
        hideNodeDetails: Bool = false,
        customTitle: String? = nil,
        onSuccess: @escaping (RemoteNodeSessionDTO) -> Void
    ) {
        self.contact = contact
        self.role = role
        self.hideNodeDetails = hideNodeDetails
        self.customTitle = customTitle
        self.onSuccess = onSuccess
    }

    var body: some View {
        NavigationStack {
            Form {
                if !hideNodeDetails {
                    nodeDetailsSection
                }
                authenticationSection
                connectButton
            }
            .navigationTitle(customTitle ?? (role == .roomServer ? L10n.RemoteNodes.RemoteNodes.Auth.joinRoom : L10n.RemoteNodes.RemoteNodes.Auth.adminAccess))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.RemoteNodes.RemoteNodes.Auth.cancel) { dismiss() }
                }
            }
            .task {
                if let remoteNodeService = appState.services?.remoteNodeService,
                   let saved = await remoteNodeService.retrievePassword(forContact: contact) {
                    password = saved
                    hasSavedPassword = true
                }
            }
            .sensoryFeedback(.error, trigger: errorMessage)
        }
    }

    // MARK: - Sections

    private var nodeDetailsSection: some View {
        Section {
            LabeledContent(L10n.RemoteNodes.RemoteNodes.Auth.name, value: contact.displayName)
            LabeledContent(L10n.RemoteNodes.RemoteNodes.Auth.type, value: role == .roomServer ? L10n.RemoteNodes.RemoteNodes.Auth.typeRoom : L10n.RemoteNodes.RemoteNodes.Auth.typeRepeater)
        } header: {
            Text(L10n.RemoteNodes.RemoteNodes.Auth.nodeDetails)
        }
    }

    private var authenticationSection: some View {
        Section {
            SecureField(L10n.RemoteNodes.RemoteNodes.Auth.password, text: $password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            Toggle(L10n.RemoteNodes.RemoteNodes.Auth.rememberPassword, isOn: $rememberPassword)
        } header: {
            Text(L10n.RemoteNodes.RemoteNodes.Auth.authentication)
        } footer: {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .accessibilityLabel(L10n.RemoteNodes.RemoteNodes.Auth.errorPrefix(errorMessage))
            } else if password.count > maxPasswordLength {
                Text(role == .repeater ? L10n.RemoteNodes.RemoteNodes.Auth.passwordTooLongRepeaters(maxPasswordLength) : L10n.RemoteNodes.RemoteNodes.Auth.passwordTooLongRooms(maxPasswordLength))
            } else if let remaining = authSecondsRemaining, remaining > 0 {
                Text(L10n.RemoteNodes.RemoteNodes.Auth.secondsRemaining(remaining))
            } else {
                // Reserve footer space to prevent layout shift when error appears
                Text(" ")
                    .accessibilityHidden(true)
            }
        }
        .onChange(of: password) {
            if errorMessage != nil {
                errorMessage = nil
            }
        }
        .onChange(of: authSecondsRemaining) { oldValue, newValue in
            // Announce countdown for VoiceOver at meaningful intervals
            guard let remaining = newValue, remaining > 0 else { return }
            // Announce when countdown starts or at 30/15/10/5 second thresholds
            let shouldAnnounce = oldValue == nil || remaining == 30 || remaining == 15 || remaining == 10 || remaining <= 5
            if shouldAnnounce {
                AccessibilityNotification.Announcement(L10n.RemoteNodes.RemoteNodes.Auth.secondsRemainingAnnouncement(remaining)).post()
            }
        }
    }

    private var connectButton: some View {
        Section {
            Button {
                authenticate()
            } label: {
                if isAuthenticating {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                } else {
                    Text(role == .roomServer ? L10n.RemoteNodes.RemoteNodes.Auth.joinRoom : L10n.RemoteNodes.RemoteNodes.Auth.connect)
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(isAuthenticating)
        }
    }

    // MARK: - Authentication

    private func authenticate() {
        // Clear any previous error
        errorMessage = nil
        isAuthenticating = true
        cleanupCountdownState()

        Task {
            do {
                guard let device = appState.connectedDevice else {
                    throw RemoteNodeError.notConnected
                }

                guard let services = appState.services else {
                    throw RemoteNodeError.notConnected
                }

                // Determine path length from contact for timeout calculation
                let pathLength = UInt8(max(0, contact.outPathLength))

                let session: RemoteNodeSessionDTO
                // MeshCore repeaters and rooms only support 15-character passwords, truncate if needed
                let passwordToUse = password.count > maxPasswordLength
                    ? String(password.prefix(maxPasswordLength))
                    : password

                // Callback to start countdown when firmware timeout is known
                let onTimeoutKnown: @Sendable (Int) async -> Void = { [self] seconds in
                    await MainActor.run {
                        self.authTimeoutSeconds = seconds
                        self.authStartTime = Date.now
                        self.authSecondsRemaining = seconds
                        self.startCountdownTask()
                    }
                }

                if role == .roomServer {
                    session = try await services.roomServerService.joinRoom(
                        deviceID: device.id,
                        contact: contact,
                        password: passwordToUse,
                        rememberPassword: rememberPassword,
                        pathLength: pathLength,
                        onTimeoutKnown: onTimeoutKnown
                    )
                } else {
                    session = try await services.repeaterAdminService.connectAsAdmin(
                        deviceID: device.id,
                        contact: contact,
                        password: passwordToUse,
                        rememberPassword: rememberPassword,
                        pathLength: pathLength,
                        onTimeoutKnown: onTimeoutKnown
                    )
                }

                // Delete saved password if user unchecked "Remember Password"
                if hasSavedPassword && !rememberPassword {
                    do {
                        try await services.remoteNodeService.deletePassword(forContact: contact)
                    } catch {
                        logger.warning("Failed to delete saved password: \(error)")
                    }
                }

                await MainActor.run {
                    cleanupCountdownState()
                    dismiss()
                    onSuccess(session)
                }
            } catch {
                await MainActor.run {
                    cleanupCountdownState()
                    errorMessage = error.localizedDescription
                    isAuthenticating = false
                }
            }
        }
    }

    // MARK: - Countdown

    private func startCountdownTask() {
        countdownTask = Task {
            while !Task.isCancelled, let timeout = authTimeoutSeconds, let startTime = authStartTime {
                do {
                    try await Task.sleep(for: .seconds(5))
                } catch {
                    break
                }

                let elapsed = Date.now.timeIntervalSince(startTime)
                let remaining = max(0, timeout - Int(elapsed))
                authSecondsRemaining = remaining
            }
        }
    }

    private func cleanupCountdownState() {
        countdownTask?.cancel()
        countdownTask = nil
        authSecondsRemaining = nil
        authStartTime = nil
        authTimeoutSeconds = nil
    }
}

#Preview {
    NodeAuthenticationSheet(
        contact: ContactDTO(from: Contact(
            deviceID: UUID(),
            publicKey: Data(repeating: 0x42, count: 32),
            name: "Test Room",
            typeRawValue: ContactType.room.rawValue
        )),
        role: .roomServer,
        onSuccess: { _ in }
    )
    .environment(\.appState, AppState())
}
