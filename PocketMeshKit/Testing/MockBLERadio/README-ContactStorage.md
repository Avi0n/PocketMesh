# Mock BLE Radio Contact Storage

This document describes the contact storage functionality implemented in the Mock BLE Radio for testing MeshCore contact synchronization without requiring physical hardware.

## Overview

The Mock BLE Radio now supports full contact storage and synchronization, emulating the MeshCore firmware's contact handling behavior. This enables comprehensive testing of:

- Contact synchronization with timestamp filtering
- Multi-frame contact delivery
- ContactData encoding/decoding
- Contact management operations
- Large contact list performance

## Quick Start

### Basic Usage

```swift
import PocketMeshKit

// Create a mock radio with sample contacts
let radio = MockBLERadio(deviceName: "TestDevice")
await radio.start()

// Pre-populate with sample contacts
await radio.populateSampleContacts()

// Verify contact count
let count = await radio.getContactCount()
print("Contact count: \(count)") // Output: 3

// Connect with MeshCoreProtocol
let manager = MockBLEManager(radio: radio)
let protocol = MeshCoreProtocol(bleManager: manager)

// Sync all contacts
let contacts = try await protocol.getContacts(since: nil)
print("Synced \(contacts.count) contacts")
```

### Adding Custom Contacts

```swift
// Add a specific contact for testing
await radio.addTestContact(
    publicKey: Data(repeating: 0xAB, count: 32),
    name: "Test Contact",
    type: .chat,
    flags: 0x01,
    lastAdvertisement: Date().addingTimeInterval(-3600),
    latitude: 37.7749,
    longitude: -122.4194,
    lastModified: Date()
)

// Remove a contact
let removed = await radio.removeTestContact(
    publicKey: Data(repeating: 0xAB, count: 32)
)
```

### Timestamp Filtering

```swift
// Sync only contacts modified in the last hour
let oneHourAgo = Date().addingTimeInterval(-3600)
let recentContacts = try await protocol.getContacts(since: oneHourAgo)
```

### Test Isolation

```swift
// Clear all contacts between tests
await radio.clearAllContacts()

// Re-populate for next test
await radio.populateSampleContacts()
```

## Sample Contacts

The `populateSampleContacts()` method creates three test contacts:

1. **Test Contact 1** (Chat)
   - Public Key: `0xAA...AA` (32 bytes)
   - Type: Chat (1)
   - Location: 37.7749, -122.4194
   - Last modified: 30 minutes ago

2. **Test Repeater** (Repeater)
   - Public Key: `0xBB...BB` (32 bytes)
   - Type: Repeater (2)
   - Has 4-byte out path
   - Last modified: 1 hour ago

3. **Test Room** (Room)
   - Public Key: `0xCC...CC` (32 bytes)
   - Type: Room (3)
   - Last modified: 15 minutes ago

## Contact Synchronization Protocol

The mock radio implements the exact same multi-frame sync protocol as MeshCore firmware:

### Sync Sequence

1. **CMD_GET_CONTACTS (4)** - Client sends with optional 4-byte `since` timestamp
2. **RESP_CODE_CONTACTS_START (2)** - Radio returns total contact count (unfiltered)
3. **RESP_CODE_CONTACT (3)** - Radio sends one frame per contact (filtered by timestamp)
4. **RESP_CODE_END_OF_CONTACTS (4)** - Radio sends most recent `lastmod` timestamp

### Frame Format

Each contact frame contains 147 bytes:
- Public key: 32 bytes
- Type: 1 byte (0=none, 1=chat, 2=repeater, 3=room)
- Flags: 1 byte
- Out path length: 1 byte
- Out path: 64 bytes (zero-padded)
- Name: 32 bytes (null-terminated UTF-8)
- Last advertisement: 4 bytes (Unix timestamp, little-endian)
- Latitude: 4 bytes (scaled by 1E6, little-endian)
- Longitude: 4 bytes (scaled by 1E6, little-endian)
- Last modified: 4 bytes (Unix timestamp, little-endian)

### Timestamp Filtering

Contacts are filtered using strict `>` comparison:
```swift
filtered = contacts.filter { $0.lastModified > since }
```

This matches firmware behavior:
- `since = nil` → Returns all contacts
- `since = timestamp` → Returns contacts with `lastModified > timestamp`
- `since == lastModified` → Contact excluded (strict > comparison)

## Testing Examples

### Test: Basic Contact Sync

```swift
func testBasicContactSync() async throws {
    let radio = MockBLERadio()
    await radio.start()
    await radio.populateSampleContacts()

    let manager = MockBLEManager(radio: radio)
    let protocol = MeshCoreProtocol(bleManager: manager)

    let contacts = try await protocol.getContacts(since: nil)

    XCTAssertEqual(contacts.count, 3)
    XCTAssertFalse(contacts[0].publicKey.isEmpty)
    XCTAssertFalse(contacts[0].name.isEmpty)
}
```

### Test: Timestamp Filtering

```swift
func testTimestampFiltering() async throws {
    let radio = MockBLERadio()
    await radio.start()

    let now = Date()

    // Add contacts with specific timestamps
    await radio.addTestContact(
        publicKey: Data(repeating: 0x01, count: 32),
        name: "Old Contact",
        lastModified: now.addingTimeInterval(-7200) // 2 hours ago
    )

    await radio.addTestContact(
        publicKey: Data(repeating: 0x02, count: 32),
        name: "Recent Contact",
        lastModified: now.addingTimeInterval(-1800) // 30 minutes ago
    )

    let manager = MockBLEManager(radio: radio)
    let protocol = MeshCoreProtocol(bleManager: manager)

    // Sync contacts modified in the last hour
    let oneHourAgo = now.addingTimeInterval(-3600)
    let recentContacts = try await protocol.getContacts(since: oneHourAgo)

    XCTAssertEqual(recentContacts.count, 1)
    XCTAssertEqual(recentContacts[0].name, "Recent Contact")
}
```

### Test: Large Contact Lists

```swift
func testLargeContactList() async throws {
    let radio = MockBLERadio()
    await radio.start()

    // Add 100+ contacts
    for i in 0..<105 {
        await radio.addTestContact(
            publicKey: Data(repeating: UInt8(i % 256), count: 32),
            name: "Contact \(i)",
            type: .chat
        )
    }

    let manager = MockBLEManager(radio: radio)
    let protocol = MeshCoreProtocol(bleManager: manager)

    let contacts = try await protocol.getContacts()

    XCTAssertEqual(contacts.count, 105)
}
```

### Test: Contact Discovery Simulation

```swift
func testContactDiscovery() async throws {
    let radio = MockBLERadio()
    await radio.start()

    // Simulate discovering a contact from advertisement
    await radio.simulateContactDiscovery(
        publicKey: Data(repeating: 0xCD, count: 32),
        name: "Discovered Contact",
        latitude: 37.7749,
        longitude: -122.4194
    )

    let manager = MockBLEManager(radio: radio)
    let protocol = MeshCoreProtocol(bleManager: manager)

    let contacts = try await protocol.getContacts()

    XCTAssertEqual(contacts.count, 1)
    XCTAssertEqual(contacts[0].name, "Discovered Contact")
    XCTAssertEqual(contacts[0].type, .chat)
}
```

## API Reference

### MockBLERadio Contact Methods

```swift
/// Add a contact for testing
func addTestContact(
    publicKey: Data,
    name: String,
    type: ContactType = .chat,
    flags: UInt8 = 0x01,
    outPath: Data? = nil,
    lastAdvertisement: Date = Date(),
    latitude: Double? = nil,
    longitude: Double? = nil,
    lastModified: Date = Date()
) async

/// Remove a contact by public key
func removeTestContact(publicKey: Data) async -> Bool

/// Get current contact count
func getContactCount() async -> Int

/// Pre-populate with sample test contacts
func populateSampleContacts() async

/// Clear all contacts
func clearAllContacts() async

/// Simulate contact discovery from advertisement
func simulateContactDiscovery(
    publicKey: Data,
    name: String,
    latitude: Double? = nil,
    longitude: Double? = nil
) async
```

## Implementation Details

### Thread Safety

All contact operations are protected by the `BLERadioState` actor, ensuring thread-safe concurrent access:

```swift
// Safe to call from multiple tasks
Task {
    await radio.addTestContact(...)
}

Task {
    let count = await radio.getContactCount()
}
```

### Multi-Frame Delivery

Contacts are delivered via the offline message queue:

1. `handleGetContacts()` enqueues all contact frames
2. Client polls with `CMD_SYNC_NEXT_MESSAGE (10)`
3. `handleSyncNextMessage()` dequeues frames one at a time
4. Client receives contacts incrementally until `END_OF_CONTACTS`

This matches the firmware's iterator-based delivery pattern.

### Memory Efficiency

- Contacts stored in memory only (appropriate for testing)
- Iterator uses references, not copies
- Efficient filtering during iterator creation
- Suitable for 100+ contacts

### Firmware Compatibility

The implementation matches MeshCore firmware v8 behavior:

- Contact payload format byte-for-byte compatible
- Timestamp filtering uses identical logic
- Response codes match firmware exactly
- Multi-frame sync pattern identical

## Edge Cases

### Empty Contact List

```swift
await radio.clearAllContacts()
let contacts = try await protocol.getContacts()
// Returns: empty array
// END_OF_CONTACTS timestamp: 0
```

### Exact Timestamp Match

```swift
let contact = contacts.last!
let exactTime = contact.lastModified

// Contact with exact timestamp is EXCLUDED
let filtered = try await protocol.getContacts(since: exactTime)
// Returns: empty (firmware uses strict > comparison)
```

### Total vs Filtered Count

```swift
await radio.populateSampleContacts() // 3 contacts

let oneHourAgo = Date().addingTimeInterval(-3600)
let recent = try await protocol.getContacts(since: oneHourAgo)
// CONTACTS_START count: 3 (total, not filtered)
// Actual contacts delivered: varies based on timestamps
```

## Verification Script

Run the integration verification script to check all functionality:

```bash
swift scripts/test_mock_contact_integration.swift
```

This verifies:
- ✅ Contact encoding format
- ✅ Multi-frame response sequence
- ✅ Timestamp filtering logic
- ✅ Thread safety
- ✅ Test API availability
- ✅ Offline queue integration
- ✅ Edge case handling

## Troubleshooting

### Contacts Not Syncing

Check that:
1. Radio is started: `await radio.start()`
2. Contacts are added: `await radio.getContactCount()`
3. Protocol is connected to mock manager
4. Timestamp filtering isn't excluding all contacts

### Incorrect Contact Count

Remember:
- `CONTACTS_START` returns **total** count (unfiltered)
- Actual contacts delivered are filtered by timestamp
- This matches firmware behavior

### Contact Fields Not Decoding

Verify:
- Public key is exactly 32 bytes
- Name is UTF-8 encoded, max 31 bytes + null terminator
- Timestamps are valid Unix timestamps (not negative)
- Lat/lon are properly scaled by 1E6

## References

- Implementation Plan: `thoughts/shared/plans/2025-01-26-mock-ble-radio-contact-storage.md`
- Firmware Reference: `MeshCore-firmware-examples/companion_radio/MyMesh.cpp`
- Protocol Layer: `PocketMeshKit/Protocol/MeshCoreProtocol+Contacts.swift`
- Mock Radio Implementation: `PocketMeshKit/Testing/MockBLERadio/MockBLERadio.swift`
- State Management: `PocketMeshKit/Testing/MockBLERadio/state/BLERadioState.swift`

## Changelog

- **2025-01-28**: Initial contact storage implementation
  - Phase 1: Contact storage in BLERadioState
  - Phase 2: CMD_GET_CONTACTS handler
  - Phase 3: Contact management test APIs
  - Phase 4: Integration verification
