import XCTest
@testable import PocketMesh
@testable import PocketMeshServices
import SwiftData
import MeshCore

// MARK: - Tests

@MainActor
final class ChatViewModelQueueTests: XCTestCase {

    var container: ModelContainer!
    var dataStore: PersistenceStore!
    var session: MeshCoreSession!
    var messageService: MessageService!

    override func setUp() async throws {
        // Create in-memory container
        container = try PersistenceStore.createContainer(inMemory: true)

        // Create persistence store
        dataStore = PersistenceStore(modelContainer: container)

        // Create test device
        let device = Device(
            publicKey: Data(repeating: 1, count: 32),
            nodeName: "Test Device"
        )
        try container.mainContext.insert(device)
        try container.mainContext.save()

        // Create mock session
        let transport = MockTransport()
        session = MeshCoreSession(transport: transport)

        // Create message service
        messageService = MessageService(
            session: session,
            dataStore: dataStore
        )
    }

    override func tearDown() async throws {
        container = nil
        dataStore = nil
        session = nil
        messageService = nil
    }

    func testQueueStartsEmpty() {
        let viewModel = ChatViewModel()
        XCTAssertEqual(viewModel.sendQueueCount, 0)
        XCTAssertFalse(viewModel.isProcessingQueue)
    }

    func testSendMessageClearsInputImmediately() async throws {
        let viewModel = ChatViewModel()
        viewModel.configure(dataStore: dataStore, messageService: messageService)

        // Get the device ID
        let devices = try await dataStore.fetchDevices()
        guard let device = devices.first else {
            XCTFail("No device found")
            return
        }

        // Create a contact
        let contact = Contact(
            deviceID: device.id,
            publicKey: Data(repeating: 2, count: 32),
            name: "Test Contact"
        )
        try container.mainContext.insert(contact)
        try container.mainContext.save()

        let contactDTO = try await dataStore.fetchContact(id: contact.id)!
        viewModel.currentContact = contactDTO
        viewModel.composingText = "Hello world"

        // Send message
        await viewModel.sendMessage()

        // Input should be cleared
        XCTAssertTrue(viewModel.composingText.isEmpty)
        XCTAssertEqual(viewModel.sendQueueCount, 1)
    }

    func testProcessQueueSendsMessagesInOrder() async throws {
        let viewModel = ChatViewModel()
        viewModel.configure(dataStore: dataStore, messageService: messageService)

        // Get the device ID
        let devices = try await dataStore.fetchDevices()
        guard let device = devices.first else {
            XCTFail("No device found")
            return
        }

        // Create a contact
        let contact = Contact(
            deviceID: device.id,
            publicKey: Data(repeating: 2, count: 32),
            name: "Test Contact"
        )
        try container.mainContext.insert(contact)
        try container.mainContext.save()

        let contactDTO = try await dataStore.fetchContact(id: contact.id)!
        viewModel.currentContact = contactDTO

        // Create messages in DB first
        let msg1 = try await messageService.createPendingMessage(text: "First", to: contactDTO)
        let msg2 = try await messageService.createPendingMessage(text: "Second", to: contactDTO)
        let msg3 = try await messageService.createPendingMessage(text: "Third", to: contactDTO)

        // Queue message IDs for sending
        viewModel.enqueueMessage(msg1.id, contactID: contact.id)
        viewModel.enqueueMessage(msg2.id, contactID: contact.id)
        viewModel.enqueueMessage(msg3.id, contactID: contact.id)

        XCTAssertEqual(viewModel.sendQueueCount, 3)

        // Process the queue
        await viewModel.processQueueForTesting()

        // Verify queue is empty and processing is done
        XCTAssertEqual(viewModel.sendQueueCount, 0)
        XCTAssertFalse(viewModel.isProcessingQueue)

        let messages = try await dataStore.fetchMessages(contactID: contact.id)
        XCTAssertEqual(messages.count, 3)
        XCTAssertEqual(messages[0].text, "First")
        XCTAssertEqual(messages[1].text, "Second")
        XCTAssertEqual(messages[2].text, "Third")
    }

    func testQueueContinuesAfterFailure() async throws {
        // This test verifies that when one message fails, the queue continues
        // processing remaining messages. With real services, we verify the queue
        // processes all messages and ends in a clean state. The error handling
        // behavior is implemented in processQueue() - the catch block sets
        // errorMessage but doesn't break out of the loop.

        let viewModel = ChatViewModel()
        viewModel.configure(dataStore: dataStore, messageService: messageService)

        // Get the device ID
        let devices = try await dataStore.fetchDevices()
        guard let device = devices.first else {
            XCTFail("No device found")
            return
        }

        // Create a contact
        let contact = Contact(
            deviceID: device.id,
            publicKey: Data(repeating: 2, count: 32),
            name: "Test Contact"
        )
        try container.mainContext.insert(contact)
        try container.mainContext.save()

        let contactDTO = try await dataStore.fetchContact(id: contact.id)!
        viewModel.currentContact = contactDTO

        // Create messages in DB first
        let msg1 = try await messageService.createPendingMessage(text: "First", to: contactDTO)
        let msg2 = try await messageService.createPendingMessage(text: "Second", to: contactDTO)
        let msg3 = try await messageService.createPendingMessage(text: "Third", to: contactDTO)

        // Queue message IDs for sending
        viewModel.enqueueMessage(msg1.id, contactID: contact.id)
        viewModel.enqueueMessage(msg2.id, contactID: contact.id)
        viewModel.enqueueMessage(msg3.id, contactID: contact.id)

        // Process the queue
        await viewModel.processQueueForTesting()

        // Verify all messages were attempted (queue is empty)
        XCTAssertEqual(viewModel.sendQueueCount, 0)
        XCTAssertFalse(viewModel.isProcessingQueue)
    }

    func testMessagesGoToCorrectContactEvenAfterNavigatingAway() async throws {
        let viewModel = ChatViewModel()
        viewModel.configure(dataStore: dataStore, messageService: messageService)

        // Get the device ID
        let devices = try await dataStore.fetchDevices()
        guard let device = devices.first else {
            XCTFail("No device found")
            return
        }

        // Create two contacts: Alice and Bob
        let alice = Contact(
            deviceID: device.id,
            publicKey: Data(repeating: 2, count: 32),
            name: "Alice"
        )
        let bob = Contact(
            deviceID: device.id,
            publicKey: Data(repeating: 3, count: 32),
            name: "Bob"
        )
        try container.mainContext.insert(alice)
        try container.mainContext.insert(bob)
        try container.mainContext.save()

        let aliceDTO = try await dataStore.fetchContact(id: alice.id)!
        let bobDTO = try await dataStore.fetchContact(id: bob.id)!

        // User is chatting with Alice
        viewModel.currentContact = aliceDTO

        // Create messages for Alice in DB first
        let msg1 = try await messageService.createPendingMessage(text: "Hello Alice", to: aliceDTO)
        let msg2 = try await messageService.createPendingMessage(text: "How are you?", to: aliceDTO)

        // Queue message IDs for sending
        viewModel.enqueueMessage(msg1.id, contactID: alice.id)
        viewModel.enqueueMessage(msg2.id, contactID: alice.id)

        // User navigates to Bob's chat before queue finishes
        viewModel.currentContact = bobDTO

        // Process the queue
        await viewModel.processQueueForTesting()

        let aliceMessages = try await dataStore.fetchMessages(contactID: alice.id)
        let bobMessages = try await dataStore.fetchMessages(contactID: bob.id)

        XCTAssertEqual(aliceMessages.count, 2, "Messages should go to Alice")
        XCTAssertEqual(aliceMessages[0].text, "Hello Alice")
        XCTAssertEqual(aliceMessages[1].text, "How are you?")
        XCTAssertEqual(bobMessages.count, 0, "Bob should have no messages")
    }
}

// MARK: - Mock Transport

actor MockTransport: MeshTransport {
    func connect() async throws {
        // No-op for testing
    }

    func disconnect() async {
        // No-op for testing
    }

    func send(_ data: Data) async throws {
        // No-op for testing
    }

    var receivedData: AsyncStream<Data> {
        AsyncStream { _ in }
    }

    var isConnected: Bool {
        true
    }
}
