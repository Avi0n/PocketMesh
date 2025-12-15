# PocketMesh Testing Guide

This document describes the testing architecture, patterns, and utilities used in PocketMesh.

## Test Organization

```
PocketMeshTests/
├── Mock/                    # Mock implementations
│   ├── MockBLEPeripheral.swift
│   ├── MockBLEPeripheralTests.swift
│   └── MockKeychainService.swift
├── Services/                # Service layer tests
│   ├── MessageServiceTests.swift   # Also defines TestBLETransport
│   ├── ContactServiceTests.swift
│   ├── ChannelServiceTests.swift
│   ├── AdvertisementServiceTests.swift
│   ├── MessagePollingServiceTests.swift
│   ├── RemoteNodeServiceTests.swift
│   ├── RoomServerServiceTests.swift
│   └── RepeaterAdminServiceTests.swift
├── Protocol/                # Protocol codec tests
│   ├── ProtocolCodecTests.swift
│   └── RemoteNodeProtocolTests.swift
├── Integration/             # Integration tests
│   ├── DataStoreIntegrationTests.swift
│   ├── MockBLEIntegrationTests.swift  # Also defines MockBLETransport
│   └── RemoteNodeIntegrationTests.swift
├── ViewModels/              # ViewModel tests
│   └── ChatViewModelTests.swift
├── Models/                  # Model tests
│   └── RemoteNodeModelTests.swift
├── BLE/                     # BLE-specific tests
│   └── BLEReconnectionTests.swift
├── Helpers/                 # Test utilities
│   └── TestHelpers.swift
└── Performance/             # Performance tests (placeholder)
```

## Testing Framework

Tests use **Swift Testing** (modern framework with `@Test` and `@Suite`):

```swift
import Testing
@testable import PocketMeshKit

@Suite("ContactService Tests")
struct ContactServiceTests {
    @Test("Sync contacts updates database")
    func testSyncContacts() async throws {
        // Test implementation
    }
}
```

### Assertions

```swift
// Equality
#expect(value == expected)

// Boolean
#expect(condition)
#expect(!condition)

// Nil checks
#expect(optional != nil)
#expect(optional == nil)

// Error expectations
await #expect(throws: SomeError.self) {
    try await riskyOperation()
}
```

## Mock Implementations

### MockBLEPeripheral

A complete simulator of a MeshCore BLE device located at `Mock/MockBLEPeripheral.swift`.

**Features:**
- Full protocol command handling
- Contact and channel storage
- Message queue simulation
- Push notification generation

**Usage:**

```swift
let mock = MockBLEPeripheral()
let transport = MockBLETransport(peripheral: mock)

// Add test contacts (using ContactFrame)
let contact = ContactFrame(
    publicKey: testKey,
    type: .chat,
    flags: 0,
    outPathLength: 0,
    outPath: Data(),
    name: "Alice",
    lastAdvertTimestamp: 0,
    latitude: 0,
    longitude: 0,
    lastModified: 0
)
await mock.addContact(contact)

// Simulate incoming message (helper method)
await mock.simulateMessageReceived(
    from: alicePrefix,
    text: "Hello",
    timestamp: currentTimestamp
)

// Simulate push notification
await mock.simulatePush(.messageWaiting, data: Data())

// Simulate ACK confirmation
await mock.simulateSendConfirmed(ackCode: 1001, roundTrip: 250)

// Verify state
let contactCount = await mock.contactCount
#expect(contactCount == 1)
```

### TestBLETransport

A mock `BLETransport` implementation for service unit testing with queued responses. Defined inline within `Services/MessageServiceTests.swift`.

**Features:**
- Pre-configured response queue
- Failure injection
- Sent data tracking
- Connection state control

**Usage:**

```swift
let transport = TestBLETransport()

// Set connection state
await transport.setConnectionState(.ready)

// Configure responses
await transport.queueResponse(Data([0x00]))  // OK response
await transport.queueResponse(createSentResponse(ackCode: 1001))

// Inject failure
await transport.setNextSendToFail(with: BLEError.writeError("Test failure"))

// Verify sent data
let sentData = await transport.getSentData()
#expect(sentData.count == 2)
#expect(sentData[0][0] == CommandCode.sendTextMessage.rawValue)

// Simulate push
await transport.simulatePush(Data([0x82, ...]))  // sendConfirmed
```

### MockBLETransport

A mock `BLETransport` that wraps `MockBLEPeripheral` for integration testing. Defined in `Integration/MockBLEIntegrationTests.swift`.

**Usage:**

```swift
let mock = MockBLEPeripheral(nodeName: "TestNode")
let transport = MockBLETransport(peripheral: mock)

try await transport.connect(to: UUID())

// Send commands through to the mock peripheral
let query = FrameCodec.encodeDeviceQuery(protocolVersion: 8)
let response = try await transport.send(query)

// Access underlying peripheral for test setup
await transport.peripheral.addContact(contact)
```

### MockKeychainService

In-memory keychain for testing secure storage.

```swift
let keychain = MockKeychainService()

try await keychain.storePassword("secret123", forNodeKey: nodeKey)
let retrieved = try await keychain.retrievePassword(forNodeKey: nodeKey)
#expect(retrieved == "secret123")

// Verify storage (returns [Data], not [String])
let allKeys = await keychain.getAllStoredKeys()
#expect(allKeys.contains(nodeKey))

// Reset
await keychain.clear()
```

## Test Patterns

### Service Unit Test Pattern

```swift
@Suite("MessageService Tests")
struct MessageServiceTests {

    @Test("Send direct message successfully")
    func sendDirectMessageSuccessfully() async throws {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)

        let deviceID = UUID()
        let contact = createTestContact(deviceID: deviceID)
        try await dataStore.saveContact(contact)

        await transport.setConnectionState(.ready)
        await transport.queueResponse(createSentResponse(ackCode: 1001))

        let service = MessageService(bleTransport: transport, dataStore: dataStore)

        let result = try await service.sendDirectMessage(
            text: "Hello!",
            to: contact
        )

        #expect(result.ackCode == 1001)
        #expect(result.status == .sent)

        // Verify message was saved
        let messages = try await dataStore.fetchMessages(contactID: contact.id)
        #expect(messages.count == 1)
        #expect(messages.first?.text == "Hello!")
        #expect(messages.first?.status == .sent)
    }
}

// Private helper functions within each test file
private func createTestContact(deviceID: UUID, name: String = "TestContact") -> ContactDTO {
    let contact = Contact(
        id: UUID(),
        deviceID: deviceID,
        publicKey: Data((0..<32).map { _ in UInt8.random(in: 0...255) }),
        name: name,
        typeRawValue: ContactType.chat.rawValue,
        // ...
    )
    return ContactDTO(from: contact)
}

private func createSentResponse(ackCode: UInt32, isFlood: Bool = false, timeout: UInt32 = 5000) -> Data {
    var data = Data([ResponseCode.sent.rawValue])
    data.append(isFlood ? 1 : 0)
    data.append(contentsOf: withUnsafeBytes(of: ackCode.littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: timeout.littleEndian) { Array($0) })
    return data
}
```

### Integration Test Pattern

Integration tests use `MockBLETransport` with `MockBLEPeripheral` to test full service interactions:

```swift
@Suite("Remote Node Integration Tests")
struct RemoteNodeIntegrationTests {

    private func createTestTransport() -> TestBLETransport {
        TestBLETransport()
    }

    private func createTestDataStore() async throws -> DataStore {
        let container = try DataStore.createContainer(inMemory: true)
        return DataStore(modelContainer: container)
    }

    private func createFullTestStack(
        transport: TestBLETransport,
        dataStore: DataStore
    ) -> (
        RemoteNodeService,
        RoomServerService,
        RepeaterAdminService,
        BinaryProtocolService,
        MockKeychainService
    ) {
        let keychain = MockKeychainService()
        let binaryProtocol = BinaryProtocolService(bleTransport: transport)
        let remoteNodeService = RemoteNodeService(
            bleTransport: transport,
            binaryProtocol: binaryProtocol,
            dataStore: dataStore,
            keychainService: keychain
        )
        let roomServerService = RoomServerService(
            remoteNodeService: remoteNodeService,
            bleTransport: transport,
            dataStore: dataStore
        )
        let repeaterAdminService = RepeaterAdminService(
            remoteNodeService: remoteNodeService,
            binaryProtocol: binaryProtocol,
            dataStore: dataStore
        )
        return (remoteNodeService, roomServerService, repeaterAdminService, binaryProtocol, keychain)
    }

    @Test("Room flow: create session, post message, receive message")
    func roomFlowCreateSessionPostReceive() async throws {
        let transport = createTestTransport()
        let dataStore = try await createTestDataStore()
        let (_, roomService, _, _, keychain) = createFullTestStack(
            transport: transport,
            dataStore: dataStore
        )

        let deviceID = UUID()
        let roomContact = createTestContact(deviceID: deviceID, name: "Chat Room", type: .room)

        // Save contact to database (simulating discovery)
        try await dataStore.saveContact(roomContact)

        // Set up transport for responses
        await transport.setConnectionState(.ready)
        await transport.queueResponses([
            Data([ResponseCode.sent.rawValue]),  // For login
            Data([ResponseCode.sent.rawValue])   // For message post
        ])

        // ... test room operations
    }
}
```

### Protocol Test Pattern

```swift
@Suite("Protocol Codec")
struct ProtocolCodecTests {
    @Test("Encode device query")
    func testEncodeDeviceQuery() {
        let data = FrameCodec.encodeDeviceQuery(protocolVersion: 8)

        #expect(data.count == 2)
        #expect(data[0] == CommandCode.deviceQuery.rawValue)
        #expect(data[1] == 8)
    }

    @Test("Decode device info")
    func testDecodeDeviceInfo() throws {
        let response = Data([
            0x0D,  // Response code
            0x08,  // Firmware version
            100,   // Max contacts
            8,     // Max channels
            // ... more bytes
        ])

        let deviceInfo = try FrameCodec.decodeDeviceInfo(from: response)

        #expect(deviceInfo.firmwareVersion == 8)
        #expect(deviceInfo.maxContacts == 100)
        #expect(deviceInfo.maxChannels == 8)
    }

    @Test("Coordinates encode/decode roundtrip")
    func testCoordinateRoundtrip() throws {
        let lat = 37.7749
        let lon = -122.4194

        let contact = ContactFrame(
            publicKey: Data(repeating: 0, count: 32),
            type: .chat,
            latitude: lat,
            longitude: lon,
            // ...
        )

        let encoded = FrameCodec.encodeAddUpdateContact(contact)
        let decoded = try FrameCodec.decodeContactFrame(from: encoded)

        #expect(abs(decoded.latitude - lat) < 0.000001)
        #expect(abs(decoded.longitude - lon) < 0.000001)
    }
}
```

### Async Test Pattern

```swift
@Test("ACK timeout handling")
func testAckTimeout() async throws {
    let (transport, _, service) = try await createTestStack()

    // Queue sent response but no confirmation
    await transport.queueResponse(createSentResponse(ackCode: 1001))

    // Send message
    _ = try await service.sendDirectMessage(...)

    // Wait for timeout (use short timeout in tests)
    try await Task.sleep(for: .milliseconds(100))

    // Verify message marked as failed
    let message = try await dataStore.fetchMessage(byId: messageID)
    #expect(message?.status == .failed)
}
```

### Callback Capture Pattern

```swift
@Test("Sync progress handler called for each contact")
func testSyncProgress() async throws {
    let transport = TestBLETransport()
    let container = try DataStore.createContainer(inMemory: true)
    let dataStore = DataStore(modelContainer: container)
    let service = ContactService(bleTransport: transport, dataStore: dataStore)

    let progressUpdates = MutableBox<[(Int, Int)]>([])
    await service.setSyncProgressHandler { current, total in
        progressUpdates.value.append((current, total))
    }

    // Queue responses for 3 contacts
    await transport.queueResponse(createContactsStartResponse(count: 3))
    await transport.queueResponse(encodeContactFrame(contact1))
    await transport.queueResponse(encodeContactFrame(contact2))
    await transport.queueResponse(encodeContactFrame(contact3))
    await transport.queueResponse(createEndOfContactsResponse())

    // Trigger sync
    _ = try await service.syncContacts(deviceID: deviceID)

    // Verify progress callbacks
    #expect(progressUpdates.value.count == 3)
    #expect(progressUpdates.value[0] == (1, 3))
    #expect(progressUpdates.value[1] == (2, 3))
    #expect(progressUpdates.value[2] == (3, 3))
}
```

## Test Utilities

### MutableBox

Thread-safe wrapper for capturing values in async closures:

```swift
// In TestHelpers.swift
public final class MutableBox<T>: @unchecked Sendable {
    public var value: T

    public init(_ value: T) {
        self.value = value
    }
}
```

**Usage:**

```swift
let captured = MutableBox<String?>(nil)

await service.setHandler { result in
    captured.value = result
}

await service.doSomething()

#expect(captured.value == "expected")
```

### Test Data Factories

Each test file defines its own private helper functions for creating test data. Here are common patterns:

```swift
// Private helpers within a test file
private func createTestContact(
    deviceID: UUID = UUID(),
    name: String = "Test",
    type: ContactType = .chat,
    publicKey: Data? = nil
) -> ContactDTO {
    let contact = Contact(
        id: UUID(),
        deviceID: deviceID,
        publicKey: publicKey ?? Data((0..<32).map { _ in UInt8.random(in: 0...255) }),
        name: name,
        typeRawValue: type.rawValue,
        flags: 0,
        outPathLength: 2,
        outPath: Data([0x01, 0x02]),
        lastAdvertTimestamp: UInt32(Date().timeIntervalSince1970),
        latitude: 0,
        longitude: 0,
        lastModified: UInt32(Date().timeIntervalSince1970)
    )
    return ContactDTO(from: contact)
}

// Response frame creators
private func createSentResponse(ackCode: UInt32, isFlood: Bool = false, timeout: UInt32 = 5000) -> Data {
    var data = Data([ResponseCode.sent.rawValue])
    data.append(isFlood ? 1 : 0)
    data.append(contentsOf: withUnsafeBytes(of: ackCode.littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: timeout.littleEndian) { Array($0) })
    return data
}

private func createErrorResponse(_ error: ProtocolError) -> Data {
    Data([ResponseCode.error.rawValue, error.rawValue])
}

private func createSendConfirmation(ackCode: UInt32, roundTrip: UInt32 = 500) -> Data {
    var data = Data([PushCode.sendConfirmed.rawValue])
    data.append(contentsOf: withUnsafeBytes(of: ackCode.littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: roundTrip.littleEndian) { Array($0) })
    return data
}
```

### In-Memory DataStore

```swift
private func createTestDataStore() async throws -> DataStore {
    let container = try DataStore.createContainer(inMemory: true)
    return DataStore(modelContainer: container)
}
```

## Running Tests

### Command Line

```bash
# Run all tests
xcodebuild test -project PocketMesh.xcodeproj -scheme PocketMesh \
    -destination "platform=iOS Simulator,name=iPhone 16e" 2>&1 | xcsift

# Run specific test file
xcodebuild test -project PocketMesh.xcodeproj -scheme PocketMesh \
    -destination "platform=iOS Simulator,name=iPhone 16e" \
    -only-testing:PocketMeshTests/MessageServiceTests 2>&1 | xcsift

# With coverage
xcodebuild test -project PocketMesh.xcodeproj -scheme PocketMesh \
    -destination "platform=iOS Simulator,name=iPhone 16e" \
    -enableCodeCoverage YES 2>&1 | xcsift --coverage
```

### Xcode

1. Open `PocketMesh.xcodeproj`
2. Select PocketMesh scheme
3. Press `Cmd+U` to run all tests
4. Use Test Navigator (Cmd+6) to run individual tests

## Test Coverage Goals

| Layer | Target | Current Focus |
|-------|--------|---------------|
| Protocol | 100% | Frame encoding/decoding |
| Services | >80% | Core business logic |
| ViewModels | >60% | UI logic |
| Integration | Key flows | Multi-service interactions |

## Best Practices

### Do

- Use in-memory containers for DataStore tests
- Create reusable test data factories
- Test error paths, not just happy paths
- Use short timeouts in async tests
- Clean up resources in test teardown

### Don't

- Use real BLE connections in unit tests
- Depend on specific timing (use callbacks/continuations)
- Share mutable state between tests
- Skip testing edge cases (empty arrays, nil values)
- Leave commented-out test code
