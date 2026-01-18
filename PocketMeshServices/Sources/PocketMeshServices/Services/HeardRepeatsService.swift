// PocketMeshServices/Sources/PocketMeshServices/Services/HeardRepeatsService.swift
import Foundation
import MeshCore
import OSLog

/// Callback signature for when a heard repeat is recorded
public typealias HeardRepeatHandler = @Sendable (UUID, Int) async -> Void

/// Service for correlating RX log entries to sent channel messages
/// and tracking "heard repeats" - evidence of message propagation through the mesh.
public actor HeardRepeatsService {
    private let persistenceStore: PersistenceStore
    private let logger = PersistentLogger(subsystem: "PocketMesh", category: "HeardRepeatsService")

    /// Device ID for the current session
    private var deviceID: UUID?

    /// Local node name for matching sender in decrypted messages
    private var localNodeName: String?

    /// Handler called when a repeat is recorded (messageID, newCount)
    private var onRepeatRecorded: HeardRepeatHandler?

    public init(persistenceStore: PersistenceStore) {
        self.persistenceStore = persistenceStore
    }

    /// Sets the handler called when a repeat is recorded.
    public func setRepeatRecordedHandler(_ handler: @escaping HeardRepeatHandler) {
        self.onRepeatRecorded = handler
    }

    /// Configure the service with device context.
    /// Must be called once before processing any RX log entries.
    /// Thread-safe due to actor isolation.
    public func configure(deviceID: UUID, localNodeName: String) {
        self.deviceID = deviceID
        self.localNodeName = localNodeName
        logger.info("Configured with deviceID: \(deviceID), nodeName: \(localNodeName)")
    }

    /// Checks if a repeat has already been recorded for this RX log entry.
    private func isDuplicateRepeat(_ entryID: UUID) async -> Bool {
        do {
            return try await persistenceStore.messageRepeatExists(rxLogEntryID: entryID)
        } catch {
            logger.error("Failed to check for existing repeat: \(error.localizedDescription)")
            return true // Assume duplicate on error to prevent potential duplicates
        }
    }

    /// Process an RX log entry to check if it's a repeat of a sent message.
    ///
    /// Called by RxLogService for each new entry. Only processes successfully
    /// decrypted channel messages within the 10-second matching window.
    ///
    /// - Parameter entry: The RX log entry to process
    /// - Returns: The updated heardRepeats count if a match was found, nil otherwise
    @discardableResult
    public func processForRepeats(_ entry: RxLogEntryDTO) async -> Int? {
        logger.info("[REPEAT-DEBUG] processForRepeats called, entryID=\(entry.id)")

        // Only process successfully decrypted channel messages
        guard entry.payloadType == .groupText else {
            logger.info("[REPEAT-DEBUG] Skip: payloadType=\(String(describing: entry.payloadType)), expected .groupText")
            return nil
        }
        guard entry.decryptStatus == .success else {
            logger.info("[REPEAT-DEBUG] Skip: decryptStatus=\(String(describing: entry.decryptStatus)), expected .success")
            return nil
        }
        guard let decodedText = entry.decodedText else {
            logger.info("[REPEAT-DEBUG] Skip: decodedText is nil")
            return nil
        }
        guard let channelIndex = entry.channelHash else {
            logger.info("[REPEAT-DEBUG] Skip: channelHash is nil")
            return nil
        }
        guard let senderTimestamp = entry.senderTimestamp else {
            logger.info("[REPEAT-DEBUG] Skip: senderTimestamp is nil")
            return nil
        }
        guard let deviceID = self.deviceID else {
            logger.info("[REPEAT-DEBUG] Skip: self.deviceID is nil (service not configured)")
            return nil
        }
        guard let localNodeName = self.localNodeName else {
            logger.info("[REPEAT-DEBUG] Skip: self.localNodeName is nil (service not configured)")
            return nil
        }

        logger.info("[REPEAT-DEBUG] Passed guards: channel=\(channelIndex), localNodeName=\(localNodeName)")

        // Parse "NodeName: MessageText" format using shared utility
        guard let (senderName, messageText) = ChannelMessageFormat.parse(decodedText) else {
            logger.info("Failed to parse channel message text: \(decodedText.prefix(50))")
            return nil
        }

        // Only match messages from our own node
        guard senderName == localNodeName else {
            logger.info("[REPEAT-DEBUG] Skip: senderName=\(senderName), localNodeName=\(localNodeName) - not a match")
            return nil
        }

        // Check for duplicate (already processed this RX entry)
        if await isDuplicateRepeat(entry.id) {
            logger.info("Repeat already recorded for RX entry: \(entry.id)")
            return nil
        }

        // Find matching sent message
        do {
            logger.info("[REPEAT-DEBUG] Searching for sent message: deviceID=\(deviceID), channel=\(channelIndex), timestamp=\(senderTimestamp), text=\(messageText.prefix(30))")
            guard let message = try await persistenceStore.findSentChannelMessage(
                deviceID: deviceID,
                channelIndex: channelIndex,
                timestamp: senderTimestamp,
                text: messageText,
                withinSeconds: 10
            ) else {
                logger.info("[REPEAT-DEBUG] No matching sent message found")
                return nil
            }
            logger.info("[REPEAT-DEBUG] Found matching message: id=\(message.id), status=\(String(describing: message.status))")

            // Create repeat entry
            let repeatDTO = MessageRepeatDTO(
                messageID: message.id,
                receivedAt: entry.receivedAt,
                pathNodes: entry.pathNodes,
                snr: entry.snr,
                rssi: entry.rssi,
                rxLogEntryID: entry.id
            )

            try await persistenceStore.saveMessageRepeat(repeatDTO)

            // Increment and return new count
            let newCount = try await persistenceStore.incrementMessageHeardRepeats(id: message.id)

            logger.info("Recorded repeat #\(newCount) for message \(message.id)")

            // Notify handler
            if let handler = onRepeatRecorded {
                logger.info("[REPEAT-DEBUG] Calling onRepeatRecorded handler for message=\(message.id), count=\(newCount)")
                await handler(message.id, newCount)
            } else {
                logger.warning("[REPEAT-DEBUG] No onRepeatRecorded handler set!")
            }

            return newCount

        } catch {
            logger.error("Failed to process repeat: \(error.localizedDescription)")
            return nil
        }
    }

    /// Refresh repeats for a specific message by querying the RX log.
    /// Used when opening the Repeat Details sheet to catch any missed repeats.
    ///
    /// - Parameter messageID: The message to refresh repeats for
    /// - Returns: Array of repeat DTOs sorted by receivedAt
    public func refreshRepeats(for messageID: UUID) async -> [MessageRepeatDTO] {
        // Return existing repeats from database
        logger.info("refreshRepeats called for messageID: \(messageID)")
        do {
            let results = try await persistenceStore.fetchMessageRepeats(messageID: messageID)
            logger.info("refreshRepeats returning \(results.count) repeats")
            return results
        } catch {
            logger.error("Failed to fetch repeats: \(error.localizedDescription)")
            return []
        }
    }
}
