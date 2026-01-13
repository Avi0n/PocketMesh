import SwiftUI
import PocketMeshServices
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh", category: "JoinHashtagFromMessageView")

/// Sheet view for joining a hashtag channel tapped in a message
struct JoinHashtagFromMessageView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let channelName: String
    let onComplete: (ChannelDTO?) -> Void

    @State private var availableSlots: [UInt8] = []
    @State private var selectedSlot: UInt8 = 1
    @State private var isJoining = false
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var normalizedName: String {
        HashtagUtilities.normalizeHashtagName(channelName)
    }

    private var fullChannelName: String {
        "#\(normalizedName)"
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if availableSlots.isEmpty {
                    NoSlotsView(
                        fullChannelName: fullChannelName,
                        onDismiss: {
                            onComplete(nil)
                            dismiss()
                        }
                    )
                } else {
                    JoinFormView(
                        fullChannelName: fullChannelName,
                        availableSlots: availableSlots,
                        selectedSlot: $selectedSlot,
                        isJoining: $isJoining,
                        errorMessage: $errorMessage,
                        onJoin: { await joinChannel() }
                    )
                }
            }
            .navigationTitle("Join Channel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onComplete(nil)
                        dismiss()
                    }
                }
            }
            .task {
                await loadAvailableSlots()
            }
        }
    }

    private func loadAvailableSlots() async {
        guard let deviceID = appState.connectedDevice?.id else {
            isLoading = false
            return
        }

        do {
            let existingChannels = try await appState.services?.dataStore.fetchChannels(deviceID: deviceID) ?? []
            let usedSlots = Set(existingChannels.map(\.index))

            let maxChannels = appState.connectedDevice?.maxChannels ?? 0
            if maxChannels > 1 {
                availableSlots = (1..<maxChannels).filter { !usedSlots.contains($0) }
                if let first = availableSlots.first {
                    selectedSlot = first
                }
            }
        } catch {
            logger.error("Failed to load channel slots: \(error)")
        }

        isLoading = false
    }

    private func joinChannel() async {
        guard let deviceID = appState.connectedDevice?.id else {
            errorMessage = "No device connected."
            return
        }

        guard let channelService = appState.services?.channelService else {
            errorMessage = "Services not available."
            return
        }

        // Validate channel name
        guard HashtagUtilities.isValidHashtagName(normalizedName) else {
            errorMessage = "Invalid channel name format."
            return
        }

        isJoining = true
        errorMessage = nil

        do {
            // Create the channel - secret derived from SHA256("#channelname")
            // Always use lowercase normalized name for consistent secret derivation
            try await channelService.setChannel(
                deviceID: deviceID,
                index: selectedSlot,
                name: fullChannelName,
                passphrase: fullChannelName
            )

            // Fetch the newly created channel
            if let newChannel = try await appState.services?.dataStore.fetchChannel(deviceID: deviceID, index: selectedSlot) {
                onComplete(newChannel)
                dismiss()
            } else {
                errorMessage = "Channel created but could not be loaded."
            }
        } catch {
            logger.error("Failed to join channel: \(error)")
            errorMessage = error.localizedDescription
        }

        isJoining = false
    }
}

// MARK: - Private Views

private struct NoSlotsView: View {
    let fullChannelName: String
    let onDismiss: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No Slots Available", systemImage: "number.circle.fill")
        } description: {
            Text("All channel slots are full. Remove an existing channel to join \(fullChannelName).")
        } actions: {
            Button("OK") {
                onDismiss()
            }
        }
    }
}

private struct JoinFormView: View {
    let fullChannelName: String
    let availableSlots: [UInt8]
    @Binding var selectedSlot: UInt8
    @Binding var isJoining: Bool
    @Binding var errorMessage: String?
    let onJoin: () async -> Void

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(.cyan)
                                .frame(width: 60, height: 60)

                            Image(systemName: "number")
                                .font(.title)
                                .bold()
                                .foregroundStyle(.white)
                        }

                        Text(fullChannelName)
                            .font(.title2)
                            .bold()
                    }
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section {
                Picker("Channel Slot", selection: $selectedSlot) {
                    ForEach(availableSlots, id: \.self) { slot in
                        Text("Slot \(slot)").tag(slot)
                    }
                }
            } header: {
                Text("Settings")
            } footer: {
                Text("Hashtag channels are public. Anyone can join by entering the same name.")
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
                        await onJoin()
                    }
                } label: {
                    HStack {
                        Spacer()
                        if isJoining {
                            ProgressView()
                        } else {
                            Text("Join \(fullChannelName)")
                        }
                        Spacer()
                    }
                }
                .disabled(isJoining)
            }
        }
    }
}

#Preview {
    JoinHashtagFromMessageView(channelName: "#general") { _ in }
        .environment(AppState())
}
