import SwiftUI
import PocketMeshServices

/// View for joining a private channel by entering name and hex secret key
struct JoinPrivateChannelView: View {
    @Environment(AppState.self) private var appState

    let availableSlots: [UInt8]
    let onComplete: () -> Void

    @State private var channelName = ""
    @State private var secretKeyHex = ""
    @State private var selectedSlot: UInt8
    @State private var isJoining = false
    @State private var errorMessage: String?

    init(availableSlots: [UInt8], onComplete: @escaping () -> Void) {
        self.availableSlots = availableSlots
        self.onComplete = onComplete
        self._selectedSlot = State(initialValue: availableSlots.first ?? 1)
    }

    private var isValidSecret: Bool {
        let cleaned = secretKeyHex.replacing(" ", with: "").uppercased()
        return cleaned.count == 32 && cleaned.allSatisfy { $0.isHexDigit }
    }

    var body: some View {
        Form {
            Section {
                TextField("Channel Name", text: $channelName)
                    .textContentType(.name)

                TextField("Secret Key (32 hex characters)", text: $secretKeyHex)
                    .textContentType(.password)
                    .font(.system(.body, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .onChange(of: secretKeyHex) { _, newValue in
                        // Clean and format as user types
                        secretKeyHex = newValue.uppercased().filter { $0.isHexDigit }
                    }
            } header: {
                Text("Channel Details")
            } footer: {
                if !secretKeyHex.isEmpty && !isValidSecret {
                    Text("Secret key must be exactly 32 hexadecimal characters (0-9, A-F)")
                        .foregroundStyle(.red)
                } else {
                    Text("Enter the channel name and secret key shared by the channel creator.")
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task {
                        await joinChannel()
                    }
                } label: {
                    HStack {
                        Spacer()
                        if isJoining {
                            ProgressView()
                        } else {
                            Text("Join Channel")
                        }
                        Spacer()
                    }
                }
                .disabled(channelName.isEmpty || !isValidSecret || isJoining)
            }
        }
        .navigationTitle("Join Private Channel")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func joinChannel() async {
        guard let deviceID = appState.connectedDevice?.id else {
            errorMessage = "No device connected"
            return
        }

        guard let secret = Data(hexString: secretKeyHex) else {
            errorMessage = "Invalid secret key format"
            return
        }

        isJoining = true
        errorMessage = nil

        do {
            guard let channelService = appState.services?.channelService else {
                errorMessage = "Services not available"
                return
            }
            try await channelService.setChannelWithSecret(
                deviceID: deviceID,
                index: selectedSlot,
                name: channelName,
                secret: secret
            )

            onComplete()
        } catch {
            errorMessage = error.localizedDescription
        }

        isJoining = false
    }
}

#Preview {
    NavigationStack {
        JoinPrivateChannelView(availableSlots: [1, 2, 3], onComplete: {})
    }
    .environment(AppState())
}
