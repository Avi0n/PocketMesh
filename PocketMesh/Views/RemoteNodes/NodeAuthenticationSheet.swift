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
                errorSection
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
            if password.count > maxPasswordLength {
                if role == .repeater {
                    Text("MeshCore repeaters only accept passwords up to \(maxPasswordLength) characters. Extra characters will be ignored.")
                } else {
                    Text("MeshCore rooms only accept passwords up to \(maxPasswordLength) characters. Extra characters will be ignored.")
                }
            }
        }
    }

    @ViewBuilder
    private var errorSection: some View {
        if let errorMessage {
            Section {
                Text(errorMessage)
                    .foregroundStyle(.red)
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

                if role == .roomServer {
                    session = try await services.roomServerService.joinRoom(
                        deviceID: device.id,
                        contact: contact,
                        password: passwordToUse,
                        rememberPassword: rememberPassword,
                        pathLength: pathLength
                    )
                } else {
                    session = try await services.repeaterAdminService.connectAsAdmin(
                        deviceID: device.id,
                        contact: contact,
                        password: passwordToUse,
                        rememberPassword: rememberPassword,
                        pathLength: pathLength
                    )
                }

                await MainActor.run {
                    dismiss()
                    onSuccess(session)
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isAuthenticating = false
                }
            }
        }
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
