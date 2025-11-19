import SwiftData
import Foundation

@MainActor
public final class PersistenceController {

    public static let shared = PersistenceController()

    public let container: ModelContainer

    private init() {
        let schema = Schema([
            Device.self,
            Contact.self,
            Message.self,
            Channel.self
        ])

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        do {
            container = try ModelContainer(for: schema, configurations: [configuration])

            // Seed test data for development
            #if DEBUG
            seedTestDataContacts()
            #endif
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    /// Seed test contacts for development and testing
    private func seedTestDataContacts() {
        Task {
            let contactRepository = ContactRepository(modelContext: container.mainContext)

            do {
                // Check if we already have test contacts
                let existingContacts = try await contactRepository.getAllContacts()
                let hasTestContacts = existingContacts.contains { contact in
                    contact.name.contains("Seattle") && contact.isManuallyAdded
                }

                guard !hasTestContacts else {
                    print("Test contacts already exist, skipping seeding")
                    return
                }

                print("Seeding test contacts...")

                // Seattle Repeater Alpha - Downtown Seattle
                let seattleRepeaterKey = generateTestPublicKey(for: 1)
                _ = try await contactRepository.createContact(
                    publicKey: seattleRepeaterKey,
                    name: "Seattle Repeater Alpha",
                    type: .repeater,
                    latitude: 47.6062,
                    longitude: -122.3321,
                    isManuallyAdded: true
                )

                // Seattle Room Hub - Space Needle area
                let seattleRoomKey = generateTestPublicKey(for: 2)
                _ = try await contactRepository.createContact(
                    publicKey: seattleRoomKey,
                    name: "Seattle Room Hub",
                    type: .room,
                    latitude: 47.6205,
                    longitude: -122.3493,
                    isManuallyAdded: true
                )

                // Seattle Companion - Pioneer Square
                let seattleCompanionKey = generateTestPublicKey(for: 3)
                _ = try await contactRepository.createContact(
                    publicKey: seattleCompanionKey,
                    name: "Seattle Companion",
                    type: .chat,
                    latitude: 47.5900,
                    longitude: -122.3310,
                    isManuallyAdded: true
                )

                try await contactRepository.save()
                print("Successfully seeded 3 test contacts in Seattle area")

            } catch {
                print("Failed to seed test contacts: \(error)")
            }
        }
    }

    /// Generate a deterministic test public key for consistent testing
    private func generateTestPublicKey(for identifier: Int) -> Data {
        var key = Data(count: 32)

        // Create a deterministic key based on the identifier
        for i in 0..<32 {
            key[i] = UInt8((identifier * 31 + i * 7) % 256)
        }

        return key
    }

    /// Create an in-memory container for testing
    static func preview() -> ModelContainer {
        let schema = Schema([
            Device.self,
            Contact.self,
            Message.self,
            Channel.self
        ])

        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])

            // Add sample data for previews
            let context = container.mainContext
            let device = Device(
                publicKey: Data(repeating: 0x01, count: 32),
                name: "Test Device",
                firmwareVersion: "1.0.0",
                radioFrequency: 915_000_000,
                radioBandwidth: 125_000,
                radioSpreadingFactor: 7,
                radioCodingRate: 5,
                txPower: 20
            )
            context.insert(device)

            return container
        } catch {
            fatalError("Failed to create preview container: \(error)")
        }
    }
}
