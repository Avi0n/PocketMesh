import SwiftUI
import PocketMeshKit

/// Reusable password entry sheet for both room servers and repeaters
struct NodeAuthenticationSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let contact: ContactDTO
    let role: RemoteNodeRole
    /// When true, hides the Node Details section (used when re-joining known rooms from chat list)
    let hideNodeDetails: Bool
    let onSuccess: (RemoteNodeSessionDTO) -> Void

    @State private var password: String = ""
    @State private var showPassword = false
    @State private var rememberPassword = true
    @State private var isAuthenticating = false
    @State private var errorMessage: String?

    private let maxPasswordLength = 15

    init(
        contact: ContactDTO,
        role: RemoteNodeRole,
        hideNodeDetails: Bool = false,
        onSuccess: @escaping (RemoteNodeSessionDTO) -> Void
    ) {
        self.contact = contact
        self.role = role
        self.hideNodeDetails = hideNodeDetails
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
            .navigationTitle(role == .roomServer ? "Join Room" : "Admin Access")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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

            Toggle("Remember Password", isOn: $rememberPassword)
        } header: {
            Text("Authentication")
        } footer: {
            Text("Max \(maxPasswordLength) characters")
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
            .disabled(isAuthenticating || (role == .repeater && password.isEmpty))
        }
    }

    // MARK: - Authentication

    private func authenticate() {
        // Clear any previous error
        errorMessage = nil

        // Validate password length on submit
        guard password.count <= maxPasswordLength else {
            errorMessage = "Password must be \(maxPasswordLength) characters or less"
            return
        }

        isAuthenticating = true

        Task {
            do {
                guard let device = appState.connectedDevice else {
                    throw RemoteNodeError.notConnected
                }

                // Determine path length from contact for timeout calculation
                let pathLength = UInt8(max(0, contact.outPathLength))

                let session: RemoteNodeSessionDTO
                if role == .roomServer {
                    session = try await appState.roomServerService.joinRoom(
                        deviceID: device.id,
                        contact: contact,
                        password: password,
                        rememberPassword: rememberPassword,
                        pathLength: pathLength
                    )
                } else {
                    session = try await appState.repeaterAdminService.connectAsAdmin(
                        deviceID: device.id,
                        contact: contact,
                        password: password,
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
