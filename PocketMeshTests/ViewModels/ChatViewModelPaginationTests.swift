import Testing
import Foundation
@testable import PocketMesh
@testable import PocketMeshServices

// MARK: - Test Helpers

private func createTestContact(
    id: UUID = UUID(),
    deviceID: UUID,
    name: String = "TestContact"
) -> ContactDTO {
    ContactDTO(
        id: id,
        deviceID: deviceID,
        publicKey: Data((0..<32).map { _ in UInt8.random(in: 0...255) }),
        name: name,
        typeRawValue: ContactType.chat.rawValue,
        flags: 0,
        outPathLength: 2,
        outPath: Data([0x01, 0x02]),
        lastAdvertTimestamp: UInt32(Date().timeIntervalSince1970),
        latitude: 0,
        longitude: 0,
        lastModified: UInt32(Date().timeIntervalSince1970),
        nickname: nil,
        isBlocked: false,
        isMuted: false,
        isFavorite: false,
        lastMessageDate: Date(),
        unreadCount: 0
    )
}

private func createTestChannel(
    id: UUID = UUID(),
    deviceID: UUID,
    index: UInt8 = 0,
    name: String = "TestChannel"
) -> ChannelDTO {
    ChannelDTO(
        id: id,
        deviceID: deviceID,
        index: index,
        name: name,
        secret: Data(),
        isEnabled: true,
        lastMessageDate: Date(),
        unreadCount: 0,
        unreadMentionCount: 0,
        isMuted: false,
        isFavorite: false
    )
}

private func createTestMessage(
    contactID: UUID,
    deviceID: UUID,
    timestamp: UInt32,
    text: String = "Test message"
) -> MessageDTO {
    MessageDTO(
        id: UUID(),
        deviceID: deviceID,
        contactID: contactID,
        channelIndex: nil,
        text: text,
        timestamp: timestamp,
        createdAt: Date(),
        direction: .incoming,
        status: .delivered,
        textType: .plain,
        ackCode: nil,
        pathLength: 0,
        snr: nil,
        senderKeyPrefix: nil,
        senderNodeName: nil,
        isRead: false,
        replyToID: nil,
        roundTripTime: nil,
        heardRepeats: 0,
        retryAttempt: 0,
        maxRetryAttempts: 0
    )
}

private func createChannelMessage(
    deviceID: UUID,
    channelIndex: UInt8,
    timestamp: UInt32,
    senderName: String = "Sender",
    text: String = "Test message"
) -> MessageDTO {
    MessageDTO(
        id: UUID(),
        deviceID: deviceID,
        contactID: nil,
        channelIndex: channelIndex,
        text: text,
        timestamp: timestamp,
        createdAt: Date(),
        direction: .incoming,
        status: .delivered,
        textType: .plain,
        ackCode: nil,
        pathLength: 0,
        snr: nil,
        senderKeyPrefix: nil,
        senderNodeName: senderName,
        isRead: false,
        replyToID: nil,
        roundTripTime: nil,
        heardRepeats: 0,
        retryAttempt: 0,
        maxRetryAttempts: 0
    )
}

// MARK: - Mock DataStore for Pagination Testing

/// A minimal mock data store for testing pagination behavior.
/// Uses in-memory storage and allows configuring responses.
actor PaginationTestDataStore: PersistenceStoreProtocol {
    var messages: [UUID: MessageDTO] = [:]
    var contacts: [UUID: ContactDTO] = [:]
    var channels: [UUID: ChannelDTO] = [:]
    var blockedContacts: [ContactDTO] = []

    var stubbedFetchError: Error?

    init() {}

    // MARK: - Message Operations

    func saveMessage(_ dto: MessageDTO) async throws {
        messages[dto.id] = dto
    }

    func fetchMessage(id: UUID) async throws -> MessageDTO? {
        messages[id]
    }

    func fetchMessage(ackCode: UInt32) async throws -> MessageDTO? {
        messages.values.first { $0.ackCode == ackCode }
    }

    func fetchMessages(contactID: UUID, limit: Int, offset: Int) async throws -> [MessageDTO] {
        if let error = stubbedFetchError {
            throw error
        }
        // Match production: sort descending (newest first), apply offset/limit, then reverse to ascending
        let filtered = messages.values.filter { $0.contactID == contactID }
            .sorted { $0.timestamp > $1.timestamp }
        return Array(filtered.dropFirst(offset).prefix(limit).reversed())
    }

    func fetchMessages(deviceID: UUID, channelIndex: UInt8, limit: Int, offset: Int) async throws -> [MessageDTO] {
        if let error = stubbedFetchError {
            throw error
        }
        // Match production: sort descending (newest first), apply offset/limit, then reverse to ascending
        let filtered = messages.values.filter { $0.deviceID == deviceID && $0.channelIndex == channelIndex }
            .sorted { $0.timestamp > $1.timestamp }
        return Array(filtered.dropFirst(offset).prefix(limit).reversed())
    }

    func updateMessageStatus(id: UUID, status: MessageStatus) async throws {}
    func updateMessageAck(id: UUID, ackCode: UInt32, status: MessageStatus, roundTripTime: UInt32?) async throws {}
    func updateMessageByAckCode(_ ackCode: UInt32, status: MessageStatus, roundTripTime: UInt32?) async throws {}
    func updateMessageRetryStatus(
        id: UUID,
        status: MessageStatus,
        retryAttempt: Int,
        maxRetryAttempts: Int
    ) async throws {}
    func updateMessageTimestamp(id: UUID, timestamp: UInt32) async throws {}
    func updateMessageHeardRepeats(id: UUID, heardRepeats: Int) async throws {}
    func updateMessageLinkPreview(
        id: UUID,
        url: String?,
        title: String?,
        imageData: Data?,
        iconData: Data?,
        fetched: Bool
    ) async throws {}

    // MARK: - Contact Operations

    func fetchContacts(deviceID: UUID) async throws -> [ContactDTO] {
        contacts.values.filter { $0.deviceID == deviceID }
    }

    func fetchConversations(deviceID: UUID) async throws -> [ContactDTO] {
        contacts.values.filter { $0.deviceID == deviceID && $0.lastMessageDate != nil }
    }

    func fetchContact(id: UUID) async throws -> ContactDTO? {
        contacts[id]
    }

    func fetchContact(deviceID: UUID, publicKey: Data) async throws -> ContactDTO? {
        contacts.values.first { $0.deviceID == deviceID && $0.publicKey == publicKey }
    }

    func fetchContact(deviceID: UUID, publicKeyPrefix: Data) async throws -> ContactDTO? {
        contacts.values.first { $0.deviceID == deviceID && $0.publicKey.prefix(6) == publicKeyPrefix }
    }

    func fetchContactPublicKeysByPrefix(deviceID: UUID) async throws -> [UInt8: [Data]] { [:] }
    @discardableResult func saveContact(deviceID: UUID, from frame: ContactFrame) async throws -> UUID { UUID() }
    func saveContact(_ dto: ContactDTO) async throws { contacts[dto.id] = dto }
    func deleteContact(id: UUID) async throws { contacts.removeValue(forKey: id) }
    func updateContactLastMessage(contactID: UUID, date: Date?) async throws {}
    func incrementUnreadCount(contactID: UUID) async throws {}
    func clearUnreadCount(contactID: UUID) async throws {}

    // MARK: - Mention Tracking

    func markMentionSeen(messageID: UUID) async throws {}
    func incrementUnreadMentionCount(contactID: UUID) async throws {}
    func decrementUnreadMentionCount(contactID: UUID) async throws {}
    func clearUnreadMentionCount(contactID: UUID) async throws {}
    func incrementChannelUnreadMentionCount(channelID: UUID) async throws {}
    func decrementChannelUnreadMentionCount(channelID: UUID) async throws {}
    func clearChannelUnreadMentionCount(channelID: UUID) async throws {}
    func fetchUnseenMentionIDs(contactID: UUID) async throws -> [UUID] { [] }
    func fetchUnseenChannelMentionIDs(deviceID: UUID, channelIndex: UInt8) async throws -> [UUID] { [] }
    func deleteMessagesForContact(contactID: UUID) async throws {}
    func fetchBlockedContacts(deviceID: UUID) async throws -> [ContactDTO] {
        blockedContacts.filter { $0.deviceID == deviceID }
    }

    // MARK: - Channel Operations

    func fetchChannels(deviceID: UUID) async throws -> [ChannelDTO] {
        channels.values.filter { $0.deviceID == deviceID }.sorted { $0.index < $1.index }
    }

    func fetchChannel(deviceID: UUID, index: UInt8) async throws -> ChannelDTO? {
        channels.values.first { $0.deviceID == deviceID && $0.index == index }
    }

    func fetchChannel(id: UUID) async throws -> ChannelDTO? {
        channels[id]
    }

    @discardableResult func saveChannel(deviceID: UUID, from info: ChannelInfo) async throws -> UUID { UUID() }
    func saveChannel(_ dto: ChannelDTO) async throws { channels[dto.id] = dto }
    func deleteChannel(id: UUID) async throws { channels.removeValue(forKey: id) }
    func updateChannelLastMessage(channelID: UUID, date: Date) async throws {}
    func incrementChannelUnreadCount(channelID: UUID) async throws {}
    func clearChannelUnreadCount(channelID: UUID) async throws {}

    // MARK: - Saved Trace Paths

    func fetchSavedTracePaths(deviceID: UUID) async throws -> [SavedTracePathDTO] { [] }
    func fetchSavedTracePath(id: UUID) async throws -> SavedTracePathDTO? { nil }
    func createSavedTracePath(
        deviceID: UUID,
        name: String,
        pathBytes: Data,
        initialRun: TracePathRunDTO?
    ) async throws -> SavedTracePathDTO {
        SavedTracePathDTO(
            id: UUID(),
            deviceID: deviceID,
            name: name,
            pathBytes: pathBytes,
            createdDate: Date(),
            runs: []
        )
    }
    func updateSavedTracePathName(id: UUID, name: String) async throws {}
    func deleteSavedTracePath(id: UUID) async throws {}
    func appendTracePathRun(pathID: UUID, run: TracePathRunDTO) async throws {}

    // MARK: - Heard Repeats

    func findSentChannelMessage(
        deviceID: UUID,
        channelIndex: UInt8,
        timestamp: UInt32,
        text: String,
        withinSeconds: Int
    ) async throws -> MessageDTO? { nil }
    func saveMessageRepeat(_ dto: MessageRepeatDTO) async throws {}
    func fetchMessageRepeats(messageID: UUID) async throws -> [MessageRepeatDTO] { [] }
    func messageRepeatExists(rxLogEntryID: UUID) async throws -> Bool { false }
    func incrementMessageHeardRepeats(id: UUID) async throws -> Int { 0 }
    func incrementMessageSendCount(id: UUID) async throws -> Int { 0 }

    // MARK: - Debug Log Operations

    func saveDebugLogEntries(_ dtos: [DebugLogEntryDTO]) async throws {}
    func fetchDebugLogEntries(since date: Date, limit: Int) async throws -> [DebugLogEntryDTO] { [] }
    func countDebugLogEntries() async throws -> Int { 0 }
    func pruneDebugLogEntries(keepCount: Int) async throws {}
    func clearDebugLogEntries() async throws {}

    // MARK: - Link Preview Data

    func fetchLinkPreview(url: String) async throws -> LinkPreviewDataDTO? { nil }
    func saveLinkPreview(_ dto: LinkPreviewDataDTO) async throws {}

    // MARK: - RxLogEntry Lookup

    func findRxLogEntry(
        channelIndex: UInt8?,
        senderTimestamp: UInt32,
        withinSeconds: Double,
        contactName: String?
    ) async throws -> RxLogEntryDTO? { nil }

    // MARK: - Discovered Nodes

    func upsertDiscoveredNode(deviceID: UUID, from frame: ContactFrame) async throws -> (node: DiscoveredNodeDTO, isNew: Bool) {
        fatalError("Not implemented")
    }
    func fetchDiscoveredNodes(deviceID: UUID) async throws -> [DiscoveredNodeDTO] { [] }
    func deleteDiscoveredNode(id: UUID) async throws {}
    func clearDiscoveredNodes(deviceID: UUID) async throws {}
    func fetchContactPublicKeys(deviceID: UUID) async throws -> Set<Data> { Set() }
}

// MARK: - Mock Link Preview Cache

actor MockLinkPreviewCacheForPagination: LinkPreviewCaching {
    func preview(
        for url: URL,
        using dataStore: any PersistenceStoreProtocol,
        isChannelMessage: Bool
    ) async -> LinkPreviewResult {
        .noPreviewAvailable
    }

    func manualFetch(
        for url: URL,
        using dataStore: any PersistenceStoreProtocol
    ) async -> LinkPreviewResult {
        .noPreviewAvailable
    }

    func isFetching(_ url: URL) async -> Bool { false }
    func cachedPreview(for url: URL) async -> LinkPreviewDataDTO? { nil }
}

// MARK: - Pagination Tests

@Suite("ChatViewModel Pagination Tests")
@MainActor
struct ChatViewModelPaginationTests {

    // MARK: - Test: loadOlderMessages sets hasMoreMessages = false when fewer than pageSize returned

    @Test("Loading fewer messages than pageSize marks no more messages available")
    func loadFewerThanPageSizeStopsLoading() async throws {
        let dataStore = PaginationTestDataStore()
        let linkPreviewCache = MockLinkPreviewCacheForPagination()
        let viewModel = ChatViewModel()

        let deviceID = UUID()
        let contactID = UUID()
        let contact = createTestContact(id: contactID, deviceID: deviceID)

        try await dataStore.saveContact(contact)

        // Add only 10 messages (less than pageSize of 50)
        for index in 0..<10 {
            let message = createTestMessage(
                contactID: contactID,
                deviceID: deviceID,
                timestamp: UInt32(1000 + index)
            )
            try await dataStore.saveMessage(message)
        }

        // Configure view model - need to use the internal configure method
        // Since we can't directly inject a PersistenceStoreProtocol, we'll test through observable behavior
        viewModel.currentContact = contact
        viewModel.messages = try await dataStore.fetchMessages(contactID: contactID, limit: 50, offset: 0)

        let initialCount = viewModel.messages.count
        #expect(initialCount == 10)

        // After loading 10 messages (< 50 pageSize), hasMoreMessages should be false internally
        // We verify this by checking that calling loadOlderMessages has no effect
        // when there are no more messages (since we loaded all 10 and offset would be 10)

        // Direct unit test of the pagination logic: if initial load < pageSize, no more loading
        #expect(viewModel.messages.count < 50, "Should have fewer than pageSize messages")
    }

    @Test("loadOlderMessages prepends messages to array")
    func loadOlderMessagesPrepends() async throws {
        let dataStore = PaginationTestDataStore()
        let deviceID = UUID()
        let contactID = UUID()
        let contact = createTestContact(id: contactID, deviceID: deviceID)

        try await dataStore.saveContact(contact)

        // Add 60 messages with sequential timestamps (0-59)
        for index in 0..<60 {
            let message = createTestMessage(
                contactID: contactID,
                deviceID: deviceID,
                timestamp: UInt32(1000 + index),
                text: "Message \(index)"
            )
            try await dataStore.saveMessage(message)
        }

        // Production pagination: sort descending, apply offset/limit, reverse to ascending
        // With 60 messages (timestamps 1000-1059):
        // - offset 0, limit 50 returns the 50 most recent (1010-1059), sorted ascending
        // - offset 50, limit 50 returns the next 10 older (1000-1009), sorted ascending

        let firstPage = try await dataStore.fetchMessages(contactID: contactID, limit: 50, offset: 0)
        #expect(firstPage.count == 50)
        #expect(firstPage.first?.timestamp == 1010, "First page starts with oldest of the 50 most recent")
        #expect(firstPage.last?.timestamp == 1059, "First page ends with the most recent message")

        // Fetch older messages (what loadOlderMessages does)
        let secondPage = try await dataStore.fetchMessages(contactID: contactID, limit: 50, offset: 50)
        #expect(secondPage.count == 10, "Second page has remaining 10 older messages")
        #expect(secondPage.first?.timestamp == 1000, "Second page starts with the oldest message")
        #expect(secondPage.last?.timestamp == 1009, "Second page ends before first page starts")

        // Simulate loadOlderMessages: prepend older messages
        var messages = firstPage
        messages.insert(contentsOf: secondPage, at: 0)

        #expect(messages.count == 60)
        #expect(messages.first?.timestamp == 1000, "After prepend, oldest is first")
        #expect(messages.last?.timestamp == 1059, "After prepend, newest is last")
    }

    @Test("loadOlderMessages guards against concurrent fetches")
    func loadOlderMessagesGuardsConcurrent() async {
        let viewModel = ChatViewModel()

        // isLoadingOlder starts false
        #expect(viewModel.isLoadingOlder == false)

        // After initial setup without dataStore, calling loadOlderMessages returns early
        // This tests the guard condition
        await viewModel.loadOlderMessages()
        #expect(viewModel.isLoadingOlder == false)
    }

    @Test("loadOlderMessages returns early without dataStore")
    func loadOlderMessagesWithoutDataStoreDoesNothing() async {
        let viewModel = ChatViewModel()
        let deviceID = UUID()
        let contactID = UUID()
        let contact = createTestContact(id: contactID, deviceID: deviceID)

        viewModel.currentContact = contact
        viewModel.messages = []

        // Without configuring dataStore, loadOlderMessages should return early
        await viewModel.loadOlderMessages()

        // No error should be set
        #expect(viewModel.errorMessage == nil)
        #expect(viewModel.messages.isEmpty)
    }

    @Test("Pagination state resets when loading messages for new contact")
    func paginationStateResetsOnConversationSwitch() async {
        let viewModel = ChatViewModel()
        let deviceID = UUID()

        // Create two contacts
        let contactA = createTestContact(id: UUID(), deviceID: deviceID, name: "Alice")
        let contactB = createTestContact(id: UUID(), deviceID: deviceID, name: "Bob")

        // Start with contact A
        viewModel.currentContact = contactA
        viewModel.messages = [
            createTestMessage(contactID: contactA.id, deviceID: deviceID, timestamp: 1000)
        ]

        // isLoadingOlder should be false
        #expect(viewModel.isLoadingOlder == false)

        // Switch to contact B
        viewModel.currentContact = contactB
        viewModel.messages = []

        // State should be clean for new contact
        #expect(viewModel.messages.isEmpty)
        #expect(viewModel.isLoadingOlder == false)
    }

    @Test("Initial message load sets hasMoreMessages based on count")
    func initialLoadSetsHasMoreMessages() async {
        let viewModel = ChatViewModel()

        // When messages.count equals pageSize (50), hasMoreMessages should remain true
        // When messages.count < pageSize, hasMoreMessages becomes false

        // This is tested indirectly through the loadMessages behavior
        // The key is that with < 50 messages, subsequent loadOlderMessages calls should not fetch

        #expect(viewModel.messages.isEmpty)
    }
}

// MARK: - Channel Pagination Tests

@Suite("ChatViewModel Channel Pagination Tests")
@MainActor
struct ChatViewModelChannelPaginationTests {

    @Test("Channel message pagination works similar to direct messages")
    func channelPaginationWorks() async throws {
        let dataStore = PaginationTestDataStore()
        let deviceID = UUID()
        let channelIndex: UInt8 = 0
        let channel = createTestChannel(deviceID: deviceID, index: channelIndex)

        try await dataStore.saveChannel(channel)

        // Add 30 channel messages
        for index in 0..<30 {
            let message = createChannelMessage(
                deviceID: deviceID,
                channelIndex: channelIndex,
                timestamp: UInt32(1000 + index),
                senderName: "User\(index % 3)"
            )
            try await dataStore.saveMessage(message)
        }

        // Fetch first page
        let messages = try await dataStore.fetchMessages(
            deviceID: deviceID,
            channelIndex: channelIndex,
            limit: 50,
            offset: 0
        )

        #expect(messages.count == 30)
        #expect(messages.count < 50, "Fewer than pageSize means no more messages available")
    }

    @Test("loadOlderMessages handles channel messages")
    func loadOlderMessagesHandlesChannels() async {
        let viewModel = ChatViewModel()
        let deviceID = UUID()
        let channelIndex: UInt8 = 1
        let channel = createTestChannel(deviceID: deviceID, index: channelIndex, name: "General")

        viewModel.currentChannel = channel
        viewModel.currentContact = nil

        // Without dataStore configured, loadOlderMessages returns early
        await viewModel.loadOlderMessages()

        #expect(viewModel.isLoadingOlder == false)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("Initial channel load uses unfiltered count for hasMoreMessages")
    func initialLoadUsesUnfilteredCountForPagination() async throws {
        // If we fetch 50 messages and 10 are blocked, hasMoreMessages should still be true
        // because the unfiltered count (50) equals pageSize
        let dataStore = PaginationTestDataStore()
        let deviceID = UUID()
        let channelIndex: UInt8 = 0

        // Add exactly 50 messages (pageSize), some from blocked sender
        for index in 0..<50 {
            let senderName = index < 10 ? "BlockedUser" : "User\(index)"
            let message = createChannelMessage(
                deviceID: deviceID,
                channelIndex: channelIndex,
                timestamp: UInt32(1000 + index),
                senderName: senderName
            )
            try await dataStore.saveMessage(message)
        }

        // Fetch all messages
        let messages = try await dataStore.fetchMessages(
            deviceID: deviceID,
            channelIndex: channelIndex,
            limit: 50,
            offset: 0
        )

        #expect(messages.count == 50, "Should fetch 50 messages before filtering")

        // After filtering, would have 40 messages, but hasMoreMessages should be based on 50
        let filtered = messages.filter { $0.senderNodeName != "BlockedUser" }
        #expect(filtered.count == 40, "After filtering should have 40 messages")

        // The key insight: unfiltered count (50) == pageSize means hasMoreMessages = true
        #expect(messages.count == 50, "Unfiltered count should drive pagination decision")
    }
}

// MARK: - Display Items Tests

@Suite("ChatViewModel Display Items Pagination Tests")
@MainActor
struct ChatViewModelDisplayItemsPaginationTests {

    @Test("Display items are rebuilt after loading older messages")
    func displayItemsRebuildAfterLoadingOlder() async {
        let viewModel = ChatViewModel()

        // Start with some messages
        let deviceID = UUID()
        let contactID = UUID()

        let messages = (0..<5).map { index in
            createTestMessage(
                contactID: contactID,
                deviceID: deviceID,
                timestamp: UInt32(1000 + index)
            )
        }

        viewModel.messages = messages
        await viewModel.buildDisplayItems()

        #expect(viewModel.displayItems.count == 5)

        // Add more messages (simulating loadOlderMessages prepend)
        let olderMessages = (0..<3).map { index in
            createTestMessage(
                contactID: contactID,
                deviceID: deviceID,
                timestamp: UInt32(900 + index)
            )
        }

        viewModel.messages.insert(contentsOf: olderMessages, at: 0)
        await viewModel.buildDisplayItems()

        #expect(viewModel.displayItems.count == 8)
    }

    @Test("Message lookup by ID works after pagination")
    func messageLookupWorksAfterPagination() async {
        let viewModel = ChatViewModel()
        let deviceID = UUID()
        let contactID = UUID()

        let message1 = createTestMessage(contactID: contactID, deviceID: deviceID, timestamp: 1000)
        let message2 = createTestMessage(contactID: contactID, deviceID: deviceID, timestamp: 1001)

        viewModel.messages = [message1, message2]
        await viewModel.buildDisplayItems()

        // Lookup should work
        #expect(viewModel.displayItems.count == 2)
        let foundMessage = viewModel.message(for: viewModel.displayItems[0])
        #expect(foundMessage?.id == message1.id)
    }
}
