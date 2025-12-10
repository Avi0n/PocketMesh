import Testing
import Foundation
import CryptoKit
@testable import PocketMeshKit

@Suite("ChannelService Tests")
struct ChannelServiceTests {

    // MARK: - Test Helpers

    private func createTestTransport() -> TestBLETransport {
        TestBLETransport()
    }

    private func createTestDataStore() async throws -> DataStore {
        let container = try DataStore.createContainer(inMemory: true)
        return DataStore(modelContainer: container)
    }

    private func createChannelInfoResponse(index: UInt8, name: String, secret: Data) -> Data {
        var response = Data([ResponseCode.channelInfo.rawValue])
        response.append(index)

        var nameData = name.data(using: .utf8) ?? Data()
        nameData.append(Data(repeating: 0, count: max(0, 32 - nameData.count)))
        response.append(nameData.prefix(32))

        response.append(secret.prefix(16))

        return response
    }

    private func createErrorResponse(_ error: ProtocolError) -> Data {
        Data([ResponseCode.error.rawValue, error.rawValue])
    }

    // MARK: - Secret Hashing Tests

    @Test("Hash secret produces 16 bytes")
    func hashSecretProduces16Bytes() {
        let secret = ChannelService.hashSecret("test passphrase")
        #expect(secret.count == 16)
    }

    @Test("Hash secret is deterministic")
    func hashSecretIsDeterministic() {
        let secret1 = ChannelService.hashSecret("my secret")
        let secret2 = ChannelService.hashSecret("my secret")
        #expect(secret1 == secret2)
    }

    @Test("Hash secret produces different results for different passphrases")
    func hashSecretProducesDifferentResults() {
        let secret1 = ChannelService.hashSecret("passphrase one")
        let secret2 = ChannelService.hashSecret("passphrase two")
        #expect(secret1 != secret2)
    }

    @Test("Hash empty passphrase produces zero secret")
    func hashEmptyPassphraseProducesZeroSecret() {
        let secret = ChannelService.hashSecret("")
        let expected = Data(repeating: 0, count: 16)
        #expect(secret == expected)
    }

    @Test("Hash secret matches firmware algorithm")
    func hashSecretMatchesFirmwareAlgorithm() {
        // The firmware uses SHA-256 and takes the first 16 bytes
        let passphrase = "TestChannel123"
        let secret = ChannelService.hashSecret(passphrase)

        // Verify by computing SHA-256 directly
        let data = passphrase.data(using: .utf8)!
        let hash = SHA256.hash(data: data)
        let expected = Data(hash.prefix(16))

        #expect(secret == expected)
    }

    @Test("Validate secret accepts 16-byte data")
    func validateSecretAccepts16Bytes() {
        let secret = Data(repeating: 0xAB, count: 16)
        #expect(ChannelService.validateSecret(secret) == true)
    }

    @Test("Validate secret rejects wrong size data")
    func validateSecretRejectsWrongSize() {
        let tooShort = Data(repeating: 0xAB, count: 15)
        let tooLong = Data(repeating: 0xAB, count: 17)
        let empty = Data()

        #expect(ChannelService.validateSecret(tooShort) == false)
        #expect(ChannelService.validateSecret(tooLong) == false)
        #expect(ChannelService.validateSecret(empty) == false)
    }

    // MARK: - Fetch Channel Tests

    @Test("Fetch channel succeeds")
    func fetchChannelSucceeds() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        await transport.setConnectionState(.ready)

        let secret = ChannelService.hashSecret("test")
        await transport.queueResponse(createChannelInfoResponse(index: 1, name: "MyChannel", secret: secret))

        let service = ChannelService(bleTransport: transport, dataStore: dataStore)

        let channelInfo = try await service.fetchChannel(index: 1)

        #expect(channelInfo != nil)
        #expect(channelInfo?.index == 1)
        #expect(channelInfo?.name == "MyChannel")
        #expect(channelInfo?.secret == secret)

        // Verify correct command was sent
        let sentData = await transport.getSentData()
        #expect(sentData.count == 1)
        #expect(sentData[0][0] == CommandCode.getChannel.rawValue)
        #expect(sentData[0][1] == 1)
    }

    @Test("Fetch channel returns nil when not found")
    func fetchChannelReturnsNilWhenNotFound() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        await transport.setConnectionState(.ready)
        await transport.queueResponse(createErrorResponse(.notFound))

        let service = ChannelService(bleTransport: transport, dataStore: dataStore)

        let channelInfo = try await service.fetchChannel(index: 5)

        #expect(channelInfo == nil)
    }

    @Test("Fetch channel fails when not connected")
    func fetchChannelFailsWhenNotConnected() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let service = ChannelService(bleTransport: transport, dataStore: dataStore)

        await #expect(throws: ChannelServiceError.self) {
            _ = try await service.fetchChannel(index: 0)
        }
    }

    @Test("Fetch channel fails with invalid index")
    func fetchChannelFailsWithInvalidIndex() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        await transport.setConnectionState(.ready)

        let service = ChannelService(bleTransport: transport, dataStore: dataStore)

        await #expect(throws: ChannelServiceError.self) {
            _ = try await service.fetchChannel(index: 10)  // Max is 8
        }
    }

    // MARK: - Set Channel Tests

    @Test("Set channel with passphrase succeeds")
    func setChannelWithPassphraseSucceeds() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        await transport.setConnectionState(.ready)
        await transport.queueResponse(Data([ResponseCode.ok.rawValue]))

        let service = ChannelService(bleTransport: transport, dataStore: dataStore)

        try await service.setChannel(deviceID: deviceID, index: 2, name: "Team", passphrase: "secret123")

        // Verify channel was saved locally
        let channel = try await dataStore.fetchChannel(deviceID: deviceID, index: 2)
        #expect(channel != nil)
        #expect(channel?.name == "Team")
        #expect(channel?.secret == ChannelService.hashSecret("secret123"))

        // Verify command was sent correctly
        let sentData = await transport.getSentData()
        #expect(sentData.count == 1)
        #expect(sentData[0][0] == CommandCode.setChannel.rawValue)
        #expect(sentData[0][1] == 2)
    }

    @Test("Set channel with direct secret succeeds")
    func setChannelWithDirectSecretSucceeds() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        let secret = Data((0..<16).map { _ in UInt8.random(in: 0...255) })

        await transport.setConnectionState(.ready)
        await transport.queueResponse(Data([ResponseCode.ok.rawValue]))

        let service = ChannelService(bleTransport: transport, dataStore: dataStore)

        try await service.setChannelWithSecret(deviceID: deviceID, index: 3, name: "Private", secret: secret)

        // Verify channel was saved with exact secret
        let channel = try await dataStore.fetchChannel(deviceID: deviceID, index: 3)
        #expect(channel != nil)
        #expect(channel?.name == "Private")
        #expect(channel?.secret == secret)
    }

    @Test("Set channel fails when not connected")
    func setChannelFailsWhenNotConnected() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        let service = ChannelService(bleTransport: transport, dataStore: dataStore)

        await #expect(throws: ChannelServiceError.self) {
            try await service.setChannel(deviceID: deviceID, index: 1, name: "Test", passphrase: "pass")
        }
    }

    @Test("Set channel fails with invalid index")
    func setChannelFailsWithInvalidIndex() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        await transport.setConnectionState(.ready)

        let service = ChannelService(bleTransport: transport, dataStore: dataStore)

        await #expect(throws: ChannelServiceError.self) {
            try await service.setChannel(deviceID: deviceID, index: 15, name: "Bad", passphrase: "pass")
        }
    }

    @Test("Set channel fails with invalid secret size")
    func setChannelFailsWithInvalidSecretSize() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        await transport.setConnectionState(.ready)

        let service = ChannelService(bleTransport: transport, dataStore: dataStore)

        let badSecret = Data(repeating: 0xAB, count: 10)  // Should be 16

        await #expect(throws: ChannelServiceError.self) {
            try await service.setChannelWithSecret(deviceID: deviceID, index: 1, name: "Bad", secret: badSecret)
        }
    }

    @Test("Set channel notifies update handler")
    func setChannelNotifiesUpdateHandler() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        await transport.setConnectionState(.ready)
        await transport.queueResponse(Data([ResponseCode.ok.rawValue]))

        let service = ChannelService(bleTransport: transport, dataStore: dataStore)

        let receivedChannels = MutableBox<[ChannelDTO]>([])
        await service.setChannelUpdateHandler { channels in
            receivedChannels.value = channels
        }

        try await service.setChannel(deviceID: deviceID, index: 1, name: "Updated", passphrase: "pass")

        #expect(receivedChannels.value.count == 1)
        #expect(receivedChannels.value.first?.name == "Updated")
    }

    // MARK: - Clear Channel Tests

    @Test("Clear channel succeeds")
    func clearChannelSucceeds() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()

        // First create a channel
        let channelInfo = ChannelInfo(
            index: 2,
            name: "ToDelete",
            secret: ChannelService.hashSecret("secret")
        )
        _ = try await dataStore.saveChannel(deviceID: deviceID, from: channelInfo)

        await transport.setConnectionState(.ready)
        await transport.queueResponse(Data([ResponseCode.ok.rawValue]))

        let service = ChannelService(bleTransport: transport, dataStore: dataStore)

        try await service.clearChannel(deviceID: deviceID, index: 2)

        // Verify channel was deleted locally
        let channel = try await dataStore.fetchChannel(deviceID: deviceID, index: 2)
        #expect(channel == nil)

        // Verify command was sent with empty name and zero secret
        let sentData = await transport.getSentData()
        #expect(sentData.count == 1)
        #expect(sentData[0][0] == CommandCode.setChannel.rawValue)
    }

    // MARK: - Sync Channels Tests

    @Test("Sync channels fetches all configured channels")
    func syncChannelsFetchesAllConfigured() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        await transport.setConnectionState(.ready)

        // Queue responses for 8 channel queries
        // Channels 0, 1, 2 exist, rest are not found
        let publicSecret = Data(repeating: 0, count: 16)
        let channel1Secret = ChannelService.hashSecret("channel1")
        let channel2Secret = ChannelService.hashSecret("channel2")

        await transport.queueResponses([
            createChannelInfoResponse(index: 0, name: "Public", secret: publicSecret),
            createChannelInfoResponse(index: 1, name: "Team", secret: channel1Secret),
            createChannelInfoResponse(index: 2, name: "Private", secret: channel2Secret),
            createErrorResponse(.notFound),
            createErrorResponse(.notFound),
            createErrorResponse(.notFound),
            createErrorResponse(.notFound),
            createErrorResponse(.notFound)
        ])

        let service = ChannelService(bleTransport: transport, dataStore: dataStore)

        let result = try await service.syncChannels(deviceID: deviceID)

        #expect(result.channelsSynced == 3)
        #expect(result.errors.isEmpty)

        // Verify channels were saved
        let channels = try await dataStore.fetchChannels(deviceID: deviceID)
        #expect(channels.count == 3)
    }

    @Test("Sync channels fails when not connected")
    func syncChannelsFailsWhenNotConnected() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        let service = ChannelService(bleTransport: transport, dataStore: dataStore)

        await #expect(throws: ChannelServiceError.self) {
            _ = try await service.syncChannels(deviceID: deviceID)
        }
    }

    @Test("Sync channels notifies update handler")
    func syncChannelsNotifiesUpdateHandler() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        await transport.setConnectionState(.ready)

        let publicSecret = Data(repeating: 0, count: 16)
        await transport.queueResponses([
            createChannelInfoResponse(index: 0, name: "Public", secret: publicSecret),
            createErrorResponse(.notFound),
            createErrorResponse(.notFound),
            createErrorResponse(.notFound),
            createErrorResponse(.notFound),
            createErrorResponse(.notFound),
            createErrorResponse(.notFound),
            createErrorResponse(.notFound)
        ])

        let service = ChannelService(bleTransport: transport, dataStore: dataStore)

        let receivedChannels = MutableBox<[ChannelDTO]>([])
        await service.setChannelUpdateHandler { channels in
            receivedChannels.value = channels
        }

        _ = try await service.syncChannels(deviceID: deviceID)

        #expect(receivedChannels.value.count == 1)
        #expect(receivedChannels.value.first?.name == "Public")
    }

    // MARK: - Public Channel Tests

    @Test("Setup public channel creates slot 0")
    func setupPublicChannelCreatesSlot0() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        await transport.setConnectionState(.ready)
        await transport.queueResponse(Data([ResponseCode.ok.rawValue]))

        let service = ChannelService(bleTransport: transport, dataStore: dataStore)

        try await service.setupPublicChannel(deviceID: deviceID)

        // Verify public channel was created
        let channel = try await dataStore.fetchChannel(deviceID: deviceID, index: 0)
        #expect(channel != nil)
        #expect(channel?.name == "Public")
        #expect(channel?.secret == Data(repeating: 0, count: 16))
        #expect(channel?.isPublicChannel == true)
    }

    @Test("Has public channel returns true when exists")
    func hasPublicChannelReturnsTrueWhenExists() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()

        // Create public channel locally
        let channelInfo = ChannelInfo(index: 0, name: "Public", secret: Data(repeating: 0, count: 16))
        _ = try await dataStore.saveChannel(deviceID: deviceID, from: channelInfo)

        let service = ChannelService(bleTransport: transport, dataStore: dataStore)

        let hasPublic = try await service.hasPublicChannel(deviceID: deviceID)
        #expect(hasPublic == true)
    }

    @Test("Has public channel returns false when missing")
    func hasPublicChannelReturnsFalseWhenMissing() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        let service = ChannelService(bleTransport: transport, dataStore: dataStore)

        let hasPublic = try await service.hasPublicChannel(deviceID: deviceID)
        #expect(hasPublic == false)
    }

    // MARK: - Local Database Tests

    @Test("Get channels from local database")
    func getChannelsFromLocalDatabase() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()

        // Create some channels locally
        let channel0 = ChannelInfo(index: 0, name: "Public", secret: Data(repeating: 0, count: 16))
        let channel1 = ChannelInfo(index: 1, name: "Team", secret: ChannelService.hashSecret("team"))
        _ = try await dataStore.saveChannel(deviceID: deviceID, from: channel0)
        _ = try await dataStore.saveChannel(deviceID: deviceID, from: channel1)

        let service = ChannelService(bleTransport: transport, dataStore: dataStore)

        let channels = try await service.getChannels(deviceID: deviceID)

        #expect(channels.count == 2)
        #expect(channels.contains { $0.index == 0 && $0.name == "Public" })
        #expect(channels.contains { $0.index == 1 && $0.name == "Team" })
    }

    @Test("Get active channels returns only those with messages")
    func getActiveChannelsReturnsOnlyThoseWithMessages() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()

        // Create channels
        let channel0 = ChannelInfo(index: 0, name: "Public", secret: Data(repeating: 0, count: 16))
        let channel1 = ChannelInfo(index: 1, name: "Active", secret: ChannelService.hashSecret("active"))
        let id0 = try await dataStore.saveChannel(deviceID: deviceID, from: channel0)
        let id1 = try await dataStore.saveChannel(deviceID: deviceID, from: channel1)

        // Update only channel1 to have a message date
        try await dataStore.updateChannelLastMessage(channelID: id1, date: Date())

        let service = ChannelService(bleTransport: transport, dataStore: dataStore)

        let activeChannels = try await service.getActiveChannels(deviceID: deviceID)

        #expect(activeChannels.count == 1)
        #expect(activeChannels.first?.name == "Active")
    }

    @Test("Set channel enabled updates local state")
    func setChannelEnabledUpdatesLocalState() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()

        // Create a channel
        let channelInfo = ChannelInfo(index: 1, name: "ToDisable", secret: ChannelService.hashSecret("test"))
        let channelID = try await dataStore.saveChannel(deviceID: deviceID, from: channelInfo)

        let service = ChannelService(bleTransport: transport, dataStore: dataStore)

        // Disable the channel
        try await service.setChannelEnabled(channelID: channelID, isEnabled: false)

        let channel = try await dataStore.fetchChannel(deviceID: deviceID, index: 1)
        #expect(channel?.isEnabled == false)
    }

    @Test("Set channel enabled fails when not found")
    func setChannelEnabledFailsWhenNotFound() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let service = ChannelService(bleTransport: transport, dataStore: dataStore)

        await #expect(throws: ChannelServiceError.self) {
            try await service.setChannelEnabled(channelID: UUID(), isEnabled: false)
        }
    }

    @Test("Clear unread count succeeds")
    func clearUnreadCountSucceeds() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()

        // Create a channel with unread count
        let channelInfo = ChannelInfo(index: 1, name: "WithUnread", secret: ChannelService.hashSecret("test"))
        let channelID = try await dataStore.saveChannel(deviceID: deviceID, from: channelInfo)

        // Manually set unread count by creating a channel with unread
        let channel = Channel(
            id: channelID,
            deviceID: deviceID,
            index: 1,
            name: "WithUnread",
            secret: channelInfo.secret,
            isEnabled: true,
            lastMessageDate: Date(),
            unreadCount: 5
        )
        try await dataStore.saveChannel(ChannelDTO(from: channel))

        let service = ChannelService(bleTransport: transport, dataStore: dataStore)

        try await service.clearUnreadCount(channelID: channelID)

        let updatedChannel = try await dataStore.fetchChannel(deviceID: deviceID, index: 1)
        #expect(updatedChannel?.unreadCount == 0)
    }

    // MARK: - Protocol Error Tests

    @Test("Fetch channel handles protocol error")
    func fetchChannelHandlesProtocolError() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        await transport.setConnectionState(.ready)
        await transport.queueResponse(createErrorResponse(.badState))

        let service = ChannelService(bleTransport: transport, dataStore: dataStore)

        do {
            _ = try await service.fetchChannel(index: 0)
            Issue.record("Expected error to be thrown")
        } catch let error as ChannelServiceError {
            if case .protocolError(let protocolError) = error {
                #expect(protocolError == .badState)
            } else {
                Issue.record("Expected protocol error")
            }
        }
    }

    @Test("Set channel handles protocol error")
    func setChannelHandlesProtocolError() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        await transport.setConnectionState(.ready)
        await transport.queueResponse(createErrorResponse(.illegalArgument))

        let service = ChannelService(bleTransport: transport, dataStore: dataStore)

        do {
            try await service.setChannel(deviceID: deviceID, index: 0, name: "Bad", passphrase: "pass")
            Issue.record("Expected error to be thrown")
        } catch let error as ChannelServiceError {
            if case .protocolError(let protocolError) = error {
                #expect(protocolError == .illegalArgument)
            } else {
                Issue.record("Expected protocol error")
            }
        }
    }

    // MARK: - Stale Entry Cleanup Tests

    @Test("Fetch channel returns nil for empty-name channels")
    func fetchChannelReturnsNilForEmptyNameChannels() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        await transport.setConnectionState(.ready)

        // Device returns channelInfo with empty name (cleared slot)
        let emptySecret = Data(repeating: 0, count: 16)
        await transport.queueResponse(createChannelInfoResponse(index: 3, name: "", secret: emptySecret))

        let service = ChannelService(bleTransport: transport, dataStore: dataStore)

        // Empty-name channels should be treated as not configured
        let channelInfo = try await service.fetchChannel(index: 3)
        #expect(channelInfo == nil)
    }

    @Test("Sync channels deletes stale entries when device returns empty-name channels")
    func syncChannelsDeletesStaleEntriesForEmptyNameChannels() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        await transport.setConnectionState(.ready)

        // Pre-populate local database with a channel that was deleted on device
        let staleChannelInfo = ChannelInfo(
            index: 3,
            name: "Deleted Channel",
            secret: Data(repeating: 0xAB, count: 16)
        )
        _ = try await dataStore.saveChannel(deviceID: deviceID, from: staleChannelInfo)

        // Verify stale channel exists locally
        let beforeChannels = try await dataStore.fetchChannels(deviceID: deviceID)
        #expect(beforeChannels.count == 1)

        // Device returns empty-name channelInfo for cleared slot 3 (common behavior)
        let publicSecret = Data(repeating: 0, count: 16)
        let emptySecret = Data(repeating: 0, count: 16)
        await transport.queueResponses([
            createChannelInfoResponse(index: 0, name: "Public", secret: publicSecret),
            createChannelInfoResponse(index: 1, name: "", secret: emptySecret),  // Cleared
            createChannelInfoResponse(index: 2, name: "", secret: emptySecret),  // Cleared
            createChannelInfoResponse(index: 3, name: "", secret: emptySecret),  // Cleared - should delete local
            createChannelInfoResponse(index: 4, name: "", secret: emptySecret),  // Cleared
            createChannelInfoResponse(index: 5, name: "", secret: emptySecret),  // Cleared
            createChannelInfoResponse(index: 6, name: "", secret: emptySecret),  // Cleared
            createChannelInfoResponse(index: 7, name: "", secret: emptySecret)   // Cleared
        ])

        let service = ChannelService(bleTransport: transport, dataStore: dataStore)

        let result = try await service.syncChannels(deviceID: deviceID)

        // Only public channel should be synced
        #expect(result.channelsSynced == 1)
        #expect(result.errors.isEmpty)

        // Verify stale channel was deleted
        let afterChannels = try await dataStore.fetchChannels(deviceID: deviceID)
        #expect(afterChannels.count == 1)
        #expect(afterChannels.first?.index == 0)
        #expect(afterChannels.first?.name == "Public")

        // Slot 3 should be deleted
        let slot3 = try await dataStore.fetchChannel(deviceID: deviceID, index: 3)
        #expect(slot3 == nil)
    }

    @Test("Sync channels deletes stale local entries")
    func syncChannelsDeletesStaleLocalEntries() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()

        let deviceID = UUID()
        await transport.setConnectionState(.ready)

        // Pre-populate local database with a channel that doesn't exist on device
        let staleChannelInfo = ChannelInfo(
            index: 3,
            name: "Stale Channel",
            secret: Data(repeating: 0xAB, count: 16)
        )
        _ = try await dataStore.saveChannel(deviceID: deviceID, from: staleChannelInfo)

        // Verify stale channel exists locally
        let beforeChannels = try await dataStore.fetchChannels(deviceID: deviceID)
        #expect(beforeChannels.count == 1)
        #expect(beforeChannels.first?.index == 3)

        // Device only has public channel (slot 0) - all other slots return not found
        let publicSecret = Data(repeating: 0, count: 16)
        await transport.queueResponses([
            createChannelInfoResponse(index: 0, name: "Public", secret: publicSecret),
            createErrorResponse(.notFound),  // Slot 1 empty
            createErrorResponse(.notFound),  // Slot 2 empty
            createErrorResponse(.notFound),  // Slot 3 empty - this should delete local entry
            createErrorResponse(.notFound),  // Slot 4 empty
            createErrorResponse(.notFound),  // Slot 5 empty
            createErrorResponse(.notFound),  // Slot 6 empty
            createErrorResponse(.notFound)   // Slot 7 empty
        ])

        let service = ChannelService(bleTransport: transport, dataStore: dataStore)

        // Verify we can find the stale channel before sync (using same pattern as syncChannels)
        let staleBeforeSync = try await dataStore.fetchChannel(deviceID: deviceID, index: 3)
        #expect(staleBeforeSync != nil, "Stale channel should be findable before sync")
        #expect(staleBeforeSync?.name == "Stale Channel")

        // Also verify via service's own method
        let staleViaService = try await service.getChannel(deviceID: deviceID, index: 3)
        #expect(staleViaService != nil, "Stale channel should be findable via service before sync")

        let result = try await service.syncChannels(deviceID: deviceID)

        // Verify sync result
        #expect(result.channelsSynced == 1)
        #expect(result.errors.isEmpty)

        // Check via service method immediately after sync
        let staleViaServiceAfter = try await service.getChannel(deviceID: deviceID, index: 3)
        #expect(staleViaServiceAfter == nil, "Stale channel should be deleted via service after sync")

        // Verify stale channel was deleted
        let afterChannels = try await dataStore.fetchChannels(deviceID: deviceID)
        #expect(afterChannels.count == 1, "Expected 1 channel after sync, got \(afterChannels.count). Indices: \(afterChannels.map(\.index))")
        #expect(afterChannels.first?.index == 0)  // Only public channel remains
        #expect(afterChannels.first?.name == "Public")

        // Verify slot 3 no longer exists
        let slot3 = try await dataStore.fetchChannel(deviceID: deviceID, index: 3)
        #expect(slot3 == nil)
    }
}
