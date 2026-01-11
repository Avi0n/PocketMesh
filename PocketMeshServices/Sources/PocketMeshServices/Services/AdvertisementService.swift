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
    /// Parameters: contactName, contactID
    private var newContactDiscoveredHandler: (@Sendable (String, UUID) async -> Void)?

    /// Handler for contact sync request events (when ADVERT received for unknown contact)
    private var contactSyncRequestHandler: (@Sendable (UUID) async -> Void)?

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
    public func setNewContactDiscoveredHandler(_ handler: @escaping @Sendable (String, UUID) async -> Void) {
        newContactDiscoveredHandler = handler
    }

    /// Set handler for contact sync requests (called when ADVERT received for unknown contact)
    public func setContactSyncRequestHandler(_ handler: @escaping @Sendable (UUID) async -> Void) {
        contactSyncRequestHandler = handler
    }

    // MARK: - Event Monitoring

    /// Start monitoring MeshCore events for advertisement-related notifications
    public func startEventMonitoring(deviceID: UUID) {
        eventMonitorTask?.cancel()

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
                advertHandler?(frame)

                // Notify UI of contact update
                await contactUpdatedHandler?()
            } else {
                // Unknown contact - device has it but we don't (auto-add mode)
                // Fetch just this contact from device and notify
                logger.info("ADVERT received for unknown contact - fetching from device")
                do {
                    if let meshContact = try await session.getContact(publicKey: publicKey) {
                        let frame = meshContact.toContactFrame()
                        let contactID = try await dataStore.saveContact(deviceID: deviceID, from: frame)
                        let contactName = meshContact.advertisedName ?? "Unknown Contact"
                        await newContactDiscoveredHandler?(contactName, contactID)
                    }
                } catch {
                    logger.error("Failed to fetch new contact: \(error.localizedDescription)")
                }
                await contactSyncRequestHandler?(deviceID)
            }
        } catch {
            logger.error("Error handling advert event: \(error.localizedDescription)")
        }
    }

    /// Handle new advertisement event - New contact discovered (manual add mode)
    private func handleNewAdvertEvent(contact: MeshContact, deviceID: UUID) async {
        let contactFrame = contact.toContactFrame()

        do {
            let (contactID, isNew) = try await dataStore.saveDiscoveredContact(deviceID: deviceID, from: contactFrame)
            advertHandler?(contactFrame)

            // Notify UI of contact update
            await contactUpdatedHandler?()

            // Only post notification for NEW discoveries (not repeat adverts from same contact)
            if isNew {
                let savedContact = try? await dataStore.fetchContact(id: contactID)
                let contactName = savedContact?.displayName ?? "Unknown Contact"
                await newContactDiscoveredHandler?(contactName, contactID)
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

            logger.debug("Refreshed contact path: \(meshContact.advertisedName ?? "unnamed")")

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
        logger.info("Received trace data: tag=\(traceInfo.tag), hops=\(traceInfo.path.count)")
        // Post notification for ViewModel to handle
        await MainActor.run {
            NotificationCenter.default.post(
                name: .traceDataReceived,
                object: nil,
                userInfo: ["traceInfo": traceInfo, "deviceID": deviceID]
            )
        }
    }
}
