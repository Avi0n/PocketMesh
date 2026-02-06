import Foundation
import MeshCore
import os

// MARK: - Advertisement Errors

public enum AdvertisementError: Error, Sendable {
    case notConnected
    case sendFailed
    case invalidResponse
    case sessionError(MeshCoreError)
}

// MARK: - Advertisement Service

/// Service for managing device advertisements and discovery.
/// Handles sending self-advertisements and processing incoming adverts via MeshCore events.
public actor AdvertisementService {

    // MARK: - Properties

    private let logger = PersistentLogger(subsystem: "com.pocketmesh", category: "Advertisement")

    private let session: MeshCoreSession
    private let dataStore: PersistenceStore

    /// Task monitoring for events
    private var eventMonitorTask: Task<Void, Never>?
    private var currentDeviceID: UUID?

    /// Whether contact fetches should be deferred (during sync)
    private var isSyncingContacts = false
    private var pendingUnknownContactKeys: Set<Data> = []

    /// Handler for new advertisement events (for UI updates)
    private var advertHandler: (@Sendable (ContactFrame) -> Void)?

    /// Handler for path update events
    private var pathUpdateHandler: (@Sendable (Data, Int8) -> Void)?

    /// Handler for path discovery response events
    private var pathDiscoveryHandler: (@Sendable (PathInfo) -> Void)?

    /// Handler for routing change events (set by AppState)
    private var routingChangedHandler: (@Sendable (UUID, Bool) async -> Void)?

    /// Handler for contact update events (for UI refresh)
    private var contactUpdatedHandler: (@Sendable () async -> Void)?

    // MARK: - Discovery Handlers

    /// Handler for new contact discovered events (for notifications)
    /// Parameters: contactName, contactID, contactType
    private var newContactDiscoveredHandler: (@Sendable (String, UUID, ContactType) async -> Void)?

    /// Handler for contact sync request events (when ADVERT received for unknown contact)
    private var contactSyncRequestHandler: (@Sendable (UUID) async -> Void)?

    /// Handler for node storage full state changes (true = full, false = has space)
    private var nodeStorageFullChangedHandler: (@Sendable (Bool) async -> Void)?

    /// Handler for contact deleted cleanup (notifications, badge, session)
    /// Parameters: contactID, publicKey
    private var contactDeletedCleanupHandler: (@Sendable (UUID, Data) async -> Void)?

    /// Cache local reception SNR from rxLogData for trace responses (tag → SNR)
    private var traceLocalSnr: [UInt32: Double] = [:]

    // MARK: - Initialization

    public init(session: MeshCoreSession, dataStore: PersistenceStore) {
        self.session = session
        self.dataStore = dataStore
    }

    deinit {
        eventMonitorTask?.cancel()
    }

    // MARK: - Event Handlers

    /// Set handler for new advertisement events
    public func setAdvertHandler(_ handler: @escaping @Sendable (ContactFrame) -> Void) {
        advertHandler = handler
    }

    /// Set handler for path update events
    public func setPathUpdateHandler(_ handler: @escaping @Sendable (Data, Int8) -> Void) {
        pathUpdateHandler = handler
    }

    /// Set handler for path discovery response events
    public func setPathDiscoveryHandler(_ handler: @escaping @Sendable (PathInfo) -> Void) {
        pathDiscoveryHandler = handler
    }

    /// Set handler for routing change events
    public func setRoutingChangedHandler(_ handler: @escaping @Sendable (UUID, Bool) async -> Void) {
        routingChangedHandler = handler
    }

    /// Set handler for contact update events (called when contacts change)
    public func setContactUpdatedHandler(_ handler: @escaping @Sendable () async -> Void) {
        contactUpdatedHandler = handler
    }

    /// Set handler for new contact discovered events (for posting notifications)
    public func setNewContactDiscoveredHandler(_ handler: @escaping @Sendable (String, UUID, ContactType) async -> Void) {
        newContactDiscoveredHandler = handler
    }

    /// Set handler for contact sync requests (called when ADVERT received for unknown contact)
    public func setContactSyncRequestHandler(_ handler: @escaping @Sendable (UUID) async -> Void) {
        contactSyncRequestHandler = handler
    }

    /// Set handler for node storage full state changes (called when 0x90 or 0x8F push received)
    public func setNodeStorageFullChangedHandler(_ handler: @escaping @Sendable (Bool) async -> Void) {
        nodeStorageFullChangedHandler = handler
    }

    /// Set handler for contact deleted cleanup (called when device auto-deletes via 0x8F)
    public func setContactDeletedCleanupHandler(_ handler: @escaping @Sendable (UUID, Data) async -> Void) {
        contactDeletedCleanupHandler = handler
    }

    // MARK: - Event Monitoring

    /// Start monitoring MeshCore events for advertisement-related notifications
    public func startEventMonitoring(deviceID: UUID) {
        eventMonitorTask?.cancel()
        currentDeviceID = deviceID

        eventMonitorTask = Task { [weak self] in
            guard let self else { return }
            let events = await session.events()

            for await event in events {
                guard !Task.isCancelled else { break }
                await self.handleEvent(event, deviceID: deviceID)
            }
        }
    }

    /// Stop monitoring events
    public func stopEventMonitoring() {
        eventMonitorTask?.cancel()
        eventMonitorTask = nil
        currentDeviceID = nil
    }

    /// Toggle deferred contact fetching during sync.
    public func setSyncingContacts(_ isSyncing: Bool) async {
        isSyncingContacts = isSyncing
        if !isSyncing {
            await fetchPendingUnknownContacts()
        }
    }

    /// Handle incoming MeshCore event
    private func handleEvent(_ event: MeshEvent, deviceID: UUID) async {
        switch event {
        case .advertisement(let publicKey):
            await handleAdvertEvent(publicKey: publicKey, deviceID: deviceID)

        case .newContact(let contact):
            await handleNewAdvertEvent(contact: contact, deviceID: deviceID)

        case .pathUpdate(let publicKey):
            await handlePathUpdatedEvent(publicKey: publicKey, deviceID: deviceID)

        case .pathResponse(let result):
            await handlePathDiscoveryResponse(result: result, deviceID: deviceID)

        case .traceData(let traceInfo):
            await handleTraceData(traceInfo: traceInfo, deviceID: deviceID)

        case .rxLogData(let logData) where logData.payloadType == .trace:
            if logData.packetPayload.count >= 4, let snr = logData.snr {
                let tag = logData.packetPayload.readUInt32LE(at: 0)
                traceLocalSnr[tag] = snr
                let remoteSnr: Double? = logData.pathNodes.last.map {
                    Double(Int8(bitPattern: $0)) / 4.0
                }
                await MainActor.run {
                    var userInfo: [String: Any] = ["tag": tag, "localSnr": snr, "deviceID": deviceID]
                    if let remoteSnr {
                        userInfo["remoteSnr"] = remoteSnr
                    }
                    NotificationCenter.default.post(
                        name: .rxLogTraceReceived,
                        object: nil,
                        userInfo: userInfo
                    )
                }
            }

        case .contactDeleted(let publicKey):
            await handleContactDeletedEvent(publicKey: publicKey, deviceID: deviceID)

        case .contactsFull:
            await handleContactsFullEvent()

        default:
            break
        }
    }

    // MARK: - Send Advertisement

    /// Send self advertisement to the mesh network
    /// - Parameter flood: If true, sends flood advertisement (reaches all nodes).
    ///                   If false, sends zero-hop advertisement (direct only).
    public func sendSelfAdvertisement(flood: Bool) async throws {
        do {
            try await session.sendAdvertisement(flood: flood)
        } catch let error as MeshCoreError {
            throw AdvertisementError.sessionError(error)
        }
    }

    // MARK: - Update Node Name

    /// Set the node's advertised name
    /// - Parameter name: The name to advertise (max 31 characters)
    public func setAdvertName(_ name: String) async throws {
        do {
            try await session.setName(name)
        } catch let error as MeshCoreError {
            throw AdvertisementError.sessionError(error)
        }
    }

    // MARK: - Update Location

    /// Set the node's advertised GPS coordinates
    /// - Parameters:
    ///   - latitude: Latitude in degrees (-90 to 90)
    ///   - longitude: Longitude in degrees (-180 to 180)
    public func setAdvertLocation(latitude: Double, longitude: Double) async throws {
        do {
            try await session.setCoordinates(latitude: latitude, longitude: longitude)
        } catch let error as MeshCoreError {
            throw AdvertisementError.sessionError(error)
        }
    }

    // MARK: - Private Event Handlers

    /// Handle advertisement event - Existing contact updated
    private func handleAdvertEvent(publicKey: Data, deviceID: UUID) async {
        let pubKeyHex = publicKey.map { String(format: "%02X", $0) }.joined()
        logger.debug("Advert event for \(pubKeyHex)")

        let timestamp = UInt32(Date().timeIntervalSince1970)

        do {
            if let contact = try await dataStore.fetchContact(deviceID: deviceID, publicKey: publicKey) {
                // Create a modified version with updated timestamp
                let frame = ContactFrame(
                    publicKey: contact.publicKey,
                    type: contact.type,
                    flags: contact.flags,
                    outPathLength: contact.outPathLength,
                    outPath: contact.outPath,
                    name: contact.name,
                    lastAdvertTimestamp: timestamp,
                    latitude: contact.latitude,
                    longitude: contact.longitude,
                    lastModified: UInt32(Date().timeIntervalSince1970)
                )
                _ = try await dataStore.saveContact(deviceID: deviceID, from: frame)

                // Also track in DiscoveredNode for Discover page visibility
                _ = try? await dataStore.upsertDiscoveredNode(deviceID: deviceID, from: frame)

                advertHandler?(frame)

                // Notify UI of contact update
                await contactUpdatedHandler?()
            } else {
                if isSyncingContacts {
                    pendingUnknownContactKeys.insert(publicKey)
                    logger.info("ADVERT received for unknown contact during sync - deferring fetch")
                } else {
                    // Unknown contact - device has it but we don't (auto-add mode)
                    // Fetch just this contact from device and notify
                    logger.info("ADVERT received for unknown contact - fetching from device")
                    do {
                        if let meshContact = try await session.getContact(publicKey: publicKey) {
                            let frame = meshContact.toContactFrame()
                            let contactID = try await dataStore.saveContact(deviceID: deviceID, from: frame)

                            // Also track in DiscoveredNode for Discover page visibility
                            _ = try? await dataStore.upsertDiscoveredNode(deviceID: deviceID, from: frame)

                            let contactName = meshContact.advertisedName.isEmpty ? "Unknown Contact" : meshContact.advertisedName
                            let contactType = ContactType(rawValue: meshContact.type) ?? .chat
                            await newContactDiscoveredHandler?(contactName, contactID, contactType)
                        }
                    } catch {
                        logger.error("Failed to fetch new contact: \(error.localizedDescription)")
                    }
                    await contactSyncRequestHandler?(deviceID)
                }
            }
        } catch {
            logger.error("Error handling advert event: \(error.localizedDescription)")
        }
    }

    private func fetchPendingUnknownContacts() async {
        guard !pendingUnknownContactKeys.isEmpty else { return }
        guard let deviceID = currentDeviceID else {
            logger.warning("No device ID available to fetch pending contacts")
            return
        }

        let pendingKeys = pendingUnknownContactKeys
        pendingUnknownContactKeys.removeAll()

        for publicKey in pendingKeys {
            do {
                if let meshContact = try await session.getContact(publicKey: publicKey) {
                    let frame = meshContact.toContactFrame()
                    let contactID = try await dataStore.saveContact(deviceID: deviceID, from: frame)

                    // Also track in DiscoveredNode for Discover page visibility
                    _ = try? await dataStore.upsertDiscoveredNode(deviceID: deviceID, from: frame)

                    let contactName = meshContact.advertisedName.isEmpty ? "Unknown Contact" : meshContact.advertisedName
                    let contactType = ContactType(rawValue: meshContact.type) ?? .chat
                    await newContactDiscoveredHandler?(contactName, contactID, contactType)
                    await contactSyncRequestHandler?(deviceID)
                }
            } catch {
                pendingUnknownContactKeys.insert(publicKey)
                logger.error("Failed to fetch deferred contact: \(error.localizedDescription)")
            }
        }
    }

    /// Handle new advertisement event - New contact discovered (manual add mode)
    private func handleNewAdvertEvent(contact: MeshContact, deviceID: UUID) async {
        let contactFrame = contact.toContactFrame()

        do {
            let (node, isNew) = try await dataStore.upsertDiscoveredNode(deviceID: deviceID, from: contactFrame)
            advertHandler?(contactFrame)

            // Notify UI of discovered node update
            await contactUpdatedHandler?()

            // Only post notification for NEW discoveries (not repeat adverts from same contact)
            if isNew {
                let contactName = node.name
                let contactType = node.nodeType
                await newContactDiscoveredHandler?(contactName, node.id, contactType)
            }
        } catch {
            logger.error("Error handling new advert event: \(error.localizedDescription)")
        }
    }

    /// Handle path updated event - Contact path changed
    private func handlePathUpdatedEvent(publicKey: Data, deviceID: UUID) async {
        let pubKeyHex = publicKey.map { String(format: "%02X", $0) }.joined()
        logger.debug("Path updated event for \(pubKeyHex)")

        do {
            // Fetch fresh contact from device (includes updated path)
            guard let meshContact = try await session.getContact(publicKey: publicKey) else {
                logger.warning("Contact not found on device for public key \(pubKeyHex)")
                return
            }

            // Persist updated routing info
            let frame = meshContact.toContactFrame()
            _ = try await dataStore.saveContact(deviceID: deviceID, from: frame)

            logger.debug("Refreshed contact path: \(meshContact.advertisedName.isEmpty ? "unnamed" : meshContact.advertisedName)")

            // Notify UI of contact update
            await contactUpdatedHandler?()

        } catch {
            logger.error("Error refreshing contact path: \(error.localizedDescription)")
        }
    }

    /// Handle path discovery response event
    private func handlePathDiscoveryResponse(result: PathInfo, deviceID: UUID) async {
        // Debug logging for path discovery
        let outPathHex = result.outPath.map { String(format: "%02X", $0) }.joined(separator: " → ")
        let inPathHex = result.inPath.map { String(format: "%02X", $0) }.joined(separator: " → ")
        let pubKeyHex = result.publicKeyPrefix.prefix(3).map { String(format: "%02X", $0) }.joined()
        logger.info("Path discovery response for \(pubKeyHex)... - Outbound: \(result.outPath.count) hops (\(outPathHex.isEmpty ? "direct" : outPathHex)), Inbound: \(result.inPath.count) hops (\(inPathHex.isEmpty ? "direct" : inPathHex))")

        do {
            // Update contact with discovered outbound path (inbound is handled by firmware)
            if let contact = try await dataStore.fetchContact(deviceID: deviceID, publicKeyPrefix: result.publicKeyPrefix) {
                let wasFlood = contact.isFloodRouted  // Capture BEFORE database write

                let pathLength = Int8(result.outPath.count)
                let frame = ContactFrame(
                    publicKey: contact.publicKey,
                    type: contact.type,
                    flags: contact.flags,
                    outPathLength: pathLength,
                    outPath: result.outPath,
                    name: contact.name,
                    lastAdvertTimestamp: contact.lastAdvertTimestamp,
                    latitude: contact.latitude,
                    longitude: contact.longitude,
                    lastModified: UInt32(Date().timeIntervalSince1970)
                )
                _ = try await dataStore.saveContact(deviceID: deviceID, from: frame)

                // Path discovery success = we have a direct route now (not flood)
                let isNowFlood = false

                // Notify UI if routing status changed (flood → direct after path discovery)
                if wasFlood && !isNowFlood {
                    await routingChangedHandler?(contact.id, isNowFlood)
                }
            }

            pathDiscoveryHandler?(result)
        } catch {
            logger.error("Error handling path discovery response: \(error.localizedDescription)")
        }
    }

    /// Handle trace data response
    private func handleTraceData(traceInfo: TraceInfo, deviceID: UUID) async {
        let localSnr = traceLocalSnr.removeValue(forKey: traceInfo.tag)
        logger.info("Received trace data: tag=\(traceInfo.tag), hops=\(traceInfo.path.count)")
        await MainActor.run {
            var userInfo: [String: Any] = ["traceInfo": traceInfo, "deviceID": deviceID]
            if let localSnr {
                userInfo["localSnr"] = localSnr
            }
            NotificationCenter.default.post(
                name: .traceDataReceived,
                object: nil,
                userInfo: userInfo
            )
        }
    }

    /// Handle contact deleted event (0x8F) - device auto-deleted a contact via overwrite oldest
    private func handleContactDeletedEvent(publicKey: Data, deviceID: UUID) async {
        let pubKeyHex = publicKey.prefix(6).map { String(format: "%02X", $0) }.joined()
        logger.info("Contact deleted by device: \(pubKeyHex)...")

        do {
            // Fetch contact by publicKey to get its UUID
            guard let contact = try await dataStore.fetchContact(deviceID: deviceID, publicKey: publicKey) else {
                logger.warning("Contact not found in local database for deletion: \(pubKeyHex)...")
                return
            }

            let contactID = contact.id

            // Delete associated messages first
            try await dataStore.deleteMessagesForContact(contactID: contactID)

            // Delete the contact
            try await dataStore.deleteContact(id: contactID)
            logger.debug("Deleted contact from local database")

            // Trigger cleanup (notifications, badge, session)
            await contactDeletedCleanupHandler?(contactID, publicKey)

            // Storage now has room - clear the full flag
            await nodeStorageFullChangedHandler?(false)

            // Notify UI to refresh contacts list
            await contactUpdatedHandler?()
        } catch {
            logger.error("Failed to delete contact: \(error.localizedDescription)")
        }
    }

    /// Handle contacts full event (0x90) - device storage is full
    private func handleContactsFullEvent() async {
        logger.warning("Device node storage is full")
        await nodeStorageFullChangedHandler?(true)
    }
}
