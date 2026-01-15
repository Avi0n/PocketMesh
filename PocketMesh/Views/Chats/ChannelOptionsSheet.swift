import SwiftUI
import PocketMeshServices

/// Sheet presenting channel creation and joining options
struct ChannelOptionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let onChannelCreated: ((ChannelDTO) -> Void)?

    @State private var selectedOption: ChannelOption?
    @State private var availableSlots: [UInt8] = []
    @State private var hasPublicChannel = false
    @State private var isLoading = true

    init(onChannelCreated: ((ChannelDTO) -> Void)? = nil) {
        self.onChannelCreated = onChannelCreated
    }

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
                    CreatePrivateChannelView(availableSlots: availableSlots) { channel in
                        if let channel { onChannelCreated?(channel) }
                        dismiss()
                    }
                case .joinPrivate:
                    JoinPrivateChannelView(availableSlots: availableSlots) { channel in
                        if let channel { onChannelCreated?(channel) }
                        dismiss()
                    }
                case .joinPublic:
                    JoinPublicChannelView { channel in
                        if let channel { onChannelCreated?(channel) }
                        dismiss()
                    }
                case .joinHashtag:
                    JoinHashtagChannelView(availableSlots: availableSlots) { channel in
                        if let channel { onChannelCreated?(channel) }
                        dismiss()
                    }
                case .scanQR:
                    ScanChannelQRView(availableSlots: availableSlots) { channel in
                        if let channel { onChannelCreated?(channel) }
                        dismiss()
                    }
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
                    ChannelOptionRow(
                        title: "Create a Private Channel",
                        description: "Generate a secret key and QR code to share",
                        icon: "lock.fill",
                        iconColor: .blue
                    )
                }
                .buttonStyle(.plain)
                .disabled(availableSlots.isEmpty)

                // Join Private Channel
                Button {
                    selectedOption = .joinPrivate
                } label: {
                    ChannelOptionRow(
                        title: "Join a Private Channel",
                        description: "Enter channel name and secret key",
                        icon: "key.fill",
                        iconColor: .orange
                    )
                }
                .buttonStyle(.plain)
                .disabled(availableSlots.isEmpty)

                // Scan QR Code
                Button {
                    selectedOption = .scanQR
                } label: {
                    ChannelOptionRow(
                        title: "Scan a QR Code",
                        description: "Join a channel by scanning its QR code",
                        icon: "qrcode.viewfinder",
                        iconColor: .purple
                    )
                }
                .buttonStyle(.plain)
                .disabled(availableSlots.isEmpty)
            } header: {
                Text("Private Channels")
            }

            Section {
                // Join Public Channel
                Button {
                    selectedOption = .joinPublic
                } label: {
                    ChannelOptionRow(
                        title: "Join the Public Channel",
                        description: "The default public channel",
                        icon: "globe",
                        iconColor: .green
                    )
                }
                .buttonStyle(.plain)
                .disabled(hasPublicChannel)

                // Join Hashtag Channel
                Button {
                    selectedOption = .joinHashtag
                } label: {
                    ChannelOptionRow(
                        title: "Join a Hashtag Channel",
                        description: "Public channel anyone can join by name",
                        icon: "number",
                        iconColor: .cyan
                    )
                }
                .buttonStyle(.plain)
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

/// Reusable row for channel option buttons with proper disabled state styling
struct ChannelOptionRow: View {
    @Environment(\.isEnabled) private var isEnabled

    let title: String
    let description: String
    let icon: String
    let iconColor: Color

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(isEnabled ? iconColor : .secondary)
        }
    }
}

#Preview {
    ChannelOptionsSheet()
        .environment(AppState())
}
