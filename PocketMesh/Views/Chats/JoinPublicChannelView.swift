import SwiftUI
import PocketMeshKit

/// View for re-adding the public channel on slot 0
struct JoinPublicChannelView: View {
    @Environment(AppState.self) private var appState

    let onComplete: () -> Void

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
            try await appState.channelService.setupPublicChannel(deviceID: deviceID)
            onComplete()
        } catch {
            errorMessage = error.localizedDescription
        }

        isJoining = false
    }
}

#Preview {
    NavigationStack {
        JoinPublicChannelView(onComplete: {})
    }
    .environment(AppState())
}
