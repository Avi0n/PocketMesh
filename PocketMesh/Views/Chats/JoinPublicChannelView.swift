import SwiftUI
import PocketMeshServices

/// View for re-adding the public channel on slot 0
struct JoinPublicChannelView: View {
    @Environment(AppState.self) private var appState

    let onComplete: (ChannelDTO?) -> Void

    @State private var isJoining = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "globe")
                            .font(.system(size: 60))
                            .foregroundStyle(.green)

                        Text("Public Channel")
                            .font(.title2)
                            .bold()

                        Text("The public channel is an open broadcast channel on slot 0. All devices on the mesh network can send and receive messages on this channel.")
                            .font(.subheadline)
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
                        await joinPublicChannel()
                    }
                } label: {
                    HStack {
                        Spacer()
                        if isJoining {
                            ProgressView()
                        } else {
                            Text("Add Public Channel")
                        }
                        Spacer()
                    }
                }
                .disabled(isJoining)
            }
        }
        .navigationTitle("Join Public Channel")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func joinPublicChannel() async {
        guard let deviceID = appState.connectedDevice?.id else {
            errorMessage = "No device connected"
            return
        }

        isJoining = true
        errorMessage = nil

        do {
            guard let channelService = appState.services?.channelService else {
                errorMessage = "Services not available"
                return
            }
            try await channelService.setupPublicChannel(deviceID: deviceID)

            // Fetch the public channel (slot 0) to return it
            var publicChannel: ChannelDTO?
            if let channels = try? await appState.services?.dataStore.fetchChannels(deviceID: deviceID) {
                publicChannel = channels.first { $0.index == 0 }
            }
            onComplete(publicChannel)
        } catch {
            errorMessage = error.localizedDescription
        }

        isJoining = false
    }
}

#Preview {
    NavigationStack {
        JoinPublicChannelView(onComplete: { _ in })
    }
    .environment(AppState())
}
