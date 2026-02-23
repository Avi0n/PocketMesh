import Testing
import Foundation
import MeshCore
import PocketMeshServices
@testable import PocketMesh

// MARK: - Test Transport

/// Minimal transport stub for creating a ServiceContainer in tests.
private actor StubTransport: MeshTransport {
    var isConnected: Bool { false }
    var receivedData: AsyncStream<Data> {
        AsyncStream { $0.finish() }
    }
    func connect() async throws {}
    func disconnect() async {}
    func send(_ data: Data) async throws {}
}

@Suite("MessageEventBroadcaster Tests")
@MainActor
struct MessageEventBroadcasterTests {

    // MARK: - Default State

    @Test("Default state has nil service references and zero counters")
    func defaultState() {
        let broadcaster = MessageEventBroadcaster()

        #expect(broadcaster.latestEvent == nil)
        #expect(broadcaster.latestMessage == nil)
        #expect(broadcaster.newMessageCount == 0)
        #expect(broadcaster.sessionStateChanged == 0)
        #expect(broadcaster.messageService == nil)
        #expect(broadcaster.remoteNodeService == nil)
        #expect(broadcaster.dataStore == nil)
        #expect(broadcaster.roomServerService == nil)
        #expect(broadcaster.binaryProtocolService == nil)
        #expect(broadcaster.repeaterAdminService == nil)
    }

    // MARK: - Handler Methods

    @Test("handleDirectMessage sets event and increments counter")
    func handleDirectMessage() {
        let broadcaster = MessageEventBroadcaster()
        let message = MessageDTO.stub()
        let contact = ContactDTO.stub()

        broadcaster.handleDirectMessage(message, from: contact)

        #expect(broadcaster.latestEvent == .directMessageReceived(message: message, contact: contact))
        #expect(broadcaster.latestMessage == message)
        #expect(broadcaster.newMessageCount == 1)
    }

    @Test("handleChannelMessage sets event and increments counter")
    func handleChannelMessage() {
        let broadcaster = MessageEventBroadcaster()
        let message = MessageDTO.stub()

        broadcaster.handleChannelMessage(message, channelIndex: 3)

        #expect(broadcaster.latestEvent == .channelMessageReceived(message: message, channelIndex: 3))
        #expect(broadcaster.newMessageCount == 1)
    }

    @Test("handleRoomMessage sets event and increments counter")
    func handleRoomMessage() {
        let broadcaster = MessageEventBroadcaster()
        let sessionID = UUID()
        let message = RoomMessageDTO.stub(sessionID: sessionID)

        broadcaster.handleRoomMessage(message)

        #expect(broadcaster.latestEvent == .roomMessageReceived(message: message, sessionID: sessionID))
        #expect(broadcaster.newMessageCount == 1)
    }

    @Test("handleAcknowledgement sets event and increments counter")
    func handleAcknowledgement() {
        let broadcaster = MessageEventBroadcaster()

        broadcaster.handleAcknowledgement(ackCode: 0xDEAD)

        #expect(broadcaster.latestEvent == .messageStatusUpdated(ackCode: 0xDEAD))
        #expect(broadcaster.newMessageCount == 1)
    }

    @Test("handleMessageFailed sets event and increments counter")
    func handleMessageFailed() {
        let broadcaster = MessageEventBroadcaster()
        let id = UUID()

        broadcaster.handleMessageFailed(messageID: id)

        #expect(broadcaster.latestEvent == .messageFailed(messageID: id))
        #expect(broadcaster.newMessageCount == 1)
    }

    @Test("handleMessageRetrying sets event with attempt info")
    func handleMessageRetrying() {
        let broadcaster = MessageEventBroadcaster()
        let id = UUID()

        broadcaster.handleMessageRetrying(messageID: id, attempt: 2, maxAttempts: 3)

        #expect(broadcaster.latestEvent == .messageRetrying(messageID: id, attempt: 2, maxAttempts: 3))
        #expect(broadcaster.newMessageCount == 1)
    }

    @Test("handleRoutingChanged sets event with routing info")
    func handleRoutingChanged() {
        let broadcaster = MessageEventBroadcaster()
        let contactID = UUID()

        broadcaster.handleRoutingChanged(contactID: contactID, isFlood: true)

        #expect(broadcaster.latestEvent == .routingChanged(contactID: contactID, isFlood: true))
        #expect(broadcaster.newMessageCount == 1)
    }

    @Test("handleHeardRepeatRecorded sets event with count")
    func handleHeardRepeatRecorded() {
        let broadcaster = MessageEventBroadcaster()
        let id = UUID()

        broadcaster.handleHeardRepeatRecorded(messageID: id, count: 5)

        #expect(broadcaster.latestEvent == .heardRepeatRecorded(messageID: id, count: 5))
        #expect(broadcaster.newMessageCount == 1)
    }

    @Test("handleReactionReceived sets event with summary")
    func handleReactionReceived() {
        let broadcaster = MessageEventBroadcaster()
        let id = UUID()

        broadcaster.handleReactionReceived(messageID: id, summary: "👍x3")

        #expect(broadcaster.latestEvent == .reactionReceived(messageID: id, summary: "👍x3"))
        #expect(broadcaster.newMessageCount == 1)
    }

    @Test("handleRoomMessageStatusUpdated sets event")
    func handleRoomMessageStatusUpdated() {
        let broadcaster = MessageEventBroadcaster()
        let id = UUID()

        broadcaster.handleRoomMessageStatusUpdated(messageID: id)

        #expect(broadcaster.latestEvent == .roomMessageStatusUpdated(messageID: id))
        #expect(broadcaster.newMessageCount == 1)
    }

    @Test("handleRoomMessageFailed sets event")
    func handleRoomMessageFailed() {
        let broadcaster = MessageEventBroadcaster()
        let id = UUID()

        broadcaster.handleRoomMessageFailed(messageID: id)

        #expect(broadcaster.latestEvent == .roomMessageFailed(messageID: id))
        #expect(broadcaster.newMessageCount == 1)
    }

    @Test("handleSessionStateChanged increments session counter")
    func handleSessionStateChanged() {
        let broadcaster = MessageEventBroadcaster()
        let sessionID = UUID()

        broadcaster.handleSessionStateChanged(sessionID: sessionID, isConnected: true)

        #expect(broadcaster.sessionStateChanged == 1)
    }

    @Test("handleUnknownSender sets event without incrementing message count")
    func handleUnknownSender() {
        let broadcaster = MessageEventBroadcaster()
        let prefix = Data([0xAB, 0xCD])

        broadcaster.handleUnknownSender(keyPrefix: prefix)

        #expect(broadcaster.latestEvent == .unknownSender(keyPrefix: prefix))
        #expect(broadcaster.newMessageCount == 0)
    }

    @Test("handleError sets event without incrementing message count")
    func handleError() {
        let broadcaster = MessageEventBroadcaster()

        broadcaster.handleError("test error")

        #expect(broadcaster.latestEvent == .error("test error"))
        #expect(broadcaster.newMessageCount == 0)
    }

    // MARK: - Counter Accumulation

    @Test("Multiple events accumulate newMessageCount")
    func counterAccumulation() {
        let broadcaster = MessageEventBroadcaster()
        let message = MessageDTO.stub()
        let contact = ContactDTO.stub()

        broadcaster.handleDirectMessage(message, from: contact)
        broadcaster.handleChannelMessage(message, channelIndex: 0)
        broadcaster.handleAcknowledgement(ackCode: 1)

        #expect(broadcaster.newMessageCount == 3)
    }

    @Test("Multiple session state changes accumulate counter")
    func sessionStateAccumulation() {
        let broadcaster = MessageEventBroadcaster()

        broadcaster.handleSessionStateChanged(sessionID: UUID(), isConnected: true)
        broadcaster.handleSessionStateChanged(sessionID: UUID(), isConnected: false)
        broadcaster.handleSessionStateChanged(sessionID: UUID(), isConnected: true)

        #expect(broadcaster.sessionStateChanged == 3)
    }

    // MARK: - wireServices Integration

    @Test("wireServices assigns all service references")
    func wireServicesAssignsReferences() async throws {
        let broadcaster = MessageEventBroadcaster()
        let session = MeshCoreSession(transport: StubTransport())
        let container = try PersistenceStore.createContainer(inMemory: true)
        let services = ServiceContainer(session: session, modelContainer: container)

        await broadcaster.wireServices(
            services,
            onConversationsChanged: {},
            onReactionReceived: { _ in }
        )

        #expect(broadcaster.messageService != nil)
        #expect(broadcaster.remoteNodeService != nil)
        #expect(broadcaster.dataStore != nil)
        #expect(broadcaster.roomServerService != nil)
        #expect(broadcaster.binaryProtocolService != nil)
        #expect(broadcaster.repeaterAdminService != nil)
    }
}

// MARK: - Test Stubs

private extension MessageDTO {
    static func stub(
        id: UUID = UUID(),
        text: String = "test",
        direction: MessageDirection = .incoming
    ) -> MessageDTO {
        MessageDTO(
            id: id,
            deviceID: UUID(),
            contactID: nil,
            channelIndex: nil,
            text: text,
            timestamp: UInt32(Date().timeIntervalSince1970),
            createdAt: Date(),
            direction: direction,
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
}

private extension ContactDTO {
    static func stub(
        id: UUID = UUID(),
        name: String = "Test Contact"
    ) -> ContactDTO {
        ContactDTO(
            id: id,
            deviceID: UUID(),
            publicKey: Data(repeating: 0xAA, count: ProtocolLimits.publicKeySize),
            name: name,
            typeRawValue: 0,
            flags: 0,
            outPathLength: 1,
            outPath: Data([0x01]),
            lastAdvertTimestamp: UInt32(Date().timeIntervalSince1970),
            latitude: 0,
            longitude: 0,
            lastModified: UInt32(Date().timeIntervalSince1970),
            nickname: nil,
            isBlocked: false,
            isMuted: false,
            isFavorite: false,
            lastMessageDate: nil,
            unreadCount: 0
        )
    }
}

private extension RoomMessageDTO {
    static func stub(
        id: UUID = UUID(),
        sessionID: UUID = UUID(),
        text: String = "room test"
    ) -> RoomMessageDTO {
        RoomMessageDTO(
            sessionID: sessionID,
            authorKeyPrefix: Data(repeating: 0xBB, count: 6),
            authorName: "TestSender",
            text: text,
            timestamp: UInt32(Date().timeIntervalSince1970)
        )
    }
}
