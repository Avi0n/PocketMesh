import SwiftUI
import PocketMeshServices
import CoreImage.CIFilterBuiltins

/// Sheet displaying channel info with sharing and deletion options
struct ChannelInfoSheet: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.chatViewModel) private var viewModel

    let channel: ChannelDTO
    let onClearMessages: () -> Void
    let onDelete: () -> Void

    @State private var notificationLevel: NotificationLevel
    @State private var isFavorite: Bool
    @State private var isDeleting = false
    @State private var isClearingMessages = false
    @State private var showingDeleteConfirmation = false
    @State private var showingClearMessagesConfirmation = false
    @State private var errorMessage: String?
    @State private var copyHapticTrigger = 0
    @State private var notificationTask: Task<Void, Never>?
    @State private var favoriteTask: Task<Void, Never>?

    init(channel: ChannelDTO, onClearMessages: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.channel = channel
        self.onClearMessages = onClearMessages
        self.onDelete = onDelete
        self._notificationLevel = State(initialValue: channel.notificationLevel)
        self._isFavorite = State(initialValue: channel.isFavorite)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Channel Header Section
                channelHeaderSection

                // Quick Actions Section
                ConversationQuickActionsSection(
                    notificationLevel: $notificationLevel,
                    isFavorite: $isFavorite,
                    availableLevels: NotificationLevel.channelLevels
                )
                .onChange(of: notificationLevel) { _, newValue in
                    notificationTask?.cancel()
                    notificationTask = Task {
                        await viewModel?.setNotificationLevel(.channel(channel), level: newValue)
                    }
                }
                .onChange(of: isFavorite) { _, newValue in
                    favoriteTask?.cancel()
                    favoriteTask = Task {
                        await viewModel?.setFavorite(.channel(channel), isFavorite: newValue)
                    }
                }
                .onDisappear {
                    notificationTask?.cancel()
                    favoriteTask?.cancel()
                }

                // QR Code Section (only for private channels with secrets)
                if channel.hasSecret && !channel.isPublicChannel {
                    qrCodeSection
                }

                // Secret Key Section (only for private channels)
                if channel.hasSecret && !channel.isPublicChannel {
                    secretKeySection
                }

                // Error Section
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                // Actions Section
                actionsSection
            }
            .navigationTitle(L10n.Chats.Chats.ChannelInfo.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.Chats.Chats.Common.done) {
                        dismiss()
                    }
                }
            }
        }
        .confirmationDialog(
            L10n.Chats.Chats.ChannelInfo.ClearMessagesConfirm.title,
            isPresented: $showingClearMessagesConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.Chats.Chats.ChannelInfo.clearMessagesButton, role: .destructive) {
                Task {
                    await clearMessages()
                }
            }
            Button(L10n.Chats.Chats.Common.cancel, role: .cancel) {}
        } message: {
            Text(L10n.Chats.Chats.ChannelInfo.ClearMessagesConfirm.message)
        }
        .confirmationDialog(
            L10n.Chats.Chats.ChannelInfo.DeleteConfirm.title,
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(L10n.Chats.Chats.ChannelInfo.deleteButton, role: .destructive) {
                Task {
                    await deleteChannel()
                }
            }
            Button(L10n.Chats.Chats.Common.cancel, role: .cancel) {}
        } message: {
            Text(L10n.Chats.Chats.ChannelInfo.DeleteConfirm.message)
        }
        .sensoryFeedback(.success, trigger: copyHapticTrigger)
    }

    // MARK: - Channel Header Section

    private var channelHeaderSection: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 12) {
                    ChannelAvatar(channel: channel, size: 80)

                    Text(channel.name.isEmpty ? L10n.Chats.Chats.Channel.defaultName(Int(channel.index)) : channel.name)
                        .font(.title2)
                        .bold()

                    Text(channelTypeLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .listRowBackground(Color.clear)
        }
    }

    private var channelTypeLabel: String {
        if channel.isPublicChannel {
            return L10n.Chats.Chats.ChannelInfo.ChannelType.`public`
        } else if channel.name.hasPrefix("#") {
            return L10n.Chats.Chats.ChannelInfo.ChannelType.hashtag
        } else {
            return L10n.Chats.Chats.ChannelInfo.ChannelType.`private`
        }
    }

    // MARK: - QR Code Section

    private var qrCodeSection: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 12) {
                    if let qrImage = generateQRCode() {
                        Image(uiImage: qrImage)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 180, height: 180)
                    }

                    Text(L10n.Chats.Chats.ChannelInfo.scanToJoin)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        } header: {
            Text(L10n.Chats.Chats.ChannelInfo.shareChannel)
        }
    }

    // MARK: - Secret Key Section

    private var secretKeySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.Chats.Chats.ChannelInfo.secretKey)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text(channel.secret.hexString())
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)

                    Spacer()

                    Button(L10n.Chats.Chats.ChannelInfo.copy, systemImage: "doc.on.doc") {
                        copyHapticTrigger += 1
                        UIPasteboard.general.string = channel.secret.hexString()
                    }
                    .labelStyle(.iconOnly)
                }
            }
        } header: {
            Text(L10n.Chats.Chats.ChannelInfo.manualSharing)
        } footer: {
            Text(L10n.Chats.Chats.ChannelInfo.manualSharingFooter)
        }
    }

    // MARK: - Actions Section

    private var isActionInProgress: Bool {
        isDeleting || isClearingMessages
    }

    private var actionsSection: some View {
        Section {
            Button {
                showingClearMessagesConfirmation = true
            } label: {
                HStack {
                    Spacer()
                    if isClearingMessages {
                        ProgressView()
                    } else {
                        Label(L10n.Chats.Chats.ChannelInfo.clearMessagesButton, systemImage: "xmark.circle")
                    }
                    Spacer()
                }
            }
            .disabled(isActionInProgress)
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }

            Button(role: .destructive) {
                showingDeleteConfirmation = true
            } label: {
                HStack {
                    Spacer()
                    if isDeleting {
                        ProgressView()
                    } else {
                        Label(L10n.Chats.Chats.ChannelInfo.deleteButton, systemImage: "trash")
                    }
                    Spacer()
                }
            }
            .disabled(isActionInProgress)
        } footer: {
            Text(L10n.Chats.Chats.ChannelInfo.deleteFooter)
        }
    }

    // MARK: - Private Methods

    private func clearNotificationsForChannel(deviceID: UUID) async {
        await appState.services?.notificationService.removeDeliveredNotifications(
            forChannelIndex: channel.index,
            deviceID: deviceID
        )
        await appState.services?.notificationService.updateBadgeCount()
    }

    private func generateQRCode() -> UIImage? {
        // Format: meshcore://channel/add?name=<name>&secret=<hex>
        let urlString = "meshcore://channel/add?name=\(channel.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&secret=\(channel.secret.hexString())"

        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(urlString.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage else { return nil }

        // Scale up for better quality
        let scale = 10.0
        let scaledImage = outputImage.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        guard let cgImage = context.createCGImage(scaledImage, from: scaledImage.extent) else { return nil }

        return UIImage(cgImage: cgImage)
    }

    private func deleteChannel() async {
        guard let deviceID = appState.connectedDevice?.id else {
            errorMessage = L10n.Chats.Chats.Error.noDeviceConnected
            return
        }

        guard let channelService = appState.services?.channelService else {
            errorMessage = L10n.Chats.Chats.Error.servicesUnavailable
            return
        }

        isDeleting = true
        errorMessage = nil

        do {
            // Clear channel on device (sends empty name + zero secret via BLE)
            // and deletes from local database
            try await channelService.clearChannel(
                deviceID: deviceID,
                index: channel.index
            )

            await clearNotificationsForChannel(deviceID: deviceID)

            dismiss()
            onDelete()
        } catch {
            errorMessage = error.localizedDescription
            isDeleting = false
        }
    }

    private func clearMessages() async {
        guard let deviceID = appState.connectedDevice?.id else {
            errorMessage = L10n.Chats.Chats.Error.noDeviceConnected
            return
        }

        guard let channelService = appState.services?.channelService else {
            errorMessage = L10n.Chats.Chats.Error.servicesUnavailable
            return
        }

        isClearingMessages = true
        errorMessage = nil

        do {
            try await channelService.clearChannelMessages(
                deviceID: deviceID,
                channelIndex: channel.index
            )

            await clearNotificationsForChannel(deviceID: deviceID)

            onClearMessages()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isClearingMessages = false
        }
    }
}

#Preview {
    ChannelInfoSheet(
        channel: ChannelDTO(from: Channel(
            deviceID: UUID(),
            index: 1,
            name: "General",
            secret: Data(repeating: 0xAB, count: 16)
        )),
        onClearMessages: {},
        onDelete: {}
    )
    .environment(\.appState, AppState())
}
