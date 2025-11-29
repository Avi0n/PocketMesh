import CoreLocation
import Foundation
import OSLog
import SwiftData

private let logger = Logger(subsystem: "com.pocketmesh.app", category: "Advertisement")

@MainActor
public final class AdvertisementService: ObservableObject {
    private let `protocol`: MeshCoreProtocol
    private let modelContext: ModelContext

    @Published var isAdvertising = false

    public init(protocol: MeshCoreProtocol, modelContext: ModelContext) {
        self.protocol = `protocol`
        self.modelContext = modelContext

        // Subscribe to advertisement push notifications
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.protocol.subscribeToPushNotifications { [weak self] pushCode, payload in
                Task { @MainActor [weak self] in
                    guard let self else { return }

                    logger.debug("Received push notification: \(pushCode) (0x\(String(pushCode, radix: 16)))")

                    switch pushCode {
                    case PushCode.advert.rawValue:
                        logger.debug("Handling advert push notification")
                        await handleAdvertisementReceived(payload)

                    case PushCode.newAdvert.rawValue:
                        logger.debug("Handling new advertisement push notification")
                        await handleNewAdvertisement(payload)

                    case PushCode.pathUpdated.rawValue:
                        await handlePathUpdated(payload)

                    default:
                        logger.debug("Ignoring push notification: \(pushCode)")
                    }
                }
            }
        }
    }

    /// Send self-advertisement (zero-hop or flood)
    public func sendAdvertisement(floodMode: Bool = false) async throws {
        logger.info("Sending advertisement (flood: \(floodMode))")

        try await `protocol`.sendSelfAdvertisement(floodMode: floodMode)
        isAdvertising = true

        // Reset after a delay
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            await MainActor.run {
                self.isAdvertising = false
            }
        }
    }

    /// Set advertisement name
    func setAdvertisementName(_ name: String) async throws {
        logger.info("Setting advertisement name: \(name)")
        try await `protocol`.setAdvertisementName(name)
    }

    /// Set advertisement location
    func setAdvertisementLocation(_ coordinate: CLLocationCoordinate2D, altitude: Int32 = 0) async throws {
        logger.info("Setting advertisement location: \(coordinate.latitude), \(coordinate.longitude)")
        try await `protocol`.setAdvertisementLocation(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            altitude: altitude,
        )
    }

    /// Sync contacts from device with timestamp watermarking
    func syncContacts(device: Device) async throws {
        logger.info("Syncing contacts from device")
        logger.debug("Device public key: \(device.publicKey.hexString)")

        // Get most recent contact modification timestamp
        let devicePublicKey = device.publicKey
        let descriptor = FetchDescriptor<Contact>(
            predicate: #Predicate { $0.device?.publicKey == devicePublicKey },
            sortBy: [SortDescriptor(\.lastModified, order: .reverse)],
        )

        let mostRecent = try modelContext.fetch(descriptor).first
        let since = mostRecent?.lastModified
        logger.debug("Most recent contact modification: \(since?.description ?? "nil")")

        // Request contact sync
        logger.debug("About to call protocol.getContacts")
        let contacts = try await `protocol`.getContacts(since: since)

        logger.info("Received \(contacts.count) contact updates")
        logger.debug("Contact sync completed - processing \(contacts.count) contacts")

        do {
            if contacts.isEmpty {
                logger.warning("Contacts array is empty despite received count!")
            } else {
                logger.debug("First contact in array: \(contacts.first?.name ?? "unknown")")
            }

            for (index, contactData) in contacts.enumerated() {
                logger.debug("Processing contact \(index + 1)/\(contacts.count): \(contactData.name) with key \(contactData.publicKey.hexString)")
                try createOrUpdateContact(from: contactData, device: device)
            }

            logger.debug("Saving model context after contact sync")
            try modelContext.save()
            logger.debug("Contact sync and save completed successfully")
        } catch {
            logger.error("Error during contact processing: \(error)")
            throw error
        }
    }

    private func createOrUpdateContact(from data: ContactData, device: Device) throws {
        let publicKey = data.publicKey
        let descriptor = FetchDescriptor<Contact>(
            predicate: #Predicate { $0.publicKey == publicKey },
        )

        if let existing = try modelContext.fetch(descriptor).first {
            // Update existing
            logger.debug("Updating existing contact: \(existing.name) with key \(publicKey.hexString)")
            existing.name = data.name
            existing.type = data.type
            existing.lastAdvertisement = data.lastAdvertisement
            existing.lastModified = data.lastModified
            existing.latitude = data.latitude
            existing.longitude = data.longitude
            existing.outPathLength = data.outPathLength
            existing.outPath = data.outPath
        } else {
            // Create new
            logger.debug("Creating new contact: \(data.name) with key \(publicKey.hexString)")
            let contact = Contact(
                publicKey: data.publicKey,
                name: data.name,
                type: data.type,
                device: device,
            )
            contact.lastAdvertisement = data.lastAdvertisement
            contact.lastModified = data.lastModified
            contact.latitude = data.latitude
            contact.longitude = data.longitude
            contact.outPathLength = data.outPathLength
            contact.outPath = data.outPath

            modelContext.insert(contact)
            logger.debug("Inserted new contact into model context")
        }
    }

    private func handleAdvertisementReceived(_ payload: Data) async {
        do {
            // Payload is 32-byte public key
            guard payload.count >= 32 else { return }
            let publicKey = payload.prefix(32)

            logger.info("Received advertisement from: \(Data(publicKey).hexString)")

            // Trigger contact sync to get full details
            do {
                if let device = try DeviceRepository(modelContext: modelContext).getActiveDevice() {
                    try await syncContacts(device: device)
                } else {
                    logger.error("No active device found for contact sync")
                }
            } catch {
                logger.error("Failed to sync contacts after advertisement: \(error.localizedDescription)")
            }

        } catch {
            logger.error("Failed to handle advertisement: \(error.localizedDescription)")
        }
    }

    /// Parse contact response frame data from MeshCore writeContactRespFrame()
    /// Expected format: [pushCode:1][publicKey:32][type:1][flags:1][outPathLen:1][outPath:64][name:32][lastAdvertTimestamp:4][gpsLat:4][gpsLon:4][lastMod:4]
    private func parseContactResponseFrame(_ payload: Data) -> (publicKey: Data, type: ContactType, name: String, latitude: Double?, longitude: Double?)? {
        logger.debug("Contact response frame payload size: \(payload.count)")
        guard payload.count >= 116 else { // Minimum expected size for contact response frame with push code
            logger.error("Invalid contact response frame payload size: \(payload.count), expected >= 116")
            return nil
        }

        // Skip push code (1 byte) and extract fields from contact response frame
        let publicKey = payload.subdata(in: 1 ..< 33)
        let contactTypeByte = payload[33]

        // Skip flags (1 byte) and outPathLen (1 byte) and outPath (64 bytes)
        // Name starts at offset 100 (1 + 32 + 1 + 1 + 64 + 1)
        let nameStart = 100
        let nameData = payload.subdata(in: nameStart ..< (nameStart + 32))

        logger.debug("Parsing contact frame: nameStart=\(nameStart), nameData=\(nameData.hexString)")

        // Extract name (null-terminated)
        guard let nameEnd = nameData.firstIndex(of: 0) else {
            logger.error("Invalid name format in contact response frame")
            return nil
        }
        let nameBytes = nameData[0 ..< nameEnd]
        let name = String(data: nameBytes, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? ""

        logger.debug("Parsed name: '\(name)' from bytes: \(nameBytes.hexString)")

        // Extract coordinates if present (after name, 4+4 bytes for lat/lon)
        var latitude: Double?
        var longitude: Double?

        let coordinateStart = nameStart + 32 + 4 // name + lastAdvertTimestamp
        if payload.count >= coordinateStart + 8 {
            let latInt = payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: coordinateStart, as: Int32.self) }
            let lonInt = payload.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: coordinateStart + 4, as: Int32.self) }
            latitude = Double(latInt) / 1_000_000.0
            longitude = Double(lonInt) / 1_000_000.0
        }

        // Convert contact type byte to ContactType enum
        let contactType: ContactType = switch contactTypeByte {
        case 1: .chat
        case 2: .repeater
        case 3: .room
        default: .none
        }

        logger.debug("Parsed contact from push: name='\(name)', type=\(contactType.rawValue), publicKey=\(publicKey.hexString)")

        return (publicKey: publicKey, type: contactType, name: name, latitude: latitude, longitude: longitude)
    }

    private func handleNewAdvertisement(_ payload: Data) async {
        logger.debug("New advertisement received: \(payload.hexString)")
        logger.debug("Payload size: \(payload.count) bytes")

        // Parse advertisement payload using AdvertisementPush model
        do {
            let advertisementPush = try AdvertisementPush.decode(from: payload)

            logger.info("Discovered new advertisement: \(advertisementPush.name) (type: \(advertisementPush.type)) with key prefix \(advertisementPush.publicKeyPrefix.hexString)")

            // Check if we should auto-add or create as pending
            let autoAdd = UserDefaults.standard.bool(forKey: "autoAddContacts")

            // Get device and sync contacts to retrieve full public key
            guard let device = try? DeviceRepository(modelContext: modelContext).getActiveDevice() else {
                logger.error("No active device found for contact sync")
                return
            }

            // Sync contacts to get full public key for this prefix
            do {
                try await syncContacts(device: device)
            } catch {
                logger.error("Failed to sync contacts in handleNewAdvertisement: \(error)")
            }

            // Find contacts with matching prefix added recently (within last 10 seconds)
            await markRecentContactsByPrefix(advertisementPush.publicKeyPrefix, name: advertisementPush.name, isPending: !autoAdd)

            // Update contact with coordinates if available
            if let lat = advertisementPush.latitude, let lon = advertisementPush.longitude {
                // Find the contact with matching prefix and update coordinates
                await updateContactCoordinatesByPrefix(advertisementPush.publicKeyPrefix, latitude: lat, longitude: lon)
            }

            // Post notification if pending
            if !autoAdd {
                NotificationCenter.default.post(
                    name: .newPendingContact,
                    object: nil,
                    userInfo: ["contactName": advertisementPush.name],
                )
            }

        } catch {
            logger.error("Failed to handle new advertisement: \(error.localizedDescription)")
        }
    }

    /// Helper method to mark contacts by prefix
    private func markRecentContactsByPrefix(_ prefix: Data, name: String, isPending: Bool) async {
        let allContacts = (try? modelContext.fetch(FetchDescriptor<Contact>())) ?? []
        logger.debug("Found \(allContacts.count) total contacts, looking for prefix=\(prefix.hexString), name='\(name)'")

        // Find contacts with matching prefix and name added in last 10 seconds
        let cutoff = Date().addingTimeInterval(-10)
        let matchingContacts = allContacts.filter { contact in
            contact.publicKey.prefix(6) == prefix &&
                contact.name == name &&
                contact.lastModified > cutoff
        }

        logger.debug("Found \(matchingContacts.count) matching contacts for prefix=\(prefix.hexString), name='\(name)'")

        for contact in matchingContacts {
            contact.isPending = isPending
            contact.isManuallyAdded = false
            if isPending {
                contact.lastAdvertisement = Date()
            }
            logger.debug("Updated contact: \(contact.name), pending=\(isPending)")
        }

        try? modelContext.save()

        if isPending {
            logger.info("Added contact to pending list: \(name)")
        } else {
            logger.info("Auto-added contact: \(name)")
        }
    }

    /// Helper method to update contact coordinates by public key prefix
    private func updateContactCoordinatesByPrefix(_ prefix: Data, latitude: Double, longitude: Double) async {
        let allContacts = (try? modelContext.fetch(FetchDescriptor<Contact>())) ?? []

        // Find contact with matching public key prefix
        if let contact = allContacts.first(where: { $0.publicKey.prefix(6) == prefix }) {
            contact.latitude = latitude
            contact.longitude = longitude
            contact.lastModified = Date()

            do {
                try modelContext.save()
                logger.debug("Updated coordinates for contact: \(contact.name)")
            } catch {
                logger.error("Failed to update contact coordinates: \(error.localizedDescription)")
            }
        }
    }

    /// Helper method to update contact coordinates (legacy method)
    private func updateContactCoordinates(publicKey: Data, latitude: Double, longitude: Double) async {
        let allContacts = (try? modelContext.fetch(FetchDescriptor<Contact>())) ?? []

        // Find contact with matching public key
        if let contact = allContacts.first(where: { $0.publicKey == publicKey }) {
            contact.latitude = latitude
            contact.longitude = longitude
            contact.lastModified = Date()

            do {
                try modelContext.save()
                logger.debug("Updated coordinates for contact: \(contact.name)")
            } catch {
                logger.error("Failed to update contact coordinates: \(error.localizedDescription)")
            }
        }
    }

    private func handlePathUpdated(_ payload: Data) async {
        guard payload.count >= 32 else {
            logger.error("Invalid pathUpdated payload size: \(payload.count)")
            return
        }

        // Extract public key (first 32 bytes)
        let publicKey = payload.prefix(32)

        logger.info("Path updated for contact: \(Data(publicKey).prefix(6).hexString)")

        // Trigger contact sync to get updated path information
        do {
            if let device = try? DeviceRepository(modelContext: modelContext).getActiveDevice() {
                try await syncContacts(device: device)
            }
        } catch {
            logger.error("Failed to sync contacts after path update: \(error.localizedDescription)")
        }
    }
}
