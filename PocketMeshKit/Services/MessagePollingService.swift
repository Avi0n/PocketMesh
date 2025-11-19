import Foundation
import SwiftData
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh.app", category: "Polling")

@MainActor
public final class MessagePollingService {

    private let `protocol`: MeshCoreProtocol
    private let modelContext: ModelContext
    private let deviceRepository: DeviceRepository

    private var pollingTask: Task<Void, Never>?
    private var isPolling = false

    public init(protocol: MeshCoreProtocol, modelContext: ModelContext, deviceRepository: DeviceRepository) {
        self.protocol = `protocol`
        self.modelContext = modelContext
        self.deviceRepository = deviceRepository

        // Listen for push notification that messages are waiting
        Task {
            // TODO: Implement push notification subscription when protocol supports it
            // For now, this is a placeholder for future implementation
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

    private func pollMessages() async {
        logger.info("Polling for messages...")

        do {
            let device = try deviceRepository.getActiveDevice()
            guard let device = device else {
                logger.warning("No active device for polling")
                return
            }

            // Poll until no more messages
            while true {
                guard let incoming = try await `protocol`.syncNextMessage() else {
                    logger.debug("No more messages in queue")
                    break
                }

                try await handleIncomingMessage(incoming, device: device)
            }

        } catch {
            logger.error("Message polling failed: \(error.localizedDescription)")
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
                device: device
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
                device: device
            )
            message.senderTimestamp = incoming.senderTimestamp
            message.pathLength = incoming.pathLength
            message.snr = incoming.snr

            modelContext.insert(message)
            try modelContext.save()

            logger.info("Received channel message on slot \(channelIndex)")
        }
    }

    private func findContact(byPublicKeyPrefix prefix: Data, device: Device) throws -> Contact? {
        // Note: This is a prefix match - in production we'd need better matching
        // For now, return nil and create unknown contact in UI layer
        return nil
    }

    private func findChannel(bySlotIndex index: UInt8, device: Device) throws -> Channel? {
        let devicePublicKey = device.publicKey
        let descriptor = FetchDescriptor<Channel>(
            predicate: #Predicate { $0.slotIndex == index && $0.device?.publicKey == devicePublicKey }
        )
        return try modelContext.fetch(descriptor).first
    }
}
