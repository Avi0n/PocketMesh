// PocketMesh/Views/Chats/Components/MessagePathSheet.swift
import SwiftUI
import PocketMeshServices
import OSLog

/// Sheet displaying the path an incoming message took through the mesh.
struct MessagePathSheet: View {
    let message: MessageDTO

    @Environment(AppState.self) private var appState

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
                } else if pathBytes.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "Path Unavailable",
                            systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                            description: Text(emptyStateDescription)
                        )
                    }
                } else {
                    Section {
                        ForEach(Array(pathBytes.enumerated()), id: \.offset) { index, byte in
                            PathHopRowView(
                                hopByte: byte,
                                hopIndex: index,
                                isLastHop: index == pathBytes.count - 1,
                                snr: index == pathBytes.count - 1 ? message.snr : nil,
                                contacts: contacts
                            )
                        }
                    }

                    Section {
                        HStack {
                            Text(message.pathString)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)

                            Spacer()

                            Button("Copy Path", systemImage: "doc.on.doc") {
                                copyHapticTrigger += 1
                                UIPasteboard.general.string = message.pathString
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Copy path to clipboard")
                            .accessibilityHint("Copies node IDs as hexadecimal values")
                        }
                    } header: {
                        Text("Path")
                    }
                }
            }
            .sensoryFeedback(.success, trigger: copyHapticTrigger)
            .navigationTitle("Message Path")
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

    private var emptyStateDescription: String {
        // Check pathNodes first (actual data), then fall back to pathLength for hint
        if message.pathNodes == nil {
            if message.pathLength == 0 || message.pathLength == 0xFF {
                return "This message was received directly"
            }
            return "Path data is not available for this message"
        }
        return ""
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

#Preview("With Path") {
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
            pathNodes: Data([0xA3, 0x7F, 0x42]),
            senderKeyPrefix: nil,
            senderNodeName: "TestNode",
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

#Preview("Direct Message") {
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
