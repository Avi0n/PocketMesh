import SwiftUI
import PocketMeshServices

/// Sheet for entering WiFi connection details (IP address and port).
struct WiFiConnectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var ipAddress = ""
    @State private var port = "5000"
    @State private var isConnecting = false
    @State private var errorMessage: String?

    @FocusState private var focusedField: Field?

    enum Field {
        case ip, port
    }

    private var isValidInput: Bool {
        isValidIPAddress(ipAddress) && isValidPort(port)
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
                    Text("Enter your MeshCore device's local network address. The default port is 5000.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        connect()
                    } label: {
                        HStack {
                            Spacer()
                            if isConnecting {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Connecting...")
                            } else {
                                Text("Connect")
                            }
                            Spacer()
                        }
                    }
                    .disabled(!isValidInput || isConnecting)
                }
            }
            .navigationTitle("Connect via WiFi")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isConnecting)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedField = nil
                    }
                }
            }
            .interactiveDismissDisabled(isConnecting)
            .onAppear {
                focusedField = .ip
            }
        }
    }

    private func connect() {
        guard let portNumber = UInt16(port) else {
            errorMessage = "Invalid port number"
            return
        }

        isConnecting = true
        errorMessage = nil

        Task {
            do {
                // TODO: Uncomment when AppState.connectViaWiFi is implemented (Task 10)
                // try await appState.connectViaWiFi(host: ipAddress, port: portNumber)
                _ = (ipAddress, portNumber) // Suppress unused variable warning
                throw NSError(domain: "WiFi", code: 0, userInfo: [NSLocalizedDescriptionKey: "WiFi connection not yet implemented"])
            } catch {
                errorMessage = error.localizedDescription
            }
            isConnecting = false
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
    WiFiConnectionSheet()
        .environment(AppState())
}
