// PocketMesh/Views/Chats/Components/MessagePathSheet.swift
import SwiftUI
import PocketMeshServices
import OSLog

/// Sheet displaying the path an incoming message took through the mesh.
struct MessagePathSheet: View {
    let message: MessageDTO

    @Environment(\.appState) private var appState

    @State private var contacts: [ContactDTO] = []
    @State private var isLoading = true
    @State private var copyHapticTrigger = 0

    private let logger = Logger(subsystem: "PocketMesh", category: "MessagePathSheet")

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                } else if !hasPathData {
                    Section {
                        ContentUnavailableView(
                            L10n.Chats.Chats.Path.Unavailable.title,
                            systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                            description: Text(L10n.Chats.Chats.Path.Unavailable.description)
                        )
                    }
                } else {
                    Section {
                        // Sender row
                        PathHopRowView(
                            hopType: .sender,
                            nodeName: senderName,
                            nodeID: senderNodeID,
                            snr: nil
                        )

                        // Intermediate hops
                        ForEach(Array(pathBytes.enumerated()), id: \.offset) { index, byte in
                            PathHopRowView(
                                hopType: .intermediate(index + 1),
                                nodeName: contactName(for: byte),
                                nodeID: String(format: "%02X", byte),
                                snr: nil
                            )
                        }

                        // Receiver row (You)
                        PathHopRowView(
                            hopType: .receiver,
                            nodeName: receiverName,
                            nodeID: nil,
                            snr: message.snr
                        )
                    }

                    // Only show raw path section if there are intermediate hops
                    if !pathBytes.isEmpty {
                        Section {
                            HStack {
                                Text(message.pathString)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Button(L10n.Chats.Chats.Path.copyButton, systemImage: "doc.on.doc") {
                                    copyHapticTrigger += 1
                                    UIPasteboard.general.string = message.pathStringForClipboard
                                }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .accessibilityLabel(L10n.Chats.Chats.Path.copyAccessibility)
                                .accessibilityHint(L10n.Chats.Chats.Path.copyHint)
                            }
                        } header: {
                            Text(L10n.Chats.Chats.Path.Section.header)
                        }
                    }
                }
            }
            .sensoryFeedback(.success, trigger: copyHapticTrigger)
            .navigationTitle(L10n.Chats.Chats.Path.title)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadContacts()
            }
        }
    }

    private var pathBytes: [UInt8] {
        guard let pathNodes = message.pathNodes else { return [] }
        return Array(pathNodes)
    }

    /// Whether we have enough data to display the path (pathNodes must exist)
    private var hasPathData: Bool {
        message.pathNodes != nil
    }

    /// Sender display name: node name for channels, contact lookup for DMs
    private var senderName: String {
        // For channel messages, use senderNodeName if available
        if message.isChannelMessage, let nodeName = message.senderNodeName {
            return nodeName
        }

        // For direct messages, look up contact by senderKeyPrefix
        if let keyPrefix = message.senderKeyPrefix,
           let firstByte = keyPrefix.first,
           let contact = contacts.first(where: { $0.publicKey.first == firstByte }) {
            return contact.displayName
        }

        return L10n.Chats.Chats.Path.Hop.unknown
    }

    /// Sender node ID (first byte of key prefix as hex)
    private var senderNodeID: String? {
        guard let keyPrefix = message.senderKeyPrefix, let firstByte = keyPrefix.first else {
            return nil
        }
        return String(format: "%02X", firstByte)
    }

    /// Receiver display name: device node name or "You"
    private var receiverName: String {
        appState.connectedDevice?.nodeName ?? L10n.Chats.Chats.Path.Receiver.you
    }

    /// Look up contact name by node ID byte
    private func contactName(for byte: UInt8) -> String {
        if let contact = contacts.first(where: { $0.publicKey.first == byte }) {
            return contact.displayName
        }
        return L10n.Chats.Chats.Path.Hop.unknown
    }

    private func loadContacts() async {
        guard let services = appState.services else {
            isLoading = false
            return
        }

        do {
            contacts = try await services.dataStore.fetchContacts(deviceID: message.deviceID)
        } catch {
            logger.error("Failed to load contacts: \(error.localizedDescription)")
        }

        isLoading = false
    }
}

#Preview("Channel With Hops") {
    MessagePathSheet(
        message: MessageDTO(
            id: UUID(),
            deviceID: UUID(),
            contactID: nil,
            channelIndex: 0,
            text: "Test message",
            timestamp: UInt32(Date().timeIntervalSince1970),
            createdAt: Date(),
            direction: .incoming,
            status: .delivered,
            textType: .plain,
            ackCode: nil,
            pathLength: 3,
            snr: 6.2,
            pathNodes: Data([0x7F, 0x42]),
            senderKeyPrefix: Data([0xA3, 0x00, 0x00, 0x00, 0x00, 0x00]),
            senderNodeName: "AlphaNode",
            isRead: true,
            replyToID: nil,
            roundTripTime: nil,
            heardRepeats: 0,
            retryAttempt: 0,
            maxRetryAttempts: 0
        )
    )
    .environment(AppState())
}

#Preview("Direct Transmission") {
    MessagePathSheet(
        message: MessageDTO(
            id: UUID(),
            deviceID: UUID(),
            contactID: nil,
            channelIndex: 0,
            text: "Test message",
            timestamp: UInt32(Date().timeIntervalSince1970),
            createdAt: Date(),
            direction: .incoming,
            status: .delivered,
            textType: .plain,
            ackCode: nil,
            pathLength: 0,
            snr: 8.5,
            pathNodes: Data(),
            senderKeyPrefix: Data([0xB2, 0x00, 0x00, 0x00, 0x00, 0x00]),
            senderNodeName: "BravoNode",
            isRead: true,
            replyToID: nil,
            roundTripTime: nil,
            heardRepeats: 0,
            retryAttempt: 0,
            maxRetryAttempts: 0
        )
    )
    .environment(AppState())
}

#Preview("No Path Data") {
    MessagePathSheet(
        message: MessageDTO(
            id: UUID(),
            deviceID: UUID(),
            contactID: nil,
            channelIndex: 0,
            text: "Test message",
            timestamp: UInt32(Date().timeIntervalSince1970),
            createdAt: Date(),
            direction: .incoming,
            status: .delivered,
            textType: .plain,
            ackCode: nil,
            pathLength: 0,
            snr: nil,
            pathNodes: nil,
            senderKeyPrefix: nil,
            senderNodeName: nil,
            isRead: true,
            replyToID: nil,
            roundTripTime: nil,
            heardRepeats: 0,
            retryAttempt: 0,
            maxRetryAttempts: 0
        )
    )
    .environment(AppState())
}
