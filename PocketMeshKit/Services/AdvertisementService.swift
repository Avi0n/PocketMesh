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
        Task {
            await `protocol`.subscribeToPushNotifications { [weak self] pushCode, payload in
                guard let self else { return }

                switch pushCode {
                case PushCode.advert.rawValue:
                    await handleAdvertisementReceived(payload)

                case PushCode.newAdvert.rawValue:
                    await handleNewAdvertisement(payload)

                case PushCode.pathUpdated.rawValue:
                    await handlePathUpdated(payload)

                default:
                    break
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
    func setAdvertisementLocation(_ coordinate: CLLocationCoordinate2D, altitude: Int16? = nil) async throws {
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

        // Get most recent contact modification timestamp
        let devicePublicKey = device.publicKey
        let descriptor = FetchDescriptor<Contact>(
            predicate: #Predicate { $0.device?.publicKey == devicePublicKey },
            sortBy: [SortDescriptor(\.lastModified, order: .reverse)],
        )

        let mostRecent = try modelContext.fetch(descriptor).first
        let since = mostRecent?.lastModified

        // Request contact sync
        let contacts = try await `protocol`.getContacts(since: since)

        logger.info("Received \(contacts.count) contact updates")

        for contactData in contacts {
            try createOrUpdateContact(from: contactData, device: device)
        }

        try modelContext.save()
    }

    private func createOrUpdateContact(from data: ContactData, device: Device) throws {
        let publicKey = data.publicKey
        let descriptor = FetchDescriptor<Contact>(
            predicate: #Predicate { $0.publicKey == publicKey },
        )

        if let existing = try modelContext.fetch(descriptor).first {
            // Update existing
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
        }
    }

    private func handleAdvertisementReceived(_ payload: Data) async {
        do {
            // Payload is 32-byte public key
            guard payload.count >= 32 else { return }
            let publicKey = payload.prefix(32)

            logger.info("Received advertisement from: \(Data(publicKey).hexString)")

            // Trigger contact sync to get full details
            if let device = try? DeviceRepository(modelContext: modelContext).getActiveDevice() {
                try await syncContacts(device: device)
            }

        } catch {
            logger.error("Failed to handle advertisement: \(error.localizedDescription)")
        }
    }

    private func handleNewAdvertisement(_ payload: Data) async {
        logger.debug("New advertisement received: \(payload.hexString)")

        // Parse advertisement payload
        guard payload.count >= 7 else {
            logger.error("Invalid new advertisement payload size: \(payload.count)")
            return
        }

        // Payload structure (based on PUSH_NEW_ADVERT format):
        // Bytes 0-5: Public key prefix (6 bytes)
        // Byte 6: Contact type (1=companion, 2=repeater, 3=room, 4=sensor)
        // Bytes 7+: UTF-8 name string (rest of payload)

        let publicKeyPrefix = payload.prefix(6)
        let contactTypeByte = payload[6]
        let contactType: ContactType = switch contactTypeByte {
        case 1: .companion
        case 2: .repeater
        case 3: .room
        case 4: .sensor
        default: .none
        }

        let nameData = payload.dropFirst(7)
        guard let name = String(data: nameData, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) else {
            logger.error("Failed to decode contact name from advertisement")
            return
        }

        logger.info("Discovered new contact: \(name) (type: \(contactType.rawValue)) with key prefix \(publicKeyPrefix.hexString)")

        // Check if we should auto-add or create as pending
        let autoAdd = UserDefaults.standard.bool(forKey: "autoAddContacts")

        // Get device and sync contacts to retrieve full public key
        do {
            guard let device = try? DeviceRepository(modelContext: modelContext).getActiveDevice() else {
                logger.error("No active device found for contact sync")
                return
            }

            // Sync contacts to get full public key for this prefix
            try await syncContacts(device: device)

            // Find contacts with matching prefix added recently
            await markRecentContactsByPrefix(publicKeyPrefix, name: name, isPending: !autoAdd)

            // Post notification if pending
            if !autoAdd {
                NotificationCenter.default.post(
                    name: .newPendingContact,
                    object: nil,
                    userInfo: ["contactName": name],
                )
            }

        } catch {
            logger.error("Failed to handle new advertisement: \(error.localizedDescription)")
        }
    }

    /// Helper method to mark contacts by prefix
    private func markRecentContactsByPrefix(_ prefix: Data, name: String, isPending: Bool) async {
        let allContacts = (try? modelContext.fetch(FetchDescriptor<Contact>())) ?? []

        // Find contacts with matching prefix and name added in last 10 seconds
        let cutoff = Date().addingTimeInterval(-10)
        let matchingContacts = allContacts.filter { contact in
            contact.publicKey.prefix(6) == prefix &&
                contact.name == name &&
                contact.lastModified > cutoff
        }

        for contact in matchingContacts {
            contact.isPending = isPending
            contact.isManuallyAdded = false
            if isPending {
                contact.lastAdvertisement = Date()
            }
        }

        try? modelContext.save()

        if isPending {
            logger.info("Added contact to pending list: \(name)")
        } else {
            logger.info("Auto-added contact: \(name)")
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
