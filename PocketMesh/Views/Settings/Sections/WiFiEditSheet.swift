import SwiftUI
import PocketMeshServices

/// Sheet for editing WiFi connection parameters.
/// Pre-populates with current connection details and allows updating them.
struct WiFiEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

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

    private var isValidInput: Bool {
        isValidIPAddress(ipAddress) && isValidPort(port)
    }

    private var hasChanges: Bool {
        guard case .wifi(let host, let currentPort, _) = currentConnection else { return true }
        return ipAddress != host || port != String(currentPort)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("IP Address", text: $ipAddress)
                        .keyboardType(.decimalPad)
                        .textContentType(.none)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .ip)

                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .port)
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
    }

    private func populateCurrentValues() {
        if case .wifi(let host, let currentPort, _) = currentConnection {
            ipAddress = host
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
                // TODO: Implement reconnect when AppState.reconnectViaWiFi is available (Task 10)
                // This should: disconnect, then connect to the new host:port
                _ = (ipAddress, portNumber) // Suppress unused variable warning
                throw NSError(domain: "WiFi", code: 0, userInfo: [NSLocalizedDescriptionKey: "WiFi reconnection not yet implemented"])
            } catch {
                errorMessage = error.localizedDescription
            }
            isReconnecting = false
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
        .environment(AppState())
}
