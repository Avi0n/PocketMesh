import Testing
import Foundation
import MeshCoreTestSupport
@testable import PocketMeshServices

@Suite("SyncCoordinator Message Handler Tests")
@MainActor
struct SyncCoordinatorMessageHandlerTests {

    // MARK: - Test Helpers

    private func createTestDataStore(deviceID: UUID) async throws -> PersistenceStore {
        let container = try PersistenceStore.createContainer(inMemory: true)
        let store = PersistenceStore(modelContainer: container)
        let device = DeviceDTO.testDevice(id: deviceID, nodeName: "TestNode")
        try await store.saveDevice(device)
        return store
    }

    private func createTestServices() async throws -> (MeshCoreSession, ServiceContainer) {
        let transport = SimulatorMockTransport()
        let session = MeshCoreSession(transport: transport)
        let services = try await ServiceContainer.forTesting(session: session)
        return (session, services)
    }

    // MARK: - parseChannelMessage Tests

    @Test("parseChannelMessage parses standard 'Name: text' format")
    func parseStandardFormat() {
        let (sender, text) = SyncCoordinator.parseChannelMessage("NodeAlpha: Hello world")
        #expect(sender == "NodeAlpha")
        #expect(text == "Hello world")
    }

    @Test("parseChannelMessage handles multiple colons")
    func parseMultipleColons() {
        let (sender, text) = SyncCoordinator.parseChannelMessage("Node: time is 12:30:00")
        #expect(sender == "Node")
        #expect(text == "time is 12:30:00")
    }

    @Test("parseChannelMessage returns nil sender for text without colon")
    func parseNoColon() {
        let (sender, text) = SyncCoordinator.parseChannelMessage("just plain text")
        #expect(sender == nil)
        #expect(text == "just plain text")
    }

    @Test("parseChannelMessage returns nil sender for empty string")
    func parseEmptyString() {
        let (sender, text) = SyncCoordinator.parseChannelMessage("")
        #expect(sender == nil)
        #expect(text == "")
    }

    @Test("parseChannelMessage handles colon only — split omits empty subsequences")
    func parseColonOnly() {
        let (sender, text) = SyncCoordinator.parseChannelMessage(":")
        #expect(sender == nil)
        #expect(text == ":")
    }

    @Test("parseChannelMessage trims whitespace from sender and text")
    func parseTrimsWhitespace() {
        let (sender, text) = SyncCoordinator.parseChannelMessage("  NodeName  :  hello there  ")
        #expect(sender == "NodeName")
        #expect(text == "hello there")
    }

    @Test("parseChannelMessage handles colon at start — leading empty part omitted by split")
    func parseColonAtStart() {
        let (sender, text) = SyncCoordinator.parseChannelMessage(": some text")
        #expect(sender == nil)
        #expect(text == ": some text")
    }

    @Test("parseChannelMessage handles emoji in name")
    func parseEmojiInName() {
        let (sender, text) = SyncCoordinator.parseChannelMessage("Node🔥: hello")
        #expect(sender == "Node🔥")
        #expect(text == "hello")
    }

    @Test("parseChannelMessage handles unicode characters")
    func parseUnicode() {
        let (sender, text) = SyncCoordinator.parseChannelMessage("Ñoño: café time")
        #expect(sender == "Ñoño")
        #expect(text == "café time")
    }

    @Test("parseChannelMessage handles text with only sender and colon — trailing empty part omitted")
    func parseSenderColonNoText() {
        let (sender, text) = SyncCoordinator.parseChannelMessage("NodeName:")
        #expect(sender == nil)
        #expect(text == "NodeName:")
    }

    // MARK: - Blocked Sender Cache Tests

    @Test("isBlockedSender returns false for empty cache")
    func blockedCacheEmptyReturnsFalse() async {
        let coordinator = SyncCoordinator()
        let result = await coordinator.isBlockedSender("SomeNode")
        #expect(!result)
    }

    @Test("refreshBlockedContactsCache loads blocked contacts by name")
    func refreshBlockedCacheLoads() async throws {
        let coordinator = SyncCoordinator()
        let deviceID = UUID()
        let dataStore = try await createTestDataStore(deviceID: deviceID)

        let blockedContact = ContactDTO.testContact(
            deviceID: deviceID,
            name: "BlockedPerson",
            isBlocked: true
        )
        try await dataStore.saveContact(blockedContact)

        await coordinator.refreshBlockedContactsCache(deviceID: deviceID, dataStore: dataStore)

        let result = await coordinator.isBlockedSender("BlockedPerson")
        #expect(result, "Blocked contact name should be in cache")
    }

    @Test("refreshBlockedContactsCache does not cache non-blocked contacts")
    func refreshBlockedCacheIgnoresUnblocked() async throws {
        let coordinator = SyncCoordinator()
        let deviceID = UUID()
        let dataStore = try await createTestDataStore(deviceID: deviceID)

        let normalContact = ContactDTO.testContact(
            deviceID: deviceID,
            name: "NormalPerson",
            isBlocked: false
        )
        try await dataStore.saveContact(normalContact)

        await coordinator.refreshBlockedContactsCache(deviceID: deviceID, dataStore: dataStore)

        let result = await coordinator.isBlockedSender("NormalPerson")
        #expect(!result, "Non-blocked contact name should not be in cache")
    }

    @Test("refreshBlockedContactsCache replaces previous cache")
    func refreshBlockedCacheReplaces() async throws {
        let coordinator = SyncCoordinator()
        let deviceID = UUID()
        let dataStore = try await createTestDataStore(deviceID: deviceID)

        // First: add a blocked contact
        let contact = ContactDTO.testContact(
            id: UUID(),
            deviceID: deviceID,
            name: "WasBlocked",
            isBlocked: true
        )
        try await dataStore.saveContact(contact)
        await coordinator.refreshBlockedContactsCache(deviceID: deviceID, dataStore: dataStore)
        #expect(await coordinator.isBlockedSender("WasBlocked"))

        // Delete the contact and refresh — cache should be empty
        try await dataStore.deleteContact(id: contact.id)
        await coordinator.refreshBlockedContactsCache(deviceID: deviceID, dataStore: dataStore)
        #expect(await !coordinator.isBlockedSender("WasBlocked"))
    }

    @Test("isBlockedSender returns false for nil name")
    func blockedSenderNilReturnsFalse() async {
        let coordinator = SyncCoordinator()
        let result = await coordinator.isBlockedSender(nil)
        #expect(!result)
    }

    @Test("blockedSenderNames returns snapshot of cached names")
    func blockedSenderNamesReturnsSnapshot() async throws {
        let coordinator = SyncCoordinator()
        let deviceID = UUID()
        let dataStore = try await createTestDataStore(deviceID: deviceID)

        let blocked1 = ContactDTO.testContact(deviceID: deviceID, name: "Blocked1", isBlocked: true)
        let blocked2 = ContactDTO.testContact(deviceID: deviceID, name: "Blocked2", isBlocked: true)
        try await dataStore.saveContact(blocked1)
        try await dataStore.saveContact(blocked2)

        await coordinator.refreshBlockedContactsCache(deviceID: deviceID, dataStore: dataStore)

        let names = await coordinator.blockedSenderNames()
        #expect(names.contains("Blocked1"))
        #expect(names.contains("Blocked2"))
    }

    // MARK: - Handler Wiring Smoke Tests

    @Test("wireMessageHandlers completes without error")
    func wireMessageHandlersSmoke() async throws {
        let coordinator = SyncCoordinator()
        let deviceID = UUID()
        let (_, services) = try await createTestServices()
        try await services.dataStore.saveDevice(DeviceDTO.testDevice(id: deviceID, nodeName: "TestNode"))

        await coordinator.wireMessageHandlers(services: services, deviceID: deviceID)
    }

    @Test("wireDiscoveryHandlers completes without error")
    func wireDiscoveryHandlersSmoke() async throws {
        let coordinator = SyncCoordinator()
        let deviceID = UUID()
        let (_, services) = try await createTestServices()

        await coordinator.wireDiscoveryHandlers(services: services, deviceID: deviceID)
    }

}
