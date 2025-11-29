import Combine
import Foundation
import OSLog
import SwiftData

private let logger = Logger(subsystem: "com.pocketmesh.app", category: "Messaging")

@MainActor
public final class MessageService: ObservableObject {
    private let `protocol`: MeshCoreProtocol
    private let modelContext: ModelContext

    // Python spec defaults: max_attempts=3, flood_after=2, max_flood_attempts=2
    /// Total attempt limit (attempts 0, 1, 2)
    public var maxAttempts: Int = 3

    /// Switch to flood after this many attempts
    public var floodAfter: Int = 2

    /// Flood-specific limit
    public var maxFloodAttempts: Int = 2

    /// Timeout configuration (matching Python spec)
    public var timeoutMultiplier: Double = 1.2 // 20% buffer over suggested timeout

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
        defer { sendingMessages.remove(messageId) }

        var attempts = 0
        var floodAttempts = 0
        var isFloodMode = false

        // Unified retry loop per Python spec:
        // while attempts < max_attempts AND (not flood OR flood_attempts < max_flood_attempts)
        while attempts < maxAttempts, !isFloodMode || floodAttempts < maxFloodAttempts {
            do {
                // Switch to flood mode at floodAfter threshold
                if attempts >= floodAfter, !isFloodMode {
                    logger.info("[Messaging] Switching to flood mode after \(attempts) attempts")
                    isFloodMode = true
                    floodAttempts = 0

                    // CRITICAL: Call resetPath() when switching to flood
                    do {
                        try await self.protocol.resetPath(publicKey: contact.publicKey)
                    } catch {
                        logger.warning("[Messaging] Failed to reset path: \(error.localizedDescription)")
                        // Continue even if resetPath fails
                    }
                }

                // Update message status
                message.deliveryStatus = .sending
                message.retryCount = attempts
                message.lastRetryDate = Date()
                try modelContext.save()

                logger.info("[Messaging] Attempt \(attempts + 1)/\(self.maxAttempts) (\(isFloodMode ? "flood" : "direct"))")

                // Send message (flood mode controlled by previous setFloodScope call)
                let result = try await self.protocol.sendTextMessage(
                    text: message.text,
                    recipientPublicKey: contact.publicKey,
                    floodMode: isFloodMode,
                    scope: scope,
                    attempt: UInt8(attempts),
                )

                // Update message with delivery info
                message.ackCode = result.expectedAck
                let timeoutInterval = TimeInterval(result.estimatedTimeout) / 1000.0 * timeoutMultiplier
                message.expectedAckTimeout = Date().addingTimeInterval(timeoutInterval)
                message.deliveryStatus = .sent
                message.routingMode = isFloodMode ? .meshBroadcast : .direct
                message.retryCount = attempts + 1
                try modelContext.save()

                logger.info("[Messaging] Message sent (\(isFloodMode ? "flood" : "direct")), ACK: \(String(format: "%08X", result.expectedAck))")

                // Success!
                return

            } catch {
                attempts += 1
                if isFloodMode {
                    floodAttempts += 1
                }

                logger.warning("[Messaging] Attempt \(attempts) failed: \(error.localizedDescription)")

                // Exponential backoff before retry
                if attempts < maxAttempts {
                    let delay = pow(2.0, Double(attempts - 1)) // 2^(attempt-1) seconds
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        // All attempts failed
        message.deliveryStatus = .failed
        message.retryCount = attempts
        try? modelContext.save()

        logger.error("[Messaging] Message delivery failed after \(attempts) total attempts")
    }

    /// Handle incoming ACK confirmation
    func handleAckConfirmation(ackCode: UInt32, roundTripMs: UInt32) {
        do {
            // Find message with matching ACK code (sent or already delivered)
            let sentStatus = DeliveryStatus.sent
            let deliveredStatus = DeliveryStatus.delivered
            let descriptor = FetchDescriptor<Message>(
                predicate: #Predicate { message in
                    message.ackCode == ackCode &&
                        (message.deliveryStatus == sentStatus || message.deliveryStatus == deliveredStatus)
                },
            )

            guard let message = try modelContext.fetch(descriptor).first as? Message else {
                // In multi-ACK mode, duplicate ACKs are expected
                logger.debug("Received ACK for code \(String(format: "%08X", ackCode)) - already processed or unknown")
                return
            }

            // Update status only if not already delivered
            if message.deliveryStatus == sentStatus {
                message.deliveryStatus = .delivered
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
