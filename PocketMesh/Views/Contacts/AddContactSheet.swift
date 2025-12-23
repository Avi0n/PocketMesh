import SwiftUI
import PocketMeshServices
import os

/// Sheet for manually adding a contact or scanning a QR code
struct AddContactSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: ContactType = .chat
    @State private var contactName = ""
    @State private var publicKeyHex = ""
    @State private var showScanner = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private let logger = Logger(subsystem: "com.pocketmesh", category: "AddContactSheet")

    // MARK: - Validation

    private var normalizedPublicKeyHex: String {
        publicKeyHex.filter { $0.isHexDigit }.lowercased()
    }

    private var isValidPublicKey: Bool {
        normalizedPublicKeyHex.count == Constants.publicKeyHexLength
    }

    private var canAdd: Bool {
        !contactName.isEmpty && isValidPublicKey && !isSubmitting
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                ScannerSection(showScanner: $showScanner)

                TypePickerSection(selectedType: $selectedType)

                NameInputSection(contactName: $contactName)

                PublicKeyInputSection(
                    publicKeyHex: $publicKeyHex,
                    normalizedCount: normalizedPublicKeyHex.count,
                    isValid: isValidPublicKey
                )

                if let errorMessage {
                    ErrorSection(message: errorMessage)
                }
            }
            .navigationTitle("Add Contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            await handleAdd()
                        }
                    }
                    .disabled(!canAdd)
                }
            }
            .navigationDestination(isPresented: $showScanner) {
                ScanContactQRView { _, _ in
                    // Scanner handles import automatically
                    // Dismiss both sheets on success
                    showScanner = false
                    dismiss()
                }
            }
            .disabled(isSubmitting)
        }
    }

    // MARK: - Actions

    @MainActor
    private func handleAdd() async {
        guard let services = appState.services,
              let deviceID = appState.connectedDevice?.id else {
            logger.error("Services or device not available")
            errorMessage = "Not connected to device"
            return
        }

        guard let publicKeyData = Data(hexString: normalizedPublicKeyHex) else {
            logger.error("Failed to convert hex string to data: \(normalizedPublicKeyHex)")
            errorMessage = "Invalid public key format"
            return
        }

        guard publicKeyData.count == ProtocolLimits.publicKeySize else {
            logger.error("Public key is not \(ProtocolLimits.publicKeySize) bytes: \(publicKeyData.count)")
            errorMessage = "Public key must be \(ProtocolLimits.publicKeySize) bytes (\(Constants.publicKeyHexLength) hex characters)"
            return
        }

        isSubmitting = true
        errorMessage = nil

        do {
            let currentTimestamp = UInt32(Date().timeIntervalSince1970)

            let contactFrame = ContactFrame(
                publicKey: publicKeyData,
                type: selectedType,
                flags: 0,
                outPathLength: -1,  // Flood routing
                outPath: Data(),
                name: contactName,
                lastAdvertTimestamp: 0,  // Never advertised
                latitude: 0,
                longitude: 0,
                lastModified: currentTimestamp
            )

            logger.info("Adding contact: \(contactName) (\(publicKeyData.hex))")
            try await services.contactService.addOrUpdateContact(deviceID: deviceID, contact: contactFrame)
            logger.info("Contact added successfully")

            dismiss()
        } catch ContactServiceError.contactTableFull {
            logger.error("Contact table is full")
            errorMessage = "Contact table is full (max \(ProtocolLimits.maxContacts) contacts)"
            isSubmitting = false
        } catch {
            logger.error("Failed to add contact: \(error.localizedDescription)")
            errorMessage = "Failed to add contact: \(error.localizedDescription)"
            isSubmitting = false
        }
    }
}

// MARK: - Constants

private enum Constants {
    static let publicKeyHexLength = ProtocolLimits.publicKeySize * 2
}

// MARK: - Scanner Section

private struct ScannerSection: View {
    @Binding var showScanner: Bool

    var body: some View {
        Section {
            Button {
                showScanner = true
            } label: {
                Label("Scan QR Code", systemImage: "camera")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }
}

// MARK: - Type Picker Section

private struct TypePickerSection: View {
    @Binding var selectedType: ContactType

    var body: some View {
        Section {
            Picker("Type", selection: $selectedType) {
                Text("Chat").tag(ContactType.chat)
                Text("Repeater").tag(ContactType.repeater)
                Text("Room").tag(ContactType.room)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Type")
        }
    }
}

// MARK: - Name Input Section

private struct NameInputSection: View {
    @Binding var contactName: String

    var body: some View {
        Section {
            TextField("Contact Name", text: $contactName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
        } header: {
            Text("Name")
        }
    }
}

// MARK: - Public Key Input Section

private struct PublicKeyInputSection: View {
    @Binding var publicKeyHex: String
    let normalizedCount: Int
    let isValid: Bool

    var body: some View {
        Section {
            TextField("\(Constants.publicKeyHexLength) hex characters", text: $publicKeyHex)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.asciiCapable)
                .font(.system(.body, design: .monospaced))
                .onChange(of: publicKeyHex) { _, newValue in
                    // Filter to hex chars only and lowercase
                    let filtered = newValue.filter { $0.isHexDigit }.lowercased()
                    if filtered != newValue {
                        publicKeyHex = filtered
                    }
                }

            if !publicKeyHex.isEmpty {
                HStack {
                    if isValid {
                        Label("Valid", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("\(normalizedCount)/\(Constants.publicKeyHexLength) characters", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.caption)
            }
        } header: {
            Text("Public Key")
        } footer: {
            Text("Enter the \(Constants.publicKeyHexLength)-character hexadecimal public key of the contact")
        }
    }
}

// MARK: - Error Section

private struct ErrorSection: View {
    let message: String

    var body: some View {
        Section {
            Text(message)
                .foregroundStyle(.red)
                .font(.caption)
        }
    }
}

#Preview {
    AddContactSheet()
        .environment(AppState())
}
