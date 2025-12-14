import Foundation
import PocketMeshKit
import OSLog

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

    private let logger = Logger(subsystem: "com.pocketmesh", category: "MessageEventBroadcaster")

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

    /// Reference to remote node service for handling login results
    var remoteNodeService: RemoteNodeService?

    /// Reference to data store for resolving public key prefixes
    var dataStore: DataStore?

    /// Reference to room server service for handling room messages
    var roomServerService: RoomServerService?

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
            await MainActor.run {
                self.logger.warning("Received send confirmation but MessageService not ready - ack: \(confirmation.ackCode)")
            }
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
            await MainActor.run {
                self.logger.error("Failed to handle send confirmation: \(error)")
            }
        }
    }

    nonisolated public func messagePollingService(
        _ service: MessagePollingService,
        didReceiveStatusResponse status: RemoteNodeStatus
    ) async {
        // Status responses can be used for node health monitoring
        // For now, just log the receipt - future implementation could update contact status
        let prefixHex = status.publicKeyPrefix.map { String(format: "%02x", $0) }.joined()
        await MainActor.run {
            self.logger.info("Received status response from node: \(prefixHex)")
        }
    }

    nonisolated public func messagePollingService(
        _ service: MessagePollingService,
        didReceiveLoginResult result: LoginResult,
        fromPublicKeyPrefix: Data
    ) async {
        let prefixHex = fromPublicKeyPrefix.map { String(format: "%02x", $0) }.joined()
        await MainActor.run {
            self.logger.info("Received login result from node: \(prefixHex), success: \(result.success)")
        }

        // Get service references from MainActor context
        let nodeService = await MainActor.run { self.remoteNodeService }
        let store = await MainActor.run { self.dataStore }

        guard let nodeService, let store else {
            await MainActor.run {
                self.logger.warning("Cannot handle login result - services not configured")
            }
            return
        }

        // Resolve 6-byte prefix to full 32-byte public key
        guard let contact = try? await store.findContactByKeyPrefix(fromPublicKeyPrefix),
              contact.publicKey.count == 32 else {
            await MainActor.run {
                self.logger.warning("Cannot resolve public key prefix to full key")
            }
            return
        }

        // Forward to RemoteNodeService to resume the waiting continuation
        await nodeService.handleLoginResult(result, fromPublicKey: contact.publicKey)
    }

    /// Called when a message fails due to ACK timeout
    func handleMessageFailed(messageID: UUID) {
        self.latestEvent = .messageFailed(messageID: messageID)
        self.newMessageCount += 1
    }

    nonisolated public func messagePollingService(
        _ service: MessagePollingService,
        didReceiveRoomMessage frame: MessageFrame,
        fromRoom contact: ContactDTO
    ) async {
        let roomService = await MainActor.run { self.roomServerService }

        guard let roomService else {
            await MainActor.run {
                self.logger.warning("Room message received but RoomServerService not configured")
            }
            return
        }

        guard let authorPrefix = frame.extraData, authorPrefix.count >= 4 else {
            await MainActor.run {
                self.logger.warning("Room message missing author prefix")
            }
            return
        }

        do {
            try await roomService.handleIncomingMessage(
                senderPublicKeyPrefix: frame.senderPublicKeyPrefix,
                timestamp: frame.timestamp,
                authorPrefix: Data(authorPrefix.prefix(4)),
                text: frame.text
            )

            await MainActor.run {
                self.newMessageCount += 1
            }
        } catch {
            await MainActor.run {
                self.logger.error("Failed to handle room message: \(error)")
            }
        }
    }
}
