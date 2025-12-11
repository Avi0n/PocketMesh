import Foundation
import PocketMeshKit

/// Events broadcast when messages arrive or status changes
public enum MessageEvent: Sendable, Equatable {
    case directMessageReceived(message: MessageDTO, contact: ContactDTO)
    case channelMessageReceived(message: MessageDTO, channelIndex: UInt8)
    case messageStatusUpdated(ackCode: UInt32)
    case messageFailed(messageID: UUID)
    case unknownSender(keyPrefix: Data)
    case error(String)
}

/// Broadcasts message events from MessagePollingService to SwiftUI views.
/// This bridges actor isolation to @MainActor context.
@Observable
@MainActor
public final class MessageEventBroadcaster: MessagePollingDelegate {

    // MARK: - Properties

    /// Latest received message (for simple observation)
    var latestMessage: MessageDTO?

    /// Latest event for reactive updates
    var latestEvent: MessageEvent?

    /// Count of new messages (triggers view updates)
    var newMessageCount: Int = 0

    /// Reference to notification service for posting notifications
    var notificationService: NotificationService?

    /// Channel name lookup function (set by AppState)
    var channelNameLookup: ((_ deviceID: UUID, _ channelIndex: UInt8) async -> String?)?

    /// Reference to message service for handling send confirmations
    var messageService: MessageService?

    // MARK: - Initialization

    public init() {}

    // MARK: - MessagePollingDelegate

    nonisolated public func messagePollingService(
        _ service: MessagePollingService,
        didReceiveDirectMessage message: MessageDTO,
        from contact: ContactDTO
    ) async {
        await MainActor.run {
            self.latestMessage = message
            self.latestEvent = .directMessageReceived(message: message, contact: contact)
            self.newMessageCount += 1

            // Post notification
            Task {
                await self.notificationService?.postDirectMessageNotification(
                    from: contact.displayName,
                    contactID: contact.id,
                    messageText: message.text,
                    messageID: message.id
                )
            }
        }
    }

    nonisolated public func messagePollingService(
        _ service: MessagePollingService,
        didReceiveChannelMessage message: MessageDTO,
        channelIndex: UInt8
    ) async {
        await MainActor.run {
            self.latestEvent = .channelMessageReceived(message: message, channelIndex: channelIndex)
            self.newMessageCount += 1

            // Post notification
            Task {
                let channelName = await self.channelNameLookup?(message.deviceID, channelIndex) ?? "Channel \(channelIndex)"
                await self.notificationService?.postChannelMessageNotification(
                    channelName: channelName,
                    channelIndex: channelIndex,
                    senderName: message.senderNodeName,  // CHANGED: Use parsed sender name instead of nil
                    messageText: message.text,
                    messageID: message.id
                )
            }
        }
    }

    nonisolated public func messagePollingService(
        _ service: MessagePollingService,
        didReceiveUnknownSender keyPrefix: Data
    ) async {
        await MainActor.run {
            self.latestEvent = .unknownSender(keyPrefix: keyPrefix)
        }
    }

    nonisolated public func messagePollingService(
        _ service: MessagePollingService,
        didEncounterError error: MessagePollingError
    ) async {
        await MainActor.run {
            self.latestEvent = .error(error.localizedDescription)
        }
    }

    nonisolated public func messagePollingService(
        _ service: MessagePollingService,
        didReceiveSendConfirmation confirmation: SendConfirmation
    ) async {
        // Access messageService on MainActor then call into the actor
        let msgService = await MainActor.run { self.messageService }

        guard let msgService else {
            print("[MessageEventBroadcaster] Received send confirmation but MessageService not ready - ack: \(confirmation.ackCode)")
            return
        }

        do {
            try await msgService.handleSendConfirmation(confirmation)

            // Notify views of status update so they refresh
            await MainActor.run {
                self.latestEvent = .messageStatusUpdated(ackCode: confirmation.ackCode)
                self.newMessageCount += 1
            }
        } catch {
            print("[MessageEventBroadcaster] Failed to handle send confirmation: \(error)")
        }
    }

    nonisolated public func messagePollingService(
        _ service: MessagePollingService,
        didReceiveStatusResponse status: RemoteNodeStatus
    ) async {
        // Status responses can be used for node health monitoring
        // For now, just log the receipt - future implementation could update contact status
        let prefixHex = status.publicKeyPrefix.map { String(format: "%02x", $0) }.joined()
        print("[MessageEventBroadcaster] Received status response from node: \(prefixHex)")
    }

    /// Called when a message fails due to ACK timeout
    func handleMessageFailed(messageID: UUID) {
        self.latestEvent = .messageFailed(messageID: messageID)
        self.newMessageCount += 1
    }
}
