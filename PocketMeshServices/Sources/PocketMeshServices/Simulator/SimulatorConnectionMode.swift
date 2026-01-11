import Foundation
import SwiftData
import OSLog

/// Connection mode for simulator and demo mode on device.
/// Provides mock data and simulated connections without requiring real hardware.
@MainActor
public final class SimulatorConnectionMode {

    private let logger = PersistentLogger(subsystem: "com.pocketmesh.services", category: "SimulatorConnectionMode")

    /// Whether simulator is "connected"
    public private(set) var isConnected = false

    /// The simulated device
    public var device: DeviceDTO? {
        isConnected ? MockDataProvider.simulatorDevice : nil
    }

    public init() {}

    /// Simulates connecting to the simulator device
    public func connect() async {
        logger.info("Simulator: connecting to mock device")
        try? await Task.sleep(for: .milliseconds(200))  // Brief delay
        isConnected = true
        logger.info("Simulator: connected")
    }

    /// Simulates disconnecting
    public func disconnect() async {
        logger.info("Simulator: disconnecting")
        isConnected = false
    }

    /// Seeds the data store with mock data
    public func seedDataStore(_ dataStore: PersistenceStore) async throws {
        // Save device
        try await dataStore.saveDevice(MockDataProvider.simulatorDevice)

        // Save contacts
        for contact in MockDataProvider.contacts {
            try await dataStore.saveContact(contact)
        }

        // Save messages for each contact
        for contact in MockDataProvider.contacts {
            let messages = MockDataProvider.messages(for: contact.id)
            for message in messages {
                try await dataStore.saveMessage(message)
            }
        }

        logger.info("Simulator: seeded \(MockDataProvider.contacts.count) contacts with messages")
    }
}
