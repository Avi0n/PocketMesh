import Foundation
import SwiftData
import OSLog
import Combine

private let logger = Logger(subsystem: "com.pocketmesh.app", category: "Messaging")

@MainActor
public final class MessageService: ObservableObject {

    private let `protocol`: MeshCoreProtocol
    private let modelContext: ModelContext

    private let maxRetries = 3
    private var sendTasks: [UUID: Task<Void, Never>] = [:]

    @Published var sendingMessages: Set<UUID> = []

    public init(protocol: MeshCoreProtocol, modelContext: ModelContext) {
        self.protocol = `protocol`
        self.modelContext = modelContext
    }

    /// Send a direct message to a contact
    public func sendMessage(text: String, to contact: Contact, device: Device) async throws {
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
            device: device
        )
        modelContext.insert(message)
        try modelContext.save()

        // Attempt to send
        await sendMessageWithRetry(message, contact: contact)
    }

    private func sendMessageWithRetry(_ message: Message, contact: Contact) async {
        let messageId = message.id
        sendingMessages.insert(messageId)
        defer { sendingMessages.remove(messageId) }

        // Try direct send first (up to maxRetries)
        for attempt in 0..<maxRetries {
            do {
                message.deliveryStatus = .sending
                message.retryCount = attempt
                message.lastRetryDate = Date()
                try modelContext.save()

                logger.info("Sending message attempt \(attempt + 1)/\(self.maxRetries)")

                let result = try await `protocol`.sendTextMessage(
                    text: message.text,
                    recipientPublicKey: contact.publicKey,
                    floodMode: false
                )

                // Update with ACK tracking
                message.ackCode = result.ackCode
                message.expectedAckTimeout = Date().addingTimeInterval(TimeInterval(result.timeoutSeconds))
                message.deliveryStatus = .sent
                try modelContext.save()

                logger.info("Message sent successfully, ACK code: \(result.ackCode)")
                return

            } catch {
                logger.error("Send attempt \(attempt + 1) failed: \(error.localizedDescription)")

                if attempt < maxRetries - 1 {
                    // Wait before retry (exponential backoff)
                    try? await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt))) * 1_000_000_000)
                }
            }
        }

        // All direct attempts failed - try flood mode as fallback
        logger.warning("All direct attempts failed, trying flood mode")

        do {
            let result = try await `protocol`.sendTextMessage(
                text: message.text,
                recipientPublicKey: contact.publicKey,
                floodMode: true
            )

            message.ackCode = result.ackCode
            message.deliveryStatus = .sent
            try modelContext.save()

            logger.info("Message sent via flood mode")

        } catch {
            logger.error("Flood mode send failed: \(error.localizedDescription)")
            message.deliveryStatus = .failed
            try? modelContext.save()
        }
    }

    /// Handle incoming ACK confirmation
    func handleAckConfirmation(ackCode: UInt32, roundTripMs: UInt32) {
        do {
            // Find message with matching ACK code
            let sentStatus = DeliveryStatus.sent
            let descriptor = FetchDescriptor<Message>(
                predicate: #Predicate { message in
                    message.ackCode == ackCode && message.deliveryStatus == sentStatus
                }
            )

            guard let message = try modelContext.fetch(descriptor).first else {
                logger.warning("Received ACK for unknown message: \(ackCode)")
                return
            }

            message.deliveryStatus = .acknowledged
            try modelContext.save()

            logger.info("Message acknowledged (RTT: \(roundTripMs)ms)")

        } catch {
            logger.error("Failed to handle ACK: \(error.localizedDescription)")
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
        case .messageTooLong: return "Message exceeds 160 byte limit"
        case .noActiveDevice: return "No active device connected"
        case .contactNotFound: return "Contact not found"
        }
    }
}
