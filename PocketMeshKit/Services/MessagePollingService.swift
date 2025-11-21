import Foundation
import OSLog
import SwiftData

private let logger = Logger(subsystem: "com.pocketmesh.app", category: "Polling")

@MainActor
public final class MessagePollingService {
    private let `protocol`: MeshCoreProtocol
    private let modelContext: ModelContext
    private let deviceRepository: DeviceRepository

    private var pollingTask: Task<Void, Never>?
    private var pushNotificationTask: Task<Void, Never>?
    private var isPolling = false
    private var pollingInterval: TimeInterval = 30.0 // Fallback polling every 30 seconds
    private var stats = PollingStats()

    private struct PollingStats {
        var pushTriggeredPolls: Int = 0
        var scheduledPolls: Int = 0
        var messagesFromPush: Int = 0
        var messagesFromScheduled: Int = 0

        func logStats() {
            let total = pushTriggeredPolls + scheduledPolls
            if total > 0 {
                let pushMsgs = messagesFromPush
                let scheduledMsgs = messagesFromScheduled
                let pushEfficiency = Double(pushMsgs) / Double(pushMsgs + scheduledMsgs) * 100
                let efficiencyStr = String(format: "%.1f", pushEfficiency)
                logger.info(
                    """
                    Polling stats: \(pushMsgs) msgs from push, \(scheduledMsgs) from scheduled \
                    (\(efficiencyStr)% push efficiency)
                    """,
                )
            }
        }
    }

    public init(protocol: MeshCoreProtocol, modelContext: ModelContext, deviceRepository: DeviceRepository) {
        self.protocol = `protocol`
        self.modelContext = modelContext
        self.deviceRepository = deviceRepository

        // Subscribe to message waiting notifications
        pushNotificationTask = Task {
            await self.protocol.subscribeToPushNotifications { [weak self] code, _ in
                guard let self else { return }

                if code == PushCode.messageWaiting.rawValue {
                    // Trigger immediate message poll
                    await pollSingleMessage()
                }
            }
        }
    }

    public func startPolling() {
        guard !isPolling else { return }

        isPolling = true
        pollingTask = Task { [weak self] in
            await self?.pollMessages()
        }
    }

    public func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
        isPolling = false
    }

    public func logPollingStatistics() {
        stats.logStats()
    }

    private func pollMessages() async {
        logger.info("Starting hybrid message polling (event-driven with 30s fallback)")

        while !Task.isCancelled {
            do {
                guard let device = try deviceRepository.getActiveDevice() else {
                    try await Task.sleep(for: .seconds(pollingInterval))
                    continue
                }

                // Fetch all available messages
                await pollAllMessages(for: device, triggeredByPush: false)

                // Wait for next polling interval (push notifications will trigger immediate polls)
                try await Task.sleep(for: .seconds(pollingInterval))

            } catch {
                logger.error("Error in polling loop: \(error)")
                try? await Task.sleep(for: .seconds(5)) // Short retry delay on error
            }
        }
    }

    private func pollAllMessages(for device: Device, triggeredByPush: Bool = false) async {
        var messageCount = 0

        do {
            // Keep fetching until noMoreMessages
            while let incomingMessage = try await `protocol`.syncNextMessage() {
                try await handleIncomingMessage(incomingMessage, device: device)
                messageCount += 1
            }

            if messageCount > 0 {
                if triggeredByPush {
                    stats.pushTriggeredPolls += 1
                    stats.messagesFromPush += messageCount
                } else {
                    stats.scheduledPolls += 1
                    stats.messagesFromScheduled += messageCount
                }
                logger.info("Polled \(messageCount) message(s) - source: \(triggeredByPush ? "push" : "scheduled")")
            }
        } catch {
            logger.error("Failed to poll messages: \(error)")
        }
    }

    private func pollSingleMessage() async {
        do {
            guard let device = try deviceRepository.getActiveDevice() else {
                return
            }

            logger.debug("Message waiting push received - polling all messages")
            await pollAllMessages(for: device, triggeredByPush: true)
        } catch {
            logger.error("Failed to poll after message waiting push: \(error)")
        }
    }

    private func handleIncomingMessage(_ incoming: IncomingMessage, device: Device) async throws {
        if incoming.isDirect {
            // Direct message from contact
            guard let senderPrefix = incoming.senderPublicKeyPrefix else { return }

            // Find contact by public key prefix
            let contact = try findContact(byPublicKeyPrefix: senderPrefix, device: device)

            let message = Message(
                text: incoming.text,
                isOutgoing: false,
                contact: contact,
                channel: nil,
                device: device,
            )
            message.senderTimestamp = incoming.senderTimestamp
            message.senderPublicKeyPrefix = senderPrefix
            message.pathLength = incoming.pathLength
            message.snr = incoming.snr

            modelContext.insert(message)
            try modelContext.save()

            logger.info("Received direct message from \(contact?.name ?? "unknown")")

        } else {
            // Channel message
            guard let channelIndex = incoming.channelIndex else { return }

            let channel = try findChannel(bySlotIndex: channelIndex, device: device)

            let message = Message(
                text: incoming.text,
                isOutgoing: false,
                contact: nil,
                channel: channel,
                device: device,
            )
            message.senderTimestamp = incoming.senderTimestamp
            message.pathLength = incoming.pathLength
            message.snr = incoming.snr

            modelContext.insert(message)
            try modelContext.save()

            logger.info("Received channel message on slot \(channelIndex)")
        }
    }

    private func findContact(byPublicKeyPrefix _: Data, device _: Device) throws -> Contact? {
        // Note: This is a prefix match - in production we'd need better matching
        // For now, return nil and create unknown contact in UI layer
        nil
    }

    private func findChannel(bySlotIndex index: UInt8, device: Device) throws -> Channel? {
        let devicePublicKey = device.publicKey
        let descriptor = FetchDescriptor<Channel>(
            predicate: #Predicate { $0.slotIndex == index && $0.device?.publicKey == devicePublicKey },
        )
        return try modelContext.fetch(descriptor).first
    }
}
