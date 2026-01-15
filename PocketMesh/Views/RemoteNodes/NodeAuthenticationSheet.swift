import SwiftUI
import PocketMeshServices

/// Reusable password entry sheet for both room servers and repeaters
struct NodeAuthenticationSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let contact: ContactDTO
    let role: RemoteNodeRole
    /// When true, hides the Node Details section (used when re-joining known rooms from chat list)
    let hideNodeDetails: Bool
    /// Optional custom title. If nil, uses default based on role ("Join Room" or "Admin Access")
    let customTitle: String?
    let onSuccess: (RemoteNodeSessionDTO) -> Void

    @State private var password: String = ""
    @State private var showPassword = false
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
            .navigationTitle(customTitle ?? (role == .roomServer ? "Join Room" : "Admin Access"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                if let remoteNodeService = appState.services?.remoteNodeService {
                    hasSavedPassword = await remoteNodeService.hasPassword(forContact: contact)
                }
            }
            .sensoryFeedback(.error, trigger: errorMessage)
        }
    }

    // MARK: - Sections

    private var nodeDetailsSection: some View {
        Section {
            LabeledContent("Name", value: contact.displayName)
            LabeledContent("Type", value: role == .roomServer ? "Room" : "Repeater")
        } header: {
            Text("Node Details")
        }
    }

    private var authenticationSection: some View {
        Section {
            if hasSavedPassword && password.isEmpty {
                HStack {
                    Image(systemName: "key.fill")
                        .foregroundStyle(.secondary)
                    Text("Using saved password")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Enter New") {
                        hasSavedPassword = false
                        errorMessage = nil
                    }
                    .font(.callout)
                }
            } else {
                HStack {
                    Group {
                        if showPassword {
                            TextField("Password", text: $password)
                        } else {
                            SecureField("Password", text: $password)
                        }
                    }
                    .textContentType(.password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Toggle("Remember Password", isOn: $rememberPassword)
        } header: {
            Text("Authentication")
        } footer: {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .foregroundStyle(.red)
                    .accessibilityLabel("Error: \(errorMessage)")
            } else if password.count > maxPasswordLength {
                Text("MeshCore \(role == .repeater ? "repeaters" : "rooms") only accept passwords up to \(maxPasswordLength) characters. Extra characters will be ignored.")
            } else if let remaining = authSecondsRemaining, remaining > 0 {
                Text("Up to \(remaining) seconds remaining")
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
                    Text(role == .roomServer ? "Join Room" : "Connect")
                        .frame(maxWidth: .infinity)
                }
            }
            .disabled(isAuthenticating || (role == .repeater && password.isEmpty && !hasSavedPassword))
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
                // Only use keychain lookup (nil) when user has saved password and hasn't entered new one.
                // Empty string is valid for rooms with empty guest password.
                var passwordToUse = (hasSavedPassword && password.isEmpty) ? nil : password

                // MeshCore repeaters and rooms only support 15-character passwords, truncate if needed
                if let pw = passwordToUse, pw.count > maxPasswordLength {
                    passwordToUse = String(pw.prefix(maxPasswordLength))
                }

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
    .environment(AppState())
}
