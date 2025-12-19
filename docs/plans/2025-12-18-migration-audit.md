# PocketMeshKit to MeshCore Migration Audit Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Restore deleted test coverage, implement missing MeshCore spec functionality, and fix code smell issues introduced during the PocketMeshKit to MeshCore migration.

**Architecture:** Three-tier architecture with MeshCore (protocol layer) → PocketMeshServices (business logic with actor isolation) → PocketMesh (UI). All services use actor isolation for thread safety and AsyncStream for event communication.

**Tech Stack:** Swift 6.2, SwiftUI, SwiftData, CoreBluetooth, AccessorySetupKit, Swift Testing (@Test, #expect, @Suite)

**Reference Implementation:** `MeshCore-references/meshcore_py-2.2.4` - Python MeshCore spec (note: exists in main repo, not worktree)

---

## Audit Findings (2025-12-18)

> **Pre-execution audit completed.** The following items were found to already exist and have been removed from this plan:

| Original Task | Feature | Status |
|---------------|---------|--------|
| ~~Task 12~~ | `send_msg_with_retry` | **EXISTS** - Full implementation in `MessageService.swift` with `MessageServiceConfig` (floodFallbackOnRetry, maxAttempts, floodAfter) |
| ~~Task 13~~ | `auto_message_fetching` | **EXISTS** - `startAutoMessageFetching()` / `stopAutoMessageFetching()` in `MeshCoreSession.swift:322-345` |
| ~~Task 20~~ | `Data.hexString` utility | **EXISTS** - `PocketMeshServices/Extensions/Data+Extensions.swift` has `hexString()` and `init?(hexString:)` |
| ~~Task 21~~ | Remove duplicate hex code | **MOSTLY DONE** - Extension exists, minimal cleanup needed |

**Existing test coverage:**
- `PersistenceStoreTests.swift` - 505 lines of tests
- `PacketParserTests.swift` - 23KB of tests
- `PacketBuilderTests.swift` - 18KB of tests
- `SessionIntegrationTests.swift` - Includes auto message fetching tests

**Existing functionality:**
- `ensureContacts(force:)` exists in `MeshCoreSession.swift:307` (different parameter than `follow:`)

## Codebase Structure (verified 2025-12-18)

**Service Dependencies:**
- All services (`MessageService`, `ContactService`, `ChannelService`) depend on:
  - `session: MeshCoreSession` - for mesh network communication
  - `dataStore: PersistenceStore` - for SwiftData persistence
- `PersistenceStore` uses `@ModelActor` with synchronous SwiftData API
- All persistence operations use DTOs (e.g., `MessageDTO`, `ContactDTO`, `ChannelDTO`)

**Models:**
- SwiftData `@Model` classes: `Message`, `Contact`, `Channel`, `Device`, `RemoteNodeSession`, `RoomMessage`
- Sendable DTOs: `MessageDTO`, `ContactDTO`, `ChannelDTO`, `DeviceDTO`, `RemoteNodeSessionDTO`, `RoomMessageDTO`
- Operations are device-scoped (use `deviceID: UUID` parameter)

**Revised plan: 10 active tasks** (8 skipped/completed)

---

## Part 1: Protocol Abstractions (Testability Prerequisites)

> **Review Finding:** Protocols must exist before mocks can be created. These tasks establish the abstractions needed for testing.

### Task 1: Create MeshCoreSessionProtocol

> **Rationale:** Services depend on MeshCoreSession for mesh communication. Creating a protocol allows mocking session behavior in tests without requiring a real BLE connection.

**Files:**
- Create: `MeshCore/Sources/MeshCore/Protocols/MeshCoreSessionProtocol.swift`

**Step 1: Create protocol definition with core methods used by services**

```swift
import Foundation

/// Protocol for MeshCoreSession to enable testability of dependent services.
/// Services use this protocol to abstract mesh communication operations.
public protocol MeshCoreSessionProtocol: Actor {
    // Connection state
    var isConnected: Bool { get }

    // Message operations (used by MessageService)
    func sendDirectMessage(
        to publicKey: Data,
        text: String,
        textType: TextType
    ) async throws -> MessageSentInfo

    func sendChannelMessage(
        channelIndex: UInt8,
        text: String
    ) async throws -> MessageSentInfo

    // Contact operations (used by ContactService)
    func getContacts(since: Date?) async throws -> [MeshContact]
    func addContact(_ contact: ContactFrame) async throws
    func removeContact(publicKey: Data) async throws
    func resetPath(for publicKey: Data) async throws
    func sendPathDiscovery(to publicKey: Data) async throws -> MessageSentInfo

    // Channel operations (used by ChannelService)
    func getChannelInfo(index: UInt8) async throws -> ChannelInfo
    func setChannel(index: UInt8, info: ChannelInfo) async throws
}
```

**Step 2: Run to verify compiles**

Run: `swift build --package-path MeshCore 2>&1 | xcsift`
Expected: Build succeeds

**Step 3: Update MeshCoreSession to conform**

Add `: MeshCoreSessionProtocol` conformance to existing MeshCoreSession actor.

**Step 4: Run to verify compiles**

Run: `swift build --package-path MeshCore 2>&1 | xcsift`
Expected: Build succeeds

**Step 5: Commit**

```bash
git add -A
git commit -m "refactor: add MeshCoreSessionProtocol for testability"
```

---

### Task 2: Create PersistenceStoreProtocol (Focused Subset)

> **Rationale:** PersistenceStore has 50+ methods. Create a focused protocol with only the methods needed for service testing. This is more maintainable than a 1:1 protocol.

**Files:**
- Create: `PocketMeshServices/Sources/PocketMeshServices/Protocols/PersistenceStoreProtocol.swift`

**Step 1: Create focused protocol definition**

```swift
import Foundation

/// Focused protocol for PersistenceStore operations used by services.
/// Enables testability without exposing all 50+ PersistenceStore methods.
public protocol PersistenceStoreProtocol: Sendable {
    // Message operations (used by MessageService)
    func saveMessage(_ dto: MessageDTO) throws
    func fetchMessages(contactID: UUID, limit: Int, offset: Int) throws -> [MessageDTO]
    func fetchMessages(deviceID: UUID, channelIndex: UInt8, limit: Int, offset: Int) throws -> [MessageDTO]
    func updateMessageStatus(id: UUID, status: MessageStatus) throws
    func updateMessageAck(id: UUID, ackCode: UInt32, status: MessageStatus, roundTripTime: UInt32?) throws
    func isDuplicateMessage(deduplicationKey: String) throws -> Bool

    // Contact operations (used by ContactService)
    func fetchContacts(deviceID: UUID) throws -> [ContactDTO]
    func fetchContact(deviceID: UUID, publicKey: Data) throws -> ContactDTO?
    func saveContact(_ dto: ContactDTO) throws
    func deleteContact(id: UUID) throws
    func updateContactLastMessage(contactID: UUID, date: Date) throws

    // Channel operations (used by ChannelService)
    func fetchChannels(deviceID: UUID) throws -> [ChannelDTO]
    func fetchChannel(deviceID: UUID, index: UInt8) throws -> ChannelDTO?
    func saveChannel(_ dto: ChannelDTO) throws
    func deleteChannel(id: UUID) throws
}
```

**Step 2: Run to verify compiles**

Run: `swift build --package-path PocketMeshServices 2>&1 | xcsift`
Expected: Build succeeds

**Step 3: Update PersistenceStore to conform**

Add `: PersistenceStoreProtocol` conformance to existing PersistenceStore actor.

**Step 4: Run to verify compiles**

Run: `swift build --package-path PocketMeshServices 2>&1 | xcsift`
Expected: Build succeeds

**Step 5: Commit**

```bash
git add -A
git commit -m "refactor: add PersistenceStoreProtocol for testability"
```

---

### Task 3: Update Services to Accept Protocols ⏭️ DEFERRED

> **Decision:** Deferred - requires significant refactoring of service initializers.
>
> **Current state:** Services use concrete types (`MeshCoreSession`, `PersistenceStore`)
> **Required change:** Services accept protocol types (`any MeshCoreSessionProtocol`, `any PersistenceStoreProtocol`)
>
> This change has cascading effects through the codebase and should be done as a separate focused effort after Tasks 1-2 are validated.

---

## Part 2: Restore PocketMeshServices Test Coverage

### Task 4: Create Test Mocks

**Files:**
- Create: `PocketMeshServices/Tests/PocketMeshServicesTests/Mocks/MockMeshCoreSession.swift`
- Create: `PocketMeshServices/Tests/PocketMeshServicesTests/Mocks/MockPersistenceStore.swift`

**Step 1: Create MockMeshCoreSession**

```swift
import Foundation
import MeshCore
@testable import PocketMeshServices

/// Mock session for testing services without real BLE connection
actor MockMeshCoreSession: MeshCoreSessionProtocol {
    var isConnected: Bool = true

    // Tracking for verification
    var sentDirectMessages: [(publicKey: Data, text: String, textType: TextType)] = []
    var sentChannelMessages: [(channelIndex: UInt8, text: String)] = []
    var addedContacts: [ContactFrame] = []
    var removedContactKeys: [Data] = []

    // Configurable responses
    var contactsToReturn: [MeshContact] = []
    var channelInfoToReturn: [UInt8: ChannelInfo] = [:]
    var shouldThrowError: Error?

    func sendDirectMessage(to publicKey: Data, text: String, textType: TextType) async throws -> MessageSentInfo {
        if let error = shouldThrowError { throw error }
        sentDirectMessages.append((publicKey, text, textType))
        return MessageSentInfo(ackCode: Data([0x01, 0x02, 0x03, 0x04]), expectedTimeout: 30.0)
    }

    func sendChannelMessage(channelIndex: UInt8, text: String) async throws -> MessageSentInfo {
        if let error = shouldThrowError { throw error }
        sentChannelMessages.append((channelIndex, text))
        return MessageSentInfo(ackCode: Data([0x01, 0x02, 0x03, 0x04]), expectedTimeout: 30.0)
    }

    func getContacts(since: Date?) async throws -> [MeshContact] {
        if let error = shouldThrowError { throw error }
        return contactsToReturn
    }

    func addContact(_ contact: ContactFrame) async throws {
        if let error = shouldThrowError { throw error }
        addedContacts.append(contact)
    }

    func removeContact(publicKey: Data) async throws {
        if let error = shouldThrowError { throw error }
        removedContactKeys.append(publicKey)
    }

    func resetPath(for publicKey: Data) async throws {
        if let error = shouldThrowError { throw error }
    }

    func sendPathDiscovery(to publicKey: Data) async throws -> MessageSentInfo {
        if let error = shouldThrowError { throw error }
        return MessageSentInfo(ackCode: Data([0x01, 0x02, 0x03, 0x04]), expectedTimeout: 30.0)
    }

    func getChannelInfo(index: UInt8) async throws -> ChannelInfo {
        if let error = shouldThrowError { throw error }
        guard let info = channelInfoToReturn[index] else {
            throw ChannelServiceError.channelNotFound
        }
        return info
    }

    func setChannel(index: UInt8, info: ChannelInfo) async throws {
        if let error = shouldThrowError { throw error }
        channelInfoToReturn[index] = info
    }
}
```

**Step 2: Create MockPersistenceStore**

```swift
import Foundation
@testable import PocketMeshServices

/// Mock persistence for testing services without SwiftData
actor MockPersistenceStore: PersistenceStoreProtocol {
    // Storage
    var messages: [UUID: MessageDTO] = [:]
    var contacts: [UUID: ContactDTO] = [:]
    var channels: [UUID: ChannelDTO] = [:]
    var duplicateKeys: Set<String> = []

    // Call tracking
    var saveMessageCalls: [MessageDTO] = []
    var updateStatusCalls: [(id: UUID, status: MessageStatus)] = []

    // Configurable error
    var shouldThrowError: Error?

    nonisolated func saveMessage(_ dto: MessageDTO) throws {
        // Note: For actor isolation, actual impl would need async
    }

    nonisolated func fetchMessages(contactID: UUID, limit: Int, offset: Int) throws -> [MessageDTO] {
        []
    }

    nonisolated func fetchMessages(deviceID: UUID, channelIndex: UInt8, limit: Int, offset: Int) throws -> [MessageDTO] {
        []
    }

    nonisolated func updateMessageStatus(id: UUID, status: MessageStatus) throws {}

    nonisolated func updateMessageAck(id: UUID, ackCode: UInt32, status: MessageStatus, roundTripTime: UInt32?) throws {}

    nonisolated func isDuplicateMessage(deduplicationKey: String) throws -> Bool {
        false
    }

    nonisolated func fetchContacts(deviceID: UUID) throws -> [ContactDTO] {
        []
    }

    nonisolated func fetchContact(deviceID: UUID, publicKey: Data) throws -> ContactDTO? {
        nil
    }

    nonisolated func saveContact(_ dto: ContactDTO) throws {}

    nonisolated func deleteContact(id: UUID) throws {}

    nonisolated func updateContactLastMessage(contactID: UUID, date: Date) throws {}

    nonisolated func fetchChannels(deviceID: UUID) throws -> [ChannelDTO] {
        []
    }

    nonisolated func fetchChannel(deviceID: UUID, index: UInt8) throws -> ChannelDTO? {
        nil
    }

    nonisolated func saveChannel(_ dto: ChannelDTO) throws {}

    nonisolated func deleteChannel(id: UUID) throws {}
}
```

**Step 3: Run to verify compiles**

Run: `swift build --package-path PocketMeshServices 2>&1 | xcsift`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add PocketMeshServices/Tests/PocketMeshServicesTests/Mocks/
git commit -m "test: add MockMeshCoreSession and MockPersistenceStore"
```

---

### Task 5: Create ChannelService Unit Tests

> **Note:** Testing ChannelService first because it has the simplest interface (static hashSecret method, fewer dependencies on MeshCoreSession state).

**Files:**
- Create: `PocketMeshServices/Tests/PocketMeshServicesTests/Services/ChannelServiceTests.swift`

**Step 1: Create the test file**

```swift
import Testing
import Foundation
import CryptoKit
@testable import PocketMeshServices
@testable import MeshCore

@Suite("ChannelService Tests")
struct ChannelServiceTests {

    // MARK: - Secret Hashing Tests

    @Test("hashSecret produces 16-byte output")
    func hashSecretProduces16Bytes() {
        let secret = ChannelService.hashSecret("test passphrase")
        #expect(secret.count == 16)
    }

    @Test("hashSecret is deterministic")
    func hashSecretIsDeterministic() {
        let secret1 = ChannelService.hashSecret("same passphrase")
        let secret2 = ChannelService.hashSecret("same passphrase")
        #expect(secret1 == secret2)
    }

    @Test("hashSecret differs for different inputs")
    func hashSecretDiffersForDifferentInputs() {
        let secret1 = ChannelService.hashSecret("passphrase one")
        let secret2 = ChannelService.hashSecret("passphrase two")
        #expect(secret1 != secret2)
    }

    @Test("hashSecret handles empty string")
    func hashSecretHandlesEmptyString() {
        let secret = ChannelService.hashSecret("")
        #expect(secret.count == 16)
        #expect(secret == Data(repeating: 0, count: 16))
    }

    @Test("hashSecret handles unicode")
    func hashSecretHandlesUnicode() {
        let secret = ChannelService.hashSecret("🔐 secure 密码")
        #expect(secret.count == 16)
    }

    @Test("validateSecret accepts 16-byte secrets")
    func validateSecretAccepts16Bytes() {
        let validSecret = Data(repeating: 0xAB, count: 16)
        #expect(ChannelService.validateSecret(validSecret))
    }

    @Test("validateSecret rejects wrong-sized secrets")
    func validateSecretRejectsWrongSize() {
        let tooShort = Data(repeating: 0xAB, count: 15)
        let tooLong = Data(repeating: 0xAB, count: 17)
        #expect(!ChannelService.validateSecret(tooShort))
        #expect(!ChannelService.validateSecret(tooLong))
    }
}
```

**Step 2: Run tests**

Run: `swift test --package-path PocketMeshServices --filter ChannelServiceTests 2>&1 | xcsift`
Expected: PASS

**Step 3: Commit**

```bash
git add PocketMeshServices/Tests/PocketMeshServicesTests/Services/ChannelServiceTests.swift
git commit -m "test: add ChannelService unit tests for secret hashing"
```

---

### Task 6: Create MessageService Unit Tests

> **Note:** Testing the `PendingAck` struct and config validation which don't require mocked dependencies.

**Files:**
- Create: `PocketMeshServices/Tests/PocketMeshServicesTests/Services/MessageServiceTests.swift`

**Step 1: Create the test file**

```swift
import Testing
import Foundation
@testable import PocketMeshServices
@testable import MeshCore

@Suite("MessageService Tests")
struct MessageServiceTests {

    // MARK: - PendingAck Tests

    @Test("PendingAck isExpired returns false when within timeout")
    func pendingAckNotExpiredWithinTimeout() {
        let ack = PendingAck(
            messageID: UUID(),
            ackCode: Data([0x01, 0x02, 0x03, 0x04]),
            sentAt: Date(),
            timeout: 30.0
        )
        #expect(!ack.isExpired)
    }

    @Test("PendingAck isExpired returns true after timeout")
    func pendingAckExpiredAfterTimeout() {
        let ack = PendingAck(
            messageID: UUID(),
            ackCode: Data([0x01, 0x02, 0x03, 0x04]),
            sentAt: Date().addingTimeInterval(-31), // 31 seconds ago
            timeout: 30.0
        )
        #expect(ack.isExpired)
    }

    @Test("PendingAck isExpired returns false when delivered")
    func pendingAckNotExpiredWhenDelivered() {
        var ack = PendingAck(
            messageID: UUID(),
            ackCode: Data([0x01, 0x02, 0x03, 0x04]),
            sentAt: Date().addingTimeInterval(-31),
            timeout: 30.0
        )
        ack.isDelivered = true
        #expect(!ack.isExpired)
    }

    @Test("PendingAck ackCodeUInt32 converts correctly")
    func pendingAckCodeConversion() {
        let ack = PendingAck(
            messageID: UUID(),
            ackCode: Data([0x01, 0x02, 0x03, 0x04]), // Little-endian: 0x04030201
            sentAt: Date(),
            timeout: 30.0
        )
        #expect(ack.ackCodeUInt32 == 0x04030201)
    }

    @Test("PendingAck ackCodeUInt32 handles short data")
    func pendingAckCodeHandlesShortData() {
        let ack = PendingAck(
            messageID: UUID(),
            ackCode: Data([0x01, 0x02]), // Only 2 bytes
            sentAt: Date(),
            timeout: 30.0
        )
        #expect(ack.ackCodeUInt32 == 0)
    }

    // MARK: - MessageServiceConfig Tests

    @Test("MessageServiceConfig default values")
    func messageServiceConfigDefaults() {
        let config = MessageServiceConfig.default
        #expect(config.floodFallbackOnRetry == true)
        #expect(config.maxAttempts == 4)
        #expect(config.maxFloodAttempts == 2)
        #expect(config.floodAfter == 2)
        #expect(config.minTimeout == 0)
        #expect(config.triggerPathDiscoveryAfterFlood == true)
    }

    @Test("MessageServiceConfig custom values")
    func messageServiceConfigCustomValues() {
        let config = MessageServiceConfig(
            floodFallbackOnRetry: false,
            maxAttempts: 5,
            maxFloodAttempts: 3,
            floodAfter: 3,
            minTimeout: 10.0,
            triggerPathDiscoveryAfterFlood: false
        )
        #expect(config.floodFallbackOnRetry == false)
        #expect(config.maxAttempts == 5)
        #expect(config.maxFloodAttempts == 3)
        #expect(config.floodAfter == 3)
        #expect(config.minTimeout == 10.0)
        #expect(config.triggerPathDiscoveryAfterFlood == false)
    }
}
```

**Step 2: Run tests**

Run: `swift test --package-path PocketMeshServices --filter MessageServiceTests 2>&1 | xcsift`
Expected: PASS

**Step 3: Commit**

```bash
git add PocketMeshServices/Tests/PocketMeshServicesTests/Services/MessageServiceTests.swift
git commit -m "test: add MessageService unit tests for PendingAck and config"
```

---

### Task 7: Create ContactService Unit Tests

> **Note:** Testing the DTO conversion extensions which are pure functions.

**Files:**
- Create: `PocketMeshServices/Tests/PocketMeshServicesTests/Services/ContactServiceTests.swift`

**Step 1: Create the test file**

```swift
import Testing
import Foundation
@testable import PocketMeshServices
@testable import MeshCore

@Suite("ContactService Tests")
struct ContactServiceTests {

    // MARK: - ContactSyncResult Tests

    @Test("ContactSyncResult initializes correctly")
    func contactSyncResultInitializes() {
        let result = ContactSyncResult(
            contactsReceived: 5,
            lastSyncTimestamp: 1234567890,
            isIncremental: true
        )
        #expect(result.contactsReceived == 5)
        #expect(result.lastSyncTimestamp == 1234567890)
        #expect(result.isIncremental == true)
    }

    @Test("ContactSyncResult handles zero contacts")
    func contactSyncResultHandlesZero() {
        let result = ContactSyncResult(
            contactsReceived: 0,
            lastSyncTimestamp: 0,
            isIncremental: false
        )
        #expect(result.contactsReceived == 0)
        #expect(result.isIncremental == false)
    }

    // MARK: - ContactServiceError Tests

    @Test("ContactServiceError cases are distinct")
    func contactServiceErrorCasesDistinct() {
        let errors: [ContactServiceError] = [
            .notConnected,
            .sendFailed,
            .invalidResponse,
            .syncInterrupted,
            .contactNotFound,
            .contactTableFull
        ]

        // Verify all cases are distinct (no duplicates)
        let errorDescriptions = errors.map { String(describing: $0) }
        let uniqueDescriptions = Set(errorDescriptions)
        #expect(errorDescriptions.count == uniqueDescriptions.count)
    }
}
```

**Step 2: Run tests**

Run: `swift test --package-path PocketMeshServices --filter ContactServiceTests 2>&1 | xcsift`
Expected: PASS

**Step 3: Commit**

```bash
git add PocketMeshServices/Tests/PocketMeshServicesTests/Services/ContactServiceTests.swift
git commit -m "test: add ContactService unit tests"
```

---

## Part 3: BLE Transport Tests ⏭️ DEFERRED

> **Decision:** BLE transport tests are deferred because:
> 1. `iOSBLETransport` uses a delegate pattern with `iOSBLEDelegate`
> 2. The delegate manages `CBCentralManager` and `CBPeripheral` directly
> 3. Creating testable abstractions requires significant refactoring
>
> **Existing coverage:** The transport is well-tested through integration tests in `SessionIntegrationTests.swift`

~~### Task 8: Create BLE Transport Tests~~
~~### Task 9: Add AccessorySetupKit State Restoration Test~~

---

## Part 3: Code Smell Fixes ⏭️ MOSTLY SKIPPED

### Tasks 10-13: Extract/Replace Constants ⏭️ SKIPPED

> **Decision:** After analysis, these tasks are unnecessary.
>
> **Reasoning:**
> - `SessionConfiguration.swift` already exists with `defaultTimeout` configuration
> - `BLEServiceUUID.swift` already exists with Nordic UART service UUIDs
> - `iOSBLETransport.swift` uses named inline constants (`pairingWindowDuration`, `connectionTimeout`, etc.)
> - MeshCoreSession uses `configuration.defaultTimeout` throughout
> - Remaining "magic numbers" are actually sensible parameter defaults (e.g., `maxAttempts: Int = 3`)
>
> **Existing infrastructure:**
> - `MeshCore/Sources/MeshCore/Session/SessionConfiguration.swift` - Session config
> - `PocketMeshServices/Sources/PocketMeshServices/Transport/BLEServiceUUID.swift` - BLE UUIDs

~~### Task 10: Extract Constants from MeshCoreSession~~
~~### Task 11: Replace Magic Numbers in MeshCoreSession~~
~~### Task 12: Extract Constants from iOSBLETransport~~
~~### Task 13: Replace Magic Numbers in iOSBLETransport~~

<details>
<summary>Original task details (collapsed)</summary>

**Task 10 Files:**
- Create: `MeshCore/Sources/MeshCore/Constants/SessionConstants.swift`
- Modify: `MeshCore/Sources/MeshCore/Session/MeshCoreSession.swift`

**Task 11 Files:**
- Modify: `MeshCore/Sources/MeshCore/Session/MeshCoreSession.swift`

**Task 12 Files:**
- Create: `PocketMeshServices/Sources/PocketMeshServices/Constants/BLEConstants.swift`
- Modify: `PocketMeshServices/Sources/PocketMeshServices/Transport/iOSBLETransport.swift`

**Task 13 Files:**
- Modify: `PocketMeshServices/Sources/PocketMeshServices/Transport/iOSBLETransport.swift`

</details>

---

### Task 14: Fix C-style String Formatting ✅ COMPLETED

> **Status:** Completed in commit `b78b0f0`. Fixed all C-style number formatting (`String(format: "%.Xf")`) across 8 files using modern `.formatted()` API. Hex formatting (`%02X`) kept as-is since it's the standard Swift approach.

**Files:**
- Modify: Multiple files (22 files use `String(format:)`)

**Step 1: Search for C-style formatting**

Run: `grep -r "String(format:" PocketMeshServices/Sources/ PocketMesh/`

**Step 2: Replace each occurrence**

Replace:
```swift
String(format: "%.2f", value)
```

With:
```swift
value.formatted(.number.precision(.fractionLength(2)))
```

**Step 3: Run tests to verify no regression**

Run: `swift test --package-path PocketMeshServices 2>&1 | xcsift`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add -A
git commit -m "refactor: replace C-style String(format:) with modern formatting"
```

---

### Task 15: Split MeshCoreSession (1579 lines) ⏭️ SKIPPED

> **Decision:** After analysis, decided NOT to split this file.
>
> **Reasoning:**
> - File is already well-organized with 14 clear `// MARK: -` sections
> - Single responsibility: all code relates to device communication
> - Splitting into separate actors would require coordination complexity
> - Extensions just shuffle code without improving design
> - 1579 lines is large but manageable with good organization
>
> **Analysis findings:** The file has logical groupings (Commands ~215 lines, Device Config ~200 lines, Messaging ~115 lines) but they're cohesive parts of the same actor. Splitting would add indirection without benefit.

---

### Task 16: Split PersistenceStore (1240 lines) ⏭️ SKIPPED

> **Decision:** After analysis, decided NOT to split this file.
>
> **Reasoning:**
> - File is already well-organized with 11 clear `// MARK: -` sections
> - Single responsibility: all code relates to SwiftData persistence
> - Splitting would require separate actors or complex coordination
> - Contact Operations (253 lines) and Message Operations (239 lines) are largest sections but cohesive
> - 1240 lines is manageable with good organization
>
> **Analysis findings:** The file handles Device, Contact, Message, Channel, RemoteNodeSession, and RoomMessage operations. These are all persistence concerns that benefit from being in one actor for transaction coordination.

---

## Part 4: Add Missing Documentation

### Task 8: Add MeshCore Public API Documentation

**Files:**
- Modify: `MeshCore/Sources/MeshCore/Session/MeshCoreSession.swift`
- Modify: `MeshCore/Sources/MeshCore/Events/MeshEvent.swift`

**Step 1: Add documentation to MeshCoreSession**

```swift
/// The main session actor for managing mesh network connections.
///
/// `MeshCoreSession` handles:
/// - Connection lifecycle management
/// - Packet serialization and parsing
/// - Event distribution to subscribers
///
/// ## Usage
///
/// ```swift
/// let session = MeshCoreSession(transport: bleTransport)
/// try await session.connect()
///
/// for await event in session.events {
///     switch event {
///     case .connected:
///         print("Connected to mesh")
///     case .message(let msg):
///         print("Received: \(msg)")
///     }
/// }
/// ```
public actor MeshCoreSession {
    // ...
}
```

**Step 2: Add documentation to MeshEvent**

Document all event cases with usage examples.

**Step 3: Run to verify compiles**

Run: `swift build --package-path MeshCore 2>&1 | xcsift`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add -A
git commit -m "docs: add public API documentation to MeshCore"
```

---

### Task 9: Add PocketMeshServices Public API Documentation

**Files:**
- Modify: `PocketMeshServices/Sources/PocketMeshServices/ConnectionManager.swift`
- Modify: `PocketMeshServices/Sources/PocketMeshServices/Services/MessageService.swift`

**Step 1: Add documentation to ConnectionManager**

Document the primary entry point for the services layer.

**Step 2: Add documentation to MessageService**

Document messaging APIs with usage examples.

**Step 3: Run to verify compiles**

Run: `swift build --package-path PocketMeshServices 2>&1 | xcsift`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add -A
git commit -m "docs: add public API documentation to PocketMeshServices"
```

---

## Summary

This plan addresses:

1. **Protocol Abstractions** (Tasks 1-2)
   - MeshCoreSessionProtocol - for testing services without BLE
   - PersistenceStoreProtocol - focused subset for service testing

2. **Test Coverage Restoration** (Tasks 4-7)
   - Mock infrastructure (MockMeshCoreSession, MockPersistenceStore)
   - ChannelService tests (secret hashing, validation)
   - MessageService tests (PendingAck, config)
   - ContactService tests (sync result, errors)

3. **Code Smell Fixes** ⏭️ MOSTLY SKIPPED
   - Task 14 (C-style formatting): ✅ Already completed
   - Tasks 10-13, 15-16: Skipped after analysis

4. **Documentation** (Tasks 8-9, renumbered from 17-18)
   - Add public API docs to MeshCore
   - Add public API docs to PocketMeshServices

**Active Tasks: 7** (Tasks 1-2, 4-7, 8-9)
**Deferred Tasks: 2** (Task 3: Service protocol updates, BLE Transport tests)
**Skipped/Completed: 9** (Tasks 10-16, original 8-9)

---

## Already Implemented (Removed from Plan)

| Feature | Location | Notes |
|---------|----------|-------|
| `send_msg_with_retry` | `MessageService.swift` | Full retry logic with flood fallback |
| `auto_message_fetching` | `MeshCoreSession.swift:322-345` | `startAutoMessageFetching()` / `stopAutoMessageFetching()` |
| `Data.hexString` | `Data+Extensions.swift` | Both `hexString()` and `init?(hexString:)` |
| Protocol layer tests | `PacketParserTests.swift`, `PacketBuilderTests.swift` | Extensive coverage (23KB + 18KB) |
| C-style formatting | Multiple files | Fixed in commit `b78b0f0` |

---

## Review Findings Addressed

| Priority | Issue | Resolution |
|----------|-------|------------|
| High | Create protocol abstractions before mocks | Tasks 1-2: MeshCoreSessionProtocol, PersistenceStoreProtocol |
| High | AccessorySetupKit state restoration test | ⏭️ Deferred - requires transport refactoring |
| Medium | Test services without BLE dependencies | Tasks 5-7: Unit tests for pure functions |
| Medium | Extract constants, fix magic numbers | ⏭️ Skipped - infrastructure already exists |
| Medium | Fix C-style string formatting | ✅ Completed in commit `b78b0f0` |
| Medium | Split large files | ⏭️ Skipped - files well-organized with MARK sections |
| Low | Add public API documentation | Tasks 8-9 |
