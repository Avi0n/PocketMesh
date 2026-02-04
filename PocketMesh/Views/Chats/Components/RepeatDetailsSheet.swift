// PocketMesh/Views/Chats/Components/RepeatDetailsSheet.swift
import SwiftUI
import PocketMeshServices
import OSLog

/// Sheet displaying detailed information about heard repeats for a message.
struct RepeatDetailsSheet: View {
    let message: MessageDTO

    @Environment(\.appState) private var appState

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
                            L10n.Chats.Chats.Repeats.EmptyState.title,
                            systemImage: "arrow.triangle.branch",
                            description: Text(L10n.Chats.Chats.Repeats.EmptyState.description)
                        )
                    }
                } else {
                    Section {
                        ForEach(repeats) { repeatEntry in
                            RepeatRowView(
                                repeatEntry: repeatEntry,
                                repeaters: repeaters,
                                userLocation: appState.locationService.currentLocation
                            )
                        }
                    }
                }
            }
            .navigationTitle(L10n.Chats.Chats.Repeats.title)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await loadRepeats()
            }
        }
    }

    private func loadRepeats() async {
        logger.info("Loading repeats for message \(message.id), heardRepeats=\(message.heardRepeats)")

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
        logger.info("Fetched \(fetched.count) repeats for message \(message.id)")

        repeats = fetched
        isLoading = false
    }

    private var repeaters: [ContactDTO] {
        contacts.filter { $0.type == .repeater }
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
    .environment(\.appState, AppState())
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
    .environment(\.appState, AppState())
}
