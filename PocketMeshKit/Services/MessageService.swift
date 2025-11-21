import Combine
import Foundation
import OSLog
import SwiftData

private let logger = Logger(subsystem: "com.pocketmesh.app", category: "Messaging")

@MainActor
public final class MessageService: ObservableObject {
    private let `protocol`: MeshCoreProtocol
    private let modelContext: ModelContext

    /// Maximum attempts before switching to flood mode
    public var maxDirectAttempts: Int = 3

    /// Switch to flood mode after N failed direct attempts (CLI: flood_after=2)
    public var floodAfterAttempts: Int = 2

    /// Maximum flood mode attempts after direct attempts fail
    public var maxFloodAttempts: Int = 1

    /// Enable multi-ACK duplicate detection
    public var multiAckEnabled: Bool = true

    private var sendTasks: [UUID: Task<Void, Never>] = [:]

    @Published var sendingMessages: Set<UUID> = []

    public init(protocol: MeshCoreProtocol, modelContext: ModelContext) {
        self.protocol = `protocol`
        self.modelContext = modelContext

        // Subscribe to ACK confirmations
        Task {
            await self.protocol.subscribeToPushNotifications { [weak self] code, payload in
                guard let self else { return }

                if code == PushCode.sendConfirmed.rawValue {
                    await handleSendConfirmedPush(payload: payload)
                }
            }
        }
    }

    /// Send a direct message to a contact
    public func sendMessage(text: String, to contact: Contact, device: Device, scope: String? = nil) async throws {
        // Validate message length (160 bytes max per protocol)
        guard text.utf8.count <= 160 else {
            throw MessageError.messageTooLong
        }

        // Create message record
        let message = Message(
            text: text,
            isOutgoing: true,
            contact: contact,
            channel: nil,
            device: device,
        )
        modelContext.insert(message)
        try modelContext.save()

        // Attempt to send
        await sendMessageWithRetry(message, contact: contact, scope: scope)
    }

    private func sendMessageWithRetry(_ message: Message, contact: Contact, scope: String? = nil) async {
        let messageId = message.id
        sendingMessages.insert(messageId)
        defer { self.sendingMessages.remove(messageId) }

        if await tryDirectRouting(message: message, contact: contact, scope: scope) {
            return // Success - direct routing worked
        }

        await tryFloodRouting(message: message, contact: contact, scope: scope)
    }

    private func tryDirectRouting(message: Message, contact: Contact, scope: String?) async -> Bool {
        for attempt in 0 ..< maxDirectAttempts {
            do {
                message.deliveryStatus = .sending
                message.retryCount = attempt
                message.lastRetryDate = Date()
                try modelContext.save()

                let attemptInfo = "\(attempt + 1)/\(maxDirectAttempts)"
                logger.info("Direct send attempt \(attemptInfo)")

                let result = try await self.protocol.sendTextMessage(
                    text: message.text,
                    recipientPublicKey: contact.publicKey,
                    floodMode: false,
                    scope: scope,
                )

                await handleDirectSendSuccess(message: message, result: result)
                return true

            } catch {
                logger.error("Direct attempt \(attempt + 1) failed: \(error.localizedDescription)")

                if attempt + 1 >= floodAfterAttempts {
                    logger.info("Reached flood_after threshold (\(self.floodAfterAttempts)), switching to flood mode")
                    break
                }

                if attempt < maxDirectAttempts - 1 {
                    try? await Task.sleep(
                        nanoseconds: UInt64(pow(2.0, Double(attempt))) * 1_000_000_000,
                    )
                }
            }
        }
        return false
    }

    private func handleDirectSendSuccess(message: Message, result: MessageSendResult) async {
        message.ackCode = result.ackCode
        let timeoutInterval = TimeInterval(result.timeoutSeconds)
        message.expectedAckTimeout = Date().addingTimeInterval(timeoutInterval)
        message.deliveryStatus = .sent
        message.routingMode = .direct
        try? modelContext.save()

        logger.info("Message sent (direct), ACK: \(String(format: "%08X", result.ackCode))")
    }

    private func tryFloodRouting(message: Message, contact: Contact, scope: String?) async {
        logger.warning("Direct routing failed after \(message.retryCount) attempts, trying flood mode")

        for floodAttempt in 0 ..< maxFloodAttempts {
            do {
                message.deliveryStatus = .sending
                message.retryCount += 1
                try modelContext.save()

                let attemptInfo = "\(floodAttempt + 1)/\(maxFloodAttempts)"
                logger.info("Flood attempt \(attemptInfo)")

                let result = try await self.protocol.sendTextMessage(
                    text: message.text,
                    recipientPublicKey: contact.publicKey,
                    floodMode: true,
                    scope: scope,
                )

                await handleFloodSendSuccess(message: message, result: result)
                return

            } catch {
                logger.error("Flood attempt \(floodAttempt + 1) failed: \(error.localizedDescription)")

                if floodAttempt < maxFloodAttempts - 1 {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }

        await handleSendFailure(message: message)
    }

    private func handleFloodSendSuccess(message: Message, result: MessageSendResult) async {
        message.ackCode = result.ackCode
        message.deliveryStatus = .sent
        message.routingMode = .flood
        try? modelContext.save()

        logger.info("Message sent (flood), ACK: \(String(format: "%08X", result.ackCode))")
    }

    private func handleSendFailure(message: Message) async {
        logger.error("Message delivery failed after \(message.retryCount) total attempts")
        message.deliveryStatus = .failed
        try? modelContext.save()
    }

    /// Handle incoming ACK confirmation
    func handleAckConfirmation(ackCode: UInt32, roundTripMs: UInt32) {
        do {
            // Find message with matching ACK code (sent or already acknowledged)
            let sentStatus = DeliveryStatus.sent
            let acknowledgedStatus = DeliveryStatus.acknowledged
            let descriptor = FetchDescriptor<Message>(
                predicate: #Predicate { message in
                    message.ackCode == ackCode &&
                        (message.deliveryStatus == sentStatus || message.deliveryStatus == acknowledgedStatus)
                },
            )

            guard let message = try modelContext.fetch(descriptor).first else {
                // In multi-ACK mode, duplicate ACKs are expected
                logger.debug("Received ACK for code \(String(format: "%08X", ackCode)) - already processed or unknown")
                return
            }

            // Update status only if not already acknowledged
            if message.deliveryStatus == sentStatus {
                message.deliveryStatus = .acknowledged
                try modelContext.save()
                logger.info("Message acknowledged in \(roundTripMs)ms (ACK code: \(String(format: "%08X", ackCode)))")
            } else {
                logger.debug(
                    "Duplicate ACK received for code \(String(format: "%08X", ackCode)) - multi-ACK mode active",
                )
            }

        } catch {
            logger.error("Failed to handle ACK: \(error.localizedDescription)")
        }
    }

    /// Handle sendConfirmed push notification
    private func handleSendConfirmedPush(payload: Data) async {
        // Decode push payload
        guard payload.count >= 8 else {
            logger.error("Invalid sendConfirmed push payload size: \(payload.count)")
            return
        }

        // Extract ACK code (UInt32 little-endian) and round-trip time (UInt32 little-endian)
        let ackCode = payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }
        let roundTripMs = payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self) }

        logger.info("Received sendConfirmed push - ACK: \(String(format: "%08X", ackCode)), RTT: \(roundTripMs)ms")

        // Use existing ACK handling logic
        await MainActor.run {
            self.handleAckConfirmation(ackCode: ackCode, roundTripMs: roundTripMs)
        }
    }

    /// Delete a queued message
    public func deleteMessage(_ message: Message) throws {
        modelContext.delete(message)
        try modelContext.save()
    }
}

public enum MessageError: LocalizedError {
    case messageTooLong
    case noActiveDevice
    case contactNotFound

    public var errorDescription: String? {
        switch self {
        case .messageTooLong: "Message exceeds 160 byte limit"
        case .noActiveDevice: "No active device connected"
        case .contactNotFound: "Contact not found"
        }
    }
}
