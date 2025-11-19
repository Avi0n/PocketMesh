import Foundation
import SwiftData
import CoreLocation
import OSLog

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
                guard let self = self else { return }

                switch pushCode {
                case PushCode.advert.rawValue:
                    await self.handleAdvertisementReceived(payload)

                case PushCode.newAdvert.rawValue:
                    await self.handleNewAdvertisement(payload)

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
            altitude: altitude
        )
    }

    /// Sync contacts from device with timestamp watermarking
    func syncContacts(device: Device) async throws {
        logger.info("Syncing contacts from device")

        // Get most recent contact modification timestamp
        let devicePublicKey = device.publicKey
        let descriptor = FetchDescriptor<Contact>(
            predicate: #Predicate { $0.device?.publicKey == devicePublicKey },
            sortBy: [SortDescriptor(\.lastModified, order: .reverse)]
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
            predicate: #Predicate { $0.publicKey == publicKey }
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
                device: device
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
        // In manual add mode - notify UI for user confirmation
        logger.info("New advertisement requires user confirmation")
        // TODO: Post notification for UI to show confirmation dialog
    }
}

