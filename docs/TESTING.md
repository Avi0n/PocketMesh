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
│   ├── MessageServiceTests.swift
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
│   ├── MockBLEIntegrationTests.swift
│   └── RemoteNodeIntegrationTests.swift
├── ViewModels/              # ViewModel tests
│   └── ChatViewModelTests.swift
├── Models/                  # Model tests
│   └── RemoteNodeModelTests.swift
├── BLE/                     # BLE-specific tests
│   └── BLEReconnectionTests.swift
└── Helpers/                 # Test utilities
    └── TestHelpers.swift
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
let transport = MockBLETransport(mockPeripheral: mock)

// Add test contacts
await mock.addContact(publicKey: testKey, name: "Alice", type: .chat)

// Queue incoming message
await mock.queueIncomingMessage(
    senderPrefix: alicePrefix,
    text: "Hello",
    timestamp: currentTimestamp
)

// Simulate push notification
await mock.simulatePush(code: .messageWaiting)

// Simulate ACK confirmation
await mock.simulateSendConfirmed(ackCode: 1001, roundTripTime: 250)

// Verify state
let contactCount = await mock.contactCount
#expect(contactCount == 1)
```

### TestBLETransport

A mock `BLETransport` implementation for service testing with queued responses.

**Features:**
- Pre-configured response queue
- Failure injection
- Sent data tracking

**Usage:**

```swift
let transport = TestBLETransport()

// Configure responses
await transport.queueResponse(Data([0x00]))  // OK response
await transport.queueResponse(Data([0x06, 0x00, ...]))  // Sent response

// Inject failure
await transport.setNextSendToFail(error: .disconnected)

// Verify sent data
let sentData = await transport.getSentData()
#expect(sentData.count == 2)
#expect(sentData[0][0] == CommandCode.sendTextMessage.rawValue)

// Simulate push
await transport.simulatePush(Data([0x82, ...]))  // sendConfirmed
```

### MockKeychainService

In-memory keychain for testing secure storage.

```swift
let keychain = MockKeychainService()

await keychain.storePassword("secret123", forPublicKey: nodeKey)
let retrieved = try await keychain.retrievePassword(forPublicKey: nodeKey)
#expect(retrieved == "secret123")

// Verify storage
let allKeys = await keychain.getAllStoredKeys()
#expect(allKeys.contains(nodeKey.base64EncodedString()))

// Reset
await keychain.clear()
```

## Test Patterns

### Service Unit Test Pattern

```swift
@Suite("MessageService Tests")
struct MessageServiceTests {
    // Create test dependencies
    private func createTestStack() async throws -> (
        TestBLETransport,
        DataStore,
        MessageService
    ) {
        let transport = TestBLETransport()
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)
        let service = MessageService(transport: transport, dataStore: dataStore)
        return (transport, dataStore, service)
    }

    @Test("Send message updates status on success")
    func testSendMessageSuccess() async throws {
        let (transport, dataStore, service) = try await createTestStack()

        // Queue expected response
        await transport.queueResponse(createSentResponse(ackCode: 1001))

        // Execute
        let result = try await service.sendDirectMessage(
            deviceID: deviceID,
            contactID: contactID,
            text: "Hello",
            timestamp: timestamp
        )

        // Verify
        #expect(result.ackCode == 1001)

        // Check database state
        let message = try await dataStore.fetchMessage(byId: messageID)
        #expect(message?.status == .sent)
    }
}
```

### Integration Test Pattern

```swift
@Suite("Remote Node Integration")
struct RemoteNodeIntegrationTests {
    private func createFullStack() async throws -> ServiceStack {
        let mock = MockBLEPeripheral()
        let transport = MockBLETransport(mockPeripheral: mock)
        let container = try DataStore.createContainer(inMemory: true)
        let dataStore = DataStore(modelContainer: container)
        let keychain = MockKeychainService()

        // Wire up services
        let binaryService = BinaryProtocolService(transport: transport)
        let remoteNodeService = RemoteNodeService(
            transport: transport,
            dataStore: dataStore,
            binaryService: binaryService,
            keychainService: keychain
        )
        // ... more services

        return ServiceStack(...)
    }

    @Test("Room server flow")
    func testRoomFlow() async throws {
        let stack = try await createFullStack()

        // Create room contact
        let roomContact = createTestContact(type: .room)
        await stack.mock.addContact(roomContact)

        // Configure login response
        await stack.mock.configureLoginSuccess(isAdmin: true)

        // Test join
        let session = try await stack.roomService.joinRoom(
            publicKey: roomContact.publicKey,
            password: "secret"
        )

        #expect(session.isConnected)
        #expect(session.permissionLevel == .admin)
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
@Test("Progress handler called for each contact")
func testSyncProgress() async throws {
    let receivedProgress = MutableBox<[(Int, Int)]>([])

    await service.setProgressHandler { current, total in
        receivedProgress.value.append((current, total))
    }

    // Add test contacts
    await mock.addContact(...)
    await mock.addContact(...)
    await mock.addContact(...)

    // Trigger sync
    _ = try await service.syncContacts(deviceID: deviceID)

    // Verify progress callbacks
    #expect(receivedProgress.value.count == 3)
    #expect(receivedProgress.value[0] == (1, 3))
    #expect(receivedProgress.value[1] == (2, 3))
    #expect(receivedProgress.value[2] == (3, 3))
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

```swift
// Create test contact
func createTestContact(
    deviceID: UUID = UUID(),
    name: String = "Test",
    type: ContactType = .chat,
    publicKey: Data? = nil
) -> ContactDTO {
    return ContactDTO(
        id: UUID(),
        deviceID: deviceID,
        publicKey: publicKey ?? Data((0..<32).map { _ in UInt8.random(in: 0...255) }),
        name: name,
        typeRawValue: type.rawValue,
        // ...
    )
}

// Create response frames
func createSentResponse(ackCode: UInt32) -> Data {
    var data = Data([ResponseCode.sent.rawValue, 0])  // Not flood
    data.append(contentsOf: withUnsafeBytes(of: ackCode.littleEndian) { Array($0) })
    data.append(contentsOf: withUnsafeBytes(of: UInt32(30000).littleEndian) { Array($0) })
    return data
}

func createErrorResponse(code: ProtocolError) -> Data {
    return Data([ResponseCode.error.rawValue, code.rawValue])
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
