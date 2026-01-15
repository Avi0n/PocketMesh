import SwiftUI
import PocketMeshServices

/// View for joining a hashtag channel (public, name-based)
struct JoinHashtagChannelView: View {
    @Environment(AppState.self) private var appState

    let availableSlots: [UInt8]
    let onComplete: (ChannelDTO?) -> Void

    @State private var channelName = ""
    @State private var selectedSlot: UInt8
    @State private var isJoining = false
    @State private var errorMessage: String?

    init(availableSlots: [UInt8], onComplete: @escaping (ChannelDTO?) -> Void) {
        self.availableSlots = availableSlots
        self.onComplete = onComplete
        self._selectedSlot = State(initialValue: availableSlots.first ?? 1)
    }

    private var isValidName: Bool {
        HashtagUtilities.isValidHashtagName(channelName)
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("#")
                        .font(.title2)
                        .foregroundStyle(.secondary)

                    TextField("channel-name", text: $channelName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: channelName) { _, newValue in
                            channelName = HashtagUtilities.sanitizeHashtagNameInput(newValue)
                        }
                }
            } header: {
                Text("Hashtag Channel")
            } footer: {
                Text("Hashtag channels are public. Anyone can join by entering the same name. Only lowercase letters, numbers, and hyphens are allowed.")
            }

            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "number")
                            .font(.system(size: 40))
                            .foregroundStyle(.cyan)

                        if !channelName.isEmpty {
                            Text("#\(channelName)")
                                .font(.headline)
                        }

                        Text("The channel name is used to generate the encryption key. Anyone with the same name can read messages.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    Spacer()
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
                            Text("Join #\(channelName)")
                        }
                        Spacer()
                    }
                }
                .disabled(!isValidName || isJoining)
            }
        }
        .navigationTitle("Join Hashtag Channel")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func joinChannel() async {
        guard let deviceID = appState.connectedDevice?.id else {
            errorMessage = "No device connected"
            return
        }

        guard let channelService = appState.services?.channelService else {
            errorMessage = "Services not available"
            return
        }

        isJoining = true
        errorMessage = nil

        do {
            // For hashtag channels, hash the full name including "#" prefix
            // to match meshcore spec: sha256("#channelname")[0:16]
            try await channelService.setChannel(
                deviceID: deviceID,
                index: selectedSlot,
                name: "#\(channelName)",
                passphrase: "#\(channelName)"
            )

            // Fetch the joined channel to return it
            var joinedChannel: ChannelDTO?
            if let channels = try? await appState.services?.dataStore.fetchChannels(deviceID: deviceID) {
                joinedChannel = channels.first { $0.index == selectedSlot }
            }
            onComplete(joinedChannel)
        } catch {
            errorMessage = error.localizedDescription
        }

        isJoining = false
    }
}

#Preview {
    NavigationStack {
        JoinHashtagChannelView(availableSlots: [1, 2, 3], onComplete: { _ in })
    }
    .environment(AppState())
}
