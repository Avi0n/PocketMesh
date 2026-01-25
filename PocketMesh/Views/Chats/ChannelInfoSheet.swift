import SwiftUI
import PocketMeshServices
import CoreImage.CIFilterBuiltins

/// Sheet displaying channel info with sharing and deletion options
struct ChannelInfoSheet: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss

    let channel: ChannelDTO
    let onDelete: () -> Void

    @State private var isDeleting = false
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?
    @State private var copyHapticTrigger = 0

    var body: some View {
        NavigationStack {
            Form {
                // Channel Header Section
                channelHeaderSection

                // Channel Info Section
                channelInfoSection

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

                // Delete Section
                deleteSection
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

    // MARK: - Channel Info Section

    private var channelInfoSection: some View {
        Section {
            LabeledContent(L10n.Chats.Chats.ChannelInfo.slot, value: "\(channel.index)")

            if let lastMessage = channel.lastMessageDate {
                LabeledContent(L10n.Chats.Chats.ChannelInfo.lastMessage) {
                    Text(lastMessage, style: .relative)
                }
            }
        }
    }

    private var channelTypeLabel: String {
        if channel.isPublicChannel {
            return L10n.Chats.Chats.ChannelInfo.ChannelType.`public`
        } else if channel.name.hasPrefix("#") {
            return L10n.Chats.Chats.ChannelInfo.ChannelType.hashtag(Int(channel.index))
        } else {
            return L10n.Chats.Chats.ChannelInfo.ChannelType.`private`(Int(channel.index))
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

    // MARK: - Delete Section

    private var deleteSection: some View {
        Section {
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
            .disabled(isDeleting)
        } footer: {
            Text(L10n.Chats.Chats.ChannelInfo.deleteFooter)
        }
    }

    // MARK: - Private Methods

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

            // Dismiss sheet and trigger parent dismissal
            dismiss()
            onDelete()
        } catch {
            errorMessage = error.localizedDescription
            isDeleting = false
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
        onDelete: {}
    )
    .environment(\.appState, AppState())
}
