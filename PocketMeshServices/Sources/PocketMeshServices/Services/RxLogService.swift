// PocketMeshServices/Sources/PocketMeshServices/Services/RxLogService.swift
import Foundation
import MeshCore
import OSLog

private let logger = PersistentLogger(subsystem: "com.pocketmesh.services", category: "RxLogService")

/// Actor that processes RX log events, decodes channel messages, and persists to database.
public actor RxLogService {
    private let session: MeshCoreSession
    private let persistenceStore: PersistenceStore
    private var deviceID: UUID?

    // Caches for fast lookup
    private var channelSecrets: [UInt8: Data] = [:]  // channelIndex -> secret
    private var channelNames: [UInt8: String] = [:]   // channelIndex -> name
    private var contactNames: [Data: String] = [:]    // pubkey prefix -> name

    // Stream for UI updates
    private var streamContinuation: AsyncStream<RxLogEntryDTO>.Continuation?

    // Event monitoring
    private var eventMonitorTask: Task<Void, Never>?

    // Heard repeats processing
    private var heardRepeatsService: HeardRepeatsService?

    public init(session: MeshCoreSession, persistenceStore: PersistenceStore) {
        self.session = session
        self.persistenceStore = persistenceStore
    }

    /// Sets the HeardRepeatsService for processing channel message repeats.
    public func setHeardRepeatsService(_ service: HeardRepeatsService) {
        self.heardRepeatsService = service
    }

    deinit {
        eventMonitorTask?.cancel()
    }

    // MARK: - Event Monitoring

    /// Start monitoring for RX log events from MeshCore.
    public func startEventMonitoring(deviceID: UUID) {
        self.deviceID = deviceID
        eventMonitorTask?.cancel()

        eventMonitorTask = Task { [weak self] in
            guard let self else { return }
            let events = await session.events()

            for await event in events {
                guard !Task.isCancelled else { break }
                if case .rxLogData(let parsed) = event {
                    await self.process(parsed)
                }
            }
        }
    }

    /// Stop monitoring events.
    public func stopEventMonitoring() {
        eventMonitorTask?.cancel()
        eventMonitorTask = nil
    }

    /// Returns a stream of new entries.
    /// - Note: Only one active subscriber is supported. Subsequent calls replace the previous subscriber.
    public func entryStream() -> AsyncStream<RxLogEntryDTO> {
        AsyncStream { continuation in
            Task { await self.setContinuation(continuation) }
            continuation.onTermination = { @Sendable _ in
                Task { await self.clearContinuation() }
            }
        }
    }

    private func setContinuation(_ continuation: AsyncStream<RxLogEntryDTO>.Continuation) {
        if streamContinuation != nil {
            logger.warning("Replacing existing RX log stream subscriber")
        }
        streamContinuation?.finish()
        self.streamContinuation = continuation
    }

    private func clearContinuation() {
        streamContinuation = nil
    }

    /// Update channel cache (secrets and names).
    public func updateChannels(secrets: [UInt8: Data], names: [UInt8: String]) {
        channelSecrets = secrets
        channelNames = names
    }

    /// Update contact names cache.
    public func updateContactNames(_ names: [Data: String]) {
        contactNames = names
    }

    /// Process a parsed RX log event.
    public func process(_ parsed: ParsedRxLogData) async {
        guard let deviceID else { return }

        // Decode channel message if applicable
        var channelIndex: UInt8?
        var channelName: String?
        var decryptStatus = DecryptStatus.notApplicable
        var decodedText: String?
        var senderTimestamp: UInt32?
        var fromContactName: String?

        if parsed.payloadType == .groupText || parsed.payloadType == .groupData {
            // Channel payload format: [channelHash: 1B] [MAC: 2B] [ciphertext: NB]
            // The first byte is a truncated channel hash (not the index), so we must
            // try all known secrets to find the one where MAC validates.
            let rawPayload = parsed.packetPayload

            // Need at least: 1 (channel hash) + 2 (MAC) + 16 (min ciphertext block)
            if rawPayload.count >= 1 + ChannelCrypto.macSize + 16 {
                let encryptedPayload = Data(rawPayload.dropFirst(1))

                for (index, secret) in self.channelSecrets {
                    let result = ChannelCrypto.decrypt(payload: encryptedPayload, secret: secret)
                    if case .success(let timestamp, _, let text) = result {
                        channelIndex = index
                        channelName = channelNames[index] ?? "Channel \(index)"
                        decryptStatus = .success
                        senderTimestamp = timestamp
                        decodedText = text
                        break
                    }
                }

                if decryptStatus == .notApplicable {
                    decryptStatus = .noMatchingKey
                }
            } else {
                decryptStatus = .pending
            }
        }

        // Resolve contact name from sender pubkey prefix (direct messages)
        if let senderPrefix = parsed.senderPubkeyPrefix {
            fromContactName = contactNames.first { storedPrefix, _ in
                storedPrefix.starts(with: senderPrefix) || senderPrefix.starts(with: storedPrefix)
            }?.value
        }

        // Create DTO
        let dto = RxLogEntryDTO(
            deviceID: deviceID,
            from: parsed,
            channelHash: channelIndex,
            channelName: channelName,
            decryptStatus: decryptStatus,
            fromContactName: fromContactName,
            senderTimestamp: senderTimestamp,
            decodedText: decodedText
        )

        // Persist
        do {
            try await persistenceStore.saveRxLogEntry(dto)
            try await persistenceStore.pruneRxLogEntries(deviceID: deviceID)
        } catch {
            logger.error("Failed to save RX log entry: \(error.localizedDescription)")
        }

        // Emit to stream
        streamContinuation?.yield(dto)

        // Process for heard repeats (fire and forget - don't block stream)
        if let heardRepeatsService = self.heardRepeatsService {
            Task {
                await heardRepeatsService.processForRepeats(dto)
            }
        }
    }

    /// Load existing entries from database, re-decrypting payloads with current secrets.
    public func loadExistingEntries() async -> [RxLogEntryDTO] {
        guard let deviceID else { return [] }
        do {
            let entries = try await persistenceStore.fetchRxLogEntries(deviceID: deviceID)
            return entries.map { decryptEntry($0) }
        } catch {
            logger.error("Failed to load RX log entries: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Decryption

    /// Attempt to decrypt a channel message entry using current secrets.
    /// Returns a copy of the entry with `decodedText` populated if decryption succeeds.
    /// This is reusable for export and other features that need decrypted content.
    ///
    /// If the entry was previously decrypted (`decryptStatus == .success`),
    /// we use the stored channel index for O(1) secret lookup instead of trying all keys.
    public func decryptEntry(_ entry: RxLogEntryDTO) -> RxLogEntryDTO {
        var result = entry

        // Only attempt decryption for channel messages
        guard entry.payloadType == .groupText || entry.payloadType == .groupData else {
            return result
        }

        // Skip if payload is too small
        guard entry.packetPayload.count >= 1 + ChannelCrypto.macSize + 16 else {
            return result
        }

        // Channel payload format: [channelHash: 1B] [MAC: 2B] [ciphertext: NB]
        let encryptedPayload = Data(entry.packetPayload.dropFirst(1))

        // Fast path: use stored channel index if previously decrypted successfully
        if entry.decryptStatus == .success, let channelIndex = entry.channelHash,
           let secret = channelSecrets[channelIndex] {
            let decryptResult = ChannelCrypto.decrypt(payload: encryptedPayload, secret: secret)
            if case .success(let timestamp, _, let text) = decryptResult {
                result.senderTimestamp = timestamp
                result.decodedText = text
                return result
            }
        }

        // Slow path: try all secrets (for .noMatchingKey entries or if fast path failed)
        for (_, secret) in channelSecrets {
            let decryptResult = ChannelCrypto.decrypt(payload: encryptedPayload, secret: secret)
            if case .success(let timestamp, _, let text) = decryptResult {
                result.senderTimestamp = timestamp
                result.decodedText = text
                break
            }
        }

        return result
    }

    /// Decrypt multiple entries concurrently. Useful for batch export.
    /// Uses parallel processing for better performance with large datasets.
    public func decryptEntries(_ entries: [RxLogEntryDTO]) async -> [RxLogEntryDTO] {
        // Capture secrets for concurrent access
        let secrets = channelSecrets

        return await withTaskGroup(of: (Int, RxLogEntryDTO).self) { group in
            for (index, entry) in entries.enumerated() {
                group.addTask {
                    let decrypted = Self.decryptEntry(entry, secrets: secrets)
                    return (index, decrypted)
                }
            }

            var results = entries
            for await (index, decrypted) in group {
                results[index] = decrypted
            }
            return results
        }
    }

    /// Static decryption for concurrent use (no actor isolation).
    private static func decryptEntry(_ entry: RxLogEntryDTO, secrets: [UInt8: Data]) -> RxLogEntryDTO {
        var result = entry

        guard entry.payloadType == .groupText || entry.payloadType == .groupData else {
            return result
        }

        guard entry.packetPayload.count >= 1 + ChannelCrypto.macSize + 16 else {
            return result
        }

        let encryptedPayload = Data(entry.packetPayload.dropFirst(1))

        // Fast path: use stored channel index
        if entry.decryptStatus == .success, let channelIndex = entry.channelHash,
           let secret = secrets[channelIndex] {
            let decryptResult = ChannelCrypto.decrypt(payload: encryptedPayload, secret: secret)
            if case .success(let timestamp, _, let text) = decryptResult {
                result.senderTimestamp = timestamp
                result.decodedText = text
                return result
            }
        }

        // Slow path: try all secrets
        for (_, secret) in secrets {
            let decryptResult = ChannelCrypto.decrypt(payload: encryptedPayload, secret: secret)
            if case .success(let timestamp, _, let text) = decryptResult {
                result.senderTimestamp = timestamp
                result.decodedText = text
                break
            }
        }

        return result
    }

    /// Clear all entries.
    public func clearEntries() async {
        guard let deviceID else { return }
        do {
            try await persistenceStore.clearRxLogEntries(deviceID: deviceID)
        } catch {
            logger.error("Failed to clear RX log entries: \(error.localizedDescription)")
        }
    }
}
