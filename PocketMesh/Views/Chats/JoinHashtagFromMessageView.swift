import SwiftUI
import PocketMeshServices
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh", category: "JoinHashtagFromMessageView")

/// Sheet view for joining a hashtag channel tapped in a message
@MainActor
struct JoinHashtagFromMessageView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appState) private var appState

    let channelName: String
    let onComplete: (ChannelDTO?) -> Void

    @State private var availableSlots: [UInt8] = []
    @State private var isJoining = false
    @State private var isLoading = true
    @State private var isMissingDevice = false
    @State private var errorMessage: String?
    @State private var successTrigger = 0

    private var normalizedName: String {
        HashtagUtilities.normalizeHashtagName(channelName)
    }

    private var fullChannelName: String {
        "#\(normalizedName)"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isLoading {
                    loadingView
                } else if isMissingDevice {
                    missingDeviceView
                } else if availableSlots.isEmpty {
                    noSlotsView
                } else {
                    joinConfirmationView
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(L10n.Chats.Chats.JoinFromMessage.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Chats.Chats.Common.cancel) {
                        onComplete(nil)
                        dismiss()
                    }
                }
            }
            .task {
                await loadAvailableSlots()
            }
            .sensoryFeedback(.success, trigger: successTrigger)
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        ProgressView(L10n.Chats.Chats.JoinFromMessage.loading)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var missingDeviceView: some View {
        ContentUnavailableView {
            Label(L10n.Chats.Chats.JoinFromMessage.NoDevice.title, systemImage: "antenna.radiowaves.left.and.right.slash")
        } description: {
            Text(L10n.Chats.Chats.JoinFromMessage.NoDevice.description(fullChannelName))
        } actions: {
            Button(L10n.Chats.Chats.Common.ok) {
                onComplete(nil)
                dismiss()
            }
            .liquidGlassProminentButtonStyle()
        }
    }

    // MARK: - No Slots View

    private var noSlotsView: some View {
        ContentUnavailableView {
            Label(L10n.Chats.Chats.JoinFromMessage.NoSlots.title, systemImage: "number.circle.fill")
        } description: {
            Text(L10n.Chats.Chats.JoinFromMessage.NoSlots.description(fullChannelName))
        } actions: {
            Button(L10n.Chats.Chats.Common.ok) {
                onComplete(nil)
                dismiss()
            }
            .liquidGlassProminentButtonStyle()
        }
    }

    // MARK: - Join Confirmation View

    private var joinConfirmationView: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(.cyan)
                        .frame(width: 80, height: 80)

                    Image(systemName: "number")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white)
                }

                Text(fullChannelName)
                    .font(.title)
                    .bold()

                Text(L10n.Chats.Chats.JoinFromMessage.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            if let errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
            }

            Button {
                Task {
                    await joinChannel()
                }
            } label: {
                if isJoining {
                    ProgressView()
                } else {
                    Text(L10n.Chats.Chats.JoinFromMessage.joinButton(fullChannelName))
                }
            }
            .liquidGlassProminentButtonStyle()
            .disabled(isJoining)
            .padding(.horizontal, 48)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Private Methods

    private func loadAvailableSlots() async {
        guard let deviceID = appState.connectedDevice?.id else {
            isMissingDevice = true
            isLoading = false
            return
        }

        isMissingDevice = false

        do {
            let existingChannels = try await appState.services?.dataStore.fetchChannels(deviceID: deviceID) ?? []
            let usedSlots = Set(existingChannels.map(\.index))

            let maxChannels = appState.connectedDevice?.maxChannels ?? 0
            if maxChannels > 1 {
                availableSlots = (1..<maxChannels).filter { !usedSlots.contains($0) }
            }
        } catch {
            logger.error("Failed to load channel slots: \(error)")
        }

        isLoading = false
    }

    private func joinChannel() async {
        guard let deviceID = appState.connectedDevice?.id else {
            errorMessage = L10n.Chats.Chats.Error.noDeviceConnected
            return
        }

        guard let channelService = appState.services?.channelService else {
            errorMessage = L10n.Chats.Chats.Error.servicesUnavailable
            return
        }

        guard let selectedSlot = availableSlots.first else {
            errorMessage = L10n.Chats.Chats.JoinFromMessage.Error.noSlots
            return
        }

        guard HashtagUtilities.isValidHashtagName(normalizedName) else {
            errorMessage = L10n.Chats.Chats.JoinFromMessage.Error.invalidName
            return
        }

        isJoining = true
        errorMessage = nil

        do {
            try await channelService.setChannel(
                deviceID: deviceID,
                index: selectedSlot,
                name: fullChannelName,
                passphrase: fullChannelName
            )

            if let newChannel = try await appState.services?.dataStore.fetchChannel(deviceID: deviceID, index: selectedSlot) {
                successTrigger += 1
                onComplete(newChannel)
                dismiss()
            } else {
                errorMessage = L10n.Chats.Chats.JoinFromMessage.Error.loadFailed
            }
        } catch {
            logger.error("Failed to join channel: \(error)")
            errorMessage = error.localizedDescription
        }

        isJoining = false
    }
}

#Preview {
    JoinHashtagFromMessageView(channelName: "#general") { _ in }
        .environment(\.appState, AppState())
        .presentationDetents([.medium])
}
