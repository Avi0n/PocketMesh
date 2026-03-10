import Foundation
import SwiftData
import Testing
@testable import PocketMeshServices

@Suite("BlockedChannelSender Persistence Tests")
struct BlockedChannelSenderPersistenceTests {

    // MARK: - Test Helpers

    private func createTestStore() async throws -> PersistenceStore {
        let container = try PersistenceStore.createContainer(inMemory: true)
        return PersistenceStore(modelContainer: container)
    }

    private let deviceID = UUID()

    // MARK: - Save & Fetch

    @Test("Save and fetch round-trip returns the blocked sender")
    func saveAndFetchRoundTrip() async throws {
        let store = try await createTestStore()
        let dto = BlockedChannelSenderDTO(name: "Spammer", deviceID: deviceID)

        try await store.saveBlockedChannelSender(dto)
        let fetched = try await store.fetchBlockedChannelSenders(deviceID: deviceID)

        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Spammer")
        #expect(fetched.first?.deviceID == deviceID)
    }

    // MARK: - Upsert

    @Test("Re-saving same name updates dateBlocked instead of creating duplicate")
    func upsertUpdateDateBlocked() async throws {
        let store = try await createTestStore()
        let earlier = Date.distantPast
        let later = Date.now

        let first = BlockedChannelSenderDTO(name: "Troll", deviceID: deviceID, dateBlocked: earlier)
        try await store.saveBlockedChannelSender(first)

        let second = BlockedChannelSenderDTO(name: "Troll", deviceID: deviceID, dateBlocked: later)
        try await store.saveBlockedChannelSender(second)

        let fetched = try await store.fetchBlockedChannelSenders(deviceID: deviceID)
        #expect(fetched.count == 1)
        #expect(fetched.first?.dateBlocked == later)
    }

    // MARK: - Delete

    @Test("Delete removes the blocked sender entry")
    func deleteRemovesEntry() async throws {
        let store = try await createTestStore()
        let dto = BlockedChannelSenderDTO(name: "BadGuy", deviceID: deviceID)
        try await store.saveBlockedChannelSender(dto)

        try await store.deleteBlockedChannelSender(deviceID: deviceID, name: "BadGuy")
        let fetched = try await store.fetchBlockedChannelSenders(deviceID: deviceID)

        #expect(fetched.isEmpty)
    }

    // MARK: - Device Scoping

    @Test("Fetch returns only senders blocked for the specified device")
    func fetchScopesToDeviceID() async throws {
        let store = try await createTestStore()
        let otherDeviceID = UUID()

        try await store.saveBlockedChannelSender(
            BlockedChannelSenderDTO(name: "Alice", deviceID: deviceID)
        )
        try await store.saveBlockedChannelSender(
            BlockedChannelSenderDTO(name: "Bob", deviceID: otherDeviceID)
        )

        let device1Results = try await store.fetchBlockedChannelSenders(deviceID: deviceID)
        let device2Results = try await store.fetchBlockedChannelSenders(deviceID: otherDeviceID)

        #expect(device1Results.count == 1)
        #expect(device1Results.first?.name == "Alice")
        #expect(device2Results.count == 1)
        #expect(device2Results.first?.name == "Bob")
    }

    // MARK: - Case Insensitivity

    @Test("Name preserves original casing for display")
    func namePreservesOriginalCasing() async throws {
        let store = try await createTestStore()
        let dto = BlockedChannelSenderDTO(name: "Alice", deviceID: deviceID)
        try await store.saveBlockedChannelSender(dto)

        let fetched = try await store.fetchBlockedChannelSenders(deviceID: deviceID)
        #expect(fetched.first?.name == "Alice")
    }

    @Test("Saving same name with different case creates separate entries")
    func caseSensitiveSave() async throws {
        let store = try await createTestStore()

        try await store.saveBlockedChannelSender(
            BlockedChannelSenderDTO(name: "Alice", deviceID: deviceID, dateBlocked: .distantPast)
        )
        try await store.saveBlockedChannelSender(
            BlockedChannelSenderDTO(name: "ALICE", deviceID: deviceID, dateBlocked: .now)
        )

        let fetched = try await store.fetchBlockedChannelSenders(deviceID: deviceID)
        #expect(fetched.count == 2)
    }

    @Test("Delete requires exact case match")
    func caseSensitiveDelete() async throws {
        let store = try await createTestStore()
        try await store.saveBlockedChannelSender(
            BlockedChannelSenderDTO(name: "Alice", deviceID: deviceID)
        )

        try await store.deleteBlockedChannelSender(deviceID: deviceID, name: "ALICE")
        let fetched = try await store.fetchBlockedChannelSenders(deviceID: deviceID)

        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Alice")
    }

    // MARK: - Sort Order

    @Test("Fetch returns senders sorted by most recently blocked first")
    func fetchSortedByDateBlockedDescending() async throws {
        let store = try await createTestStore()
        let oldest = Date(timeIntervalSince1970: 1_000_000)
        let middle = Date(timeIntervalSince1970: 2_000_000)
        let newest = Date(timeIntervalSince1970: 3_000_000)

        try await store.saveBlockedChannelSender(
            BlockedChannelSenderDTO(name: "first", deviceID: deviceID, dateBlocked: oldest)
        )
        try await store.saveBlockedChannelSender(
            BlockedChannelSenderDTO(name: "second", deviceID: deviceID, dateBlocked: newest)
        )
        try await store.saveBlockedChannelSender(
            BlockedChannelSenderDTO(name: "third", deviceID: deviceID, dateBlocked: middle)
        )

        let fetched = try await store.fetchBlockedChannelSenders(deviceID: deviceID)
        #expect(fetched.map(\.name) == ["second", "third", "first"])
    }
}
