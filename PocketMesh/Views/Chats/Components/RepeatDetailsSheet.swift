// PocketMesh/Views/Chats/Components/RepeatDetailsSheet.swift
import SwiftUI
import PocketMeshServices
import OSLog

/// Sheet displaying detailed information about heard repeats for a message.
struct RepeatDetailsSheet: View {
    let message: MessageDTO

    @Environment(AppState.self) private var appState

    @State private var repeats: [MessageRepeatDTO] = []
    @State private var contacts: [ContactDTO] = []
    @State private var isLoading = true

    private let logger = Logger(subsystem: "PocketMesh", category: "RepeatDetailsSheet")

    var body: some View {
        NavigationStack {
            List {
                // Loading, repeats list, or empty state
                if isLoading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                } else if repeats.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No repeats yet",
                            systemImage: "arrow.triangle.branch",
                            description: Text("Repeats will appear here as your message propagates through the mesh")
                        )
                    }
                } else {
                    Section {
                        ForEach(repeats) { repeatEntry in
                            RepeatRowView(
                                repeatEntry: repeatEntry,
                                contacts: contacts
                            )
                        }
                    }
                }
            }
            .navigationTitle("Repeat Details")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadRepeats()
            }
        }
    }

    private func loadRepeats() async {
        logger.debug("Loading repeats for message \(message.id), heardRepeats=\(message.heardRepeats)")

        guard let services = appState.services else {
            logger.warning("services not available")
            isLoading = false
            return
        }

        // Load all contacts (not just conversations) to match repeater public keys
        do {
            contacts = try await services.dataStore.fetchContacts(deviceID: message.deviceID)
        } catch {
            logger.error("Failed to load contacts: \(error.localizedDescription)")
        }

        let fetched = await services.heardRepeatsService.refreshRepeats(for: message.id)
        logger.debug("Fetched \(fetched.count) repeats for message \(message.id)")

        repeats = fetched
        isLoading = false
    }

}

#Preview("With Repeats") {
    RepeatDetailsSheet(
        message: MessageDTO(
            id: UUID(),
            deviceID: UUID(),
            contactID: nil,
            channelIndex: nil,
            text: "Test message",
            timestamp: UInt32(Date().timeIntervalSince1970),
            createdAt: Date(),
            direction: .outgoing,
            status: .delivered,
            textType: .plain,
            ackCode: nil,
            pathLength: 0,
            snr: nil,
            senderKeyPrefix: nil,
            senderNodeName: nil,
            isRead: true,
            replyToID: nil,
            roundTripTime: nil,
            heardRepeats: 2,
            retryAttempt: 0,
            maxRetryAttempts: 0,
            deduplicationKey: nil
        )
    )
    .environment(AppState())
}

#Preview("Empty") {
    RepeatDetailsSheet(
        message: MessageDTO(
            id: UUID(),
            deviceID: UUID(),
            contactID: nil,
            channelIndex: nil,
            text: "Test message",
            timestamp: UInt32(Date().timeIntervalSince1970),
            createdAt: Date(),
            direction: .outgoing,
            status: .delivered,
            textType: .plain,
            ackCode: nil,
            pathLength: 0,
            snr: nil,
            senderKeyPrefix: nil,
            senderNodeName: nil,
            isRead: true,
            replyToID: nil,
            roundTripTime: nil,
            heardRepeats: 0,
            retryAttempt: 0,
            maxRetryAttempts: 0,
            deduplicationKey: nil
        )
    )
    .environment(AppState())
}
