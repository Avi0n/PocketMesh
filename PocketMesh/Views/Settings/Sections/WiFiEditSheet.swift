import SwiftUI
import PocketMeshServices

/// Sheet for editing WiFi connection parameters.
/// Pre-populates with current connection details and allows updating them.
struct WiFiEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appState) private var appState

    /// Optional initial values for editing a saved (non-connected) device
    var initialHost: String?
    var initialPort: UInt16?

    @State private var ipAddress = ""
    @State private var port = "5000"
    @State private var isReconnecting = false
    @State private var errorMessage: String?

    @FocusState private var focusedField: Field?

    enum Field {
        case ip, port
    }

    private var currentConnection: ConnectionMethod? {
        appState.connectedDevice?.connectionMethods.first { $0.isWiFi }
    }

    private var originalHost: String? {
        if let initialHost { return initialHost }
        if case .wifi(let host, _, _) = currentConnection { return host }
        return nil
    }

    private var originalPort: UInt16? {
        if let initialPort { return initialPort }
        if case .wifi(_, let port, _) = currentConnection { return port }
        return nil
    }

    private var isValidInput: Bool {
        isValidIPAddress(ipAddress) && isValidPort(port)
    }

    private var hasChanges: Bool {
        guard let host = originalHost, let currentPort = originalPort else { return true }
        return ipAddress != host || port != String(currentPort)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        TextField("IP Address", text: $ipAddress)
                            .keyboardType(.decimalPad)
                            .textContentType(.none)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .ip)

                        if !ipAddress.isEmpty {
                            Button {
                                ipAddress = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear IP address")
                        }
                    }

                    HStack {
                        TextField("Port", text: $port)
                            .keyboardType(.numberPad)
                            .focused($focusedField, equals: .port)

                        if !port.isEmpty {
                            Button {
                                port = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear port")
                        }
                    }
                } header: {
                    Text("Connection Details")
                } footer: {
                    Text("Changing these values will disconnect and reconnect to the new address.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        saveChanges()
                    } label: {
                        HStack {
                            Spacer()
                            if isReconnecting {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Reconnecting...")
                            } else {
                                Text("Save Changes")
                            }
                            Spacer()
                        }
                    }
                    .disabled(!isValidInput || !hasChanges || isReconnecting)
                }
            }
            .navigationTitle("Edit WiFi Connection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isReconnecting)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
            .interactiveDismissDisabled(isReconnecting)
            .onAppear {
                populateCurrentValues()
            }
        }
        .presentationSizing(.page)
    }

    private func populateCurrentValues() {
        if let host = originalHost {
            ipAddress = host
        }
        if let currentPort = originalPort {
            port = String(currentPort)
        }
    }

    private func saveChanges() {
        guard let portNumber = UInt16(port) else {
            errorMessage = "Invalid port number"
            return
        }

        isReconnecting = true
        errorMessage = nil

        Task {
            do {
                // Disconnect from current connection, then connect to new address
                await appState.disconnect()
                try await appState.connectViaWiFi(host: ipAddress, port: portNumber, forceFullSync: true)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isReconnecting = false
            }
        }
    }

    private func isValidIPAddress(_ ip: String) -> Bool {
        let parts = ip.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let num = Int(part) else { return false }
            return num >= 0 && num <= 255
        }
    }

    private func isValidPort(_ port: String) -> Bool {
        guard let num = UInt16(port) else { return false }
        return num > 0
    }
}

#Preview {
    WiFiEditSheet()
        .environment(\.appState, AppState())
}
