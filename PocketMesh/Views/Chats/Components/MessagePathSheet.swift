// PocketMesh/Views/Chats/Components/MessagePathSheet.swift
import SwiftUI
import PocketMeshServices

/// Sheet displaying the path an incoming message took through the mesh.
struct MessagePathSheet: View {
    let message: MessageDTO

    @Environment(\.appState) private var appState

    @State private var viewModel = MessagePathViewModel()
    @State private var copyHapticTrigger = 0

    var body: some View {
        NavigationStack {
            List {
                if viewModel.isLoading {
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
                            nodeName: viewModel.senderName(for: message),
                            nodeID: viewModel.senderNodeID(for: message),
                            snr: nil
                        )

                        // Intermediate hops
                        ForEach(Array(pathBytes.enumerated()), id: \.offset) { index, byte in
                            PathHopRowView(
                                hopType: .intermediate(index + 1),
                                nodeName: viewModel.repeaterName(
                                    for: byte,
                                    userLocation: appState.locationService.currentLocation
                                ),
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
                await viewModel.loadContacts(services: appState.services, deviceID: message.deviceID)
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

    /// Receiver display name: device node name or "You"
    private var receiverName: String {
        appState.connectedDevice?.nodeName ?? L10n.Chats.Chats.Path.Receiver.you
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
