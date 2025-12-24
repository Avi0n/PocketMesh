import SwiftUI
import PocketMeshServices

/// Sheet presenting channel creation and joining options
struct ChannelOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var selectedOption: ChannelOption?
    @State private var availableSlots: [UInt8] = []
    @State private var hasPublicChannel = false
    @State private var isLoading = true

    enum ChannelOption: Identifiable {
        case createPrivate
        case joinPrivate
        case joinPublic
        case joinHashtag
        case scanQR

        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading channels...")
                } else {
                    optionsList
                }
            }
            .navigationTitle("New Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                await loadChannelState()
            }
            .navigationDestination(item: $selectedOption) { option in
                switch option {
                case .createPrivate:
                    CreatePrivateChannelView(availableSlots: availableSlots, onComplete: { dismiss() })
                case .joinPrivate:
                    JoinPrivateChannelView(availableSlots: availableSlots, onComplete: { dismiss() })
                case .joinPublic:
                    JoinPublicChannelView(onComplete: { dismiss() })
                case .joinHashtag:
                    JoinHashtagChannelView(availableSlots: availableSlots, onComplete: { dismiss() })
                case .scanQR:
                    ScanChannelQRView(availableSlots: availableSlots, onComplete: { dismiss() })
                }
            }
        }
    }

    private var optionsList: some View {
        List {
            Section {
                // Create Private Channel
                Button {
                    selectedOption = .createPrivate
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Create a Private Channel")
                                .foregroundStyle(.primary)
                            Text("Generate a secret key and QR code to share")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.blue)
                    }
                }
                .disabled(availableSlots.isEmpty)

                // Join Private Channel
                Button {
                    selectedOption = .joinPrivate
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Join a Private Channel")
                                .foregroundStyle(.primary)
                            Text("Enter channel name and secret key")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "key.fill")
                            .foregroundStyle(.orange)
                    }
                }
                .disabled(availableSlots.isEmpty)

                // Scan QR Code
                Button {
                    selectedOption = .scanQR
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Scan a QR Code")
                                .foregroundStyle(.primary)
                            Text("Join a channel by scanning its QR code")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "qrcode.viewfinder")
                            .foregroundStyle(.purple)
                    }
                }
                .disabled(availableSlots.isEmpty)
            } header: {
                Text("Private Channels")
            }

            Section {
                // Join Public Channel
                Button {
                    selectedOption = .joinPublic
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Join the Public Channel")
                                .foregroundStyle(.primary)
                            Text("Re-add the default public broadcast channel")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "globe")
                            .foregroundStyle(.green)
                    }
                }
                .disabled(hasPublicChannel)

                // Join Hashtag Channel
                Button {
                    selectedOption = .joinHashtag
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Join a Hashtag Channel")
                                .foregroundStyle(.primary)
                            Text("Public channel anyone can join by name")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "number")
                            .foregroundStyle(.cyan)
                    }
                }
                .disabled(availableSlots.isEmpty)
            } header: {
                Text("Public Channels")
            } footer: {
                if availableSlots.isEmpty {
                    Text("All channel slots are in use. Delete an existing channel to add a new one.")
                } else if hasPublicChannel {
                    Text("The public channel is already configured on slot 0.")
                }
            }
        }
    }

    private func loadChannelState() async {
        guard let deviceID = appState.connectedDevice?.id else {
            isLoading = false
            return
        }

        do {
            let existingChannels = try await appState.services?.dataStore.fetchChannels(deviceID: deviceID) ?? []
            let usedSlots = Set(existingChannels.map(\.index))

            // Check if public channel exists
            hasPublicChannel = usedSlots.contains(0)

            // Slots 1 through (maxChannels-1) are available for user channels
            // Slot 0 is reserved for public channel
            let maxChannels = appState.connectedDevice?.maxChannels ?? 0
            if maxChannels > 1 {
                availableSlots = (1..<maxChannels).filter { !usedSlots.contains($0) }
            } else {
                availableSlots = []
            }
        } catch {
            // Handle error silently, show empty state
        }

        isLoading = false
    }
}

#Preview {
    ChannelOptionsSheet()
        .environment(AppState())
}
