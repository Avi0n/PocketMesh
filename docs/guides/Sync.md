# Sync Guide

This guide covers the SyncCoordinator, connection lifecycle phases, and sync flows in PocketMesh.

## Overview

When PocketMesh connects to a MeshCore device, it must synchronize local data with the device's state. The `SyncCoordinator` orchestrates this process through three phases: contacts, channels, and messages.

## SyncCoordinator

**File:** `PocketMeshServices/Sources/PocketMeshServices/SyncCoordinator.swift`

```swift
public actor SyncCoordinator {
    public enum SyncPhase: Sendable, Equatable {
        case contacts
        case channels
        case messages
    }

    public enum SyncState: Sendable, Equatable {
        case idle
        case syncing(progress: SyncProgress)
        case synced
        case failed(SyncCoordinatorError)
    }
}
```

## Connection Lifecycle

```
BLE Connected
      │
      ▼
┌─────────────────────────────────────────────────────────────┐
│  1. WIRE MESSAGE HANDLERS                                   │
│     Set up callbacks BEFORE events can arrive               │
│     • Contact message handler                               │
│     • Channel message handler                               │
│     • Signed message handler (room servers)                 │
│     • CLI message handler (repeater admin)                  │
└─────────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────────┐
│  2. START EVENT MONITORING                                  │
│     Begin processing events from device                     │
│     Handlers are ready to receive                           │
└─────────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────────┐
│  3. PERFORM FULL SYNC                                       │
│     Synchronize data in order:                              │
│     • Contacts (with UI pill)                               │
│     • Channels (with UI pill)                               │
│     • Messages (no UI pill)                                 │
└─────────────────────────────────────────────────────────────┘
      │
      ▼
┌─────────────────────────────────────────────────────────────┐
│  4. WIRE DISCOVERY HANDLERS                                 │
│     Set up callbacks for ongoing discovery:                 │
│     • New contact discovered                                │
│     • Contact sync request (auto-add mode)                  │
└─────────────────────────────────────────────────────────────┘
      │
      ▼
Connection Ready
```

### Critical Order

The order is critical:

1. **Handlers first:** If events arrive before handlers are wired, messages are lost
2. **Event monitoring second:** Safe to start because handlers are ready
3. **Sync third:** Pulls current state from device
4. **Discovery handlers last:** For ongoing contact discovery after initial sync

## Sync Phases

### Phase 1: Contact Sync

```swift
// SyncCoordinator.performFullSync()
syncState = .syncing(progress: .contacts)
await onSyncStarted?()  // Shows UI pill

let result = try await contactService.syncContacts(
    deviceID: deviceID,
    since: lastContactSync  // Incremental if available
)
```

**ContactService.syncContacts:**

```swift
// Fetch from device
let contacts = try await session.getContacts(since: lastSync)

// Save each to local database
for contact in contacts {
    try await dataStore.saveContact(deviceID: deviceID, from: contact)
}

return ContactSyncResult(
    added: newCount,
    updated: updatedCount,
    total: contacts.count
)
```

### Phase 2: Channel Sync

```swift
syncState = .syncing(progress: .channels)

let result = try await channelService.syncChannels(
    deviceID: deviceID,
    maxChannels: 8
)
```

**ChannelService.syncChannels:**

```swift
// Query each slot (0-7)
for index in 0..<maxChannels {
    let config = try await session.getChannel(index: UInt8(index))

    if let config {
        try await dataStore.saveChannel(deviceID: deviceID, index: index, config: config)
    }
}
```

### Phase 3: Message Sync

```swift
// Note: No UI pill for message phase
await onSyncEnded?()  // Hides UI pill

syncState = .syncing(progress: .messages)

await messagePollingService.pollAllMessages()
```

**MessagePollingService.pollAllMessages:**

```swift
while true {
    let result = try await session.getMessage()

    switch result {
    case .noMessages:
        return  // Queue empty

    case .message(let message):
        // Route to appropriate handler
        await handleIncomingMessage(message)
    }
}
```

## Incremental vs Full Sync

### Incremental Sync

Used when we have a previous sync timestamp:

```swift
// Only fetch contacts modified since last sync
let contacts = try await session.getContacts(since: lastSyncDate)
```

Benefits:
- Faster sync
- Less data transfer
- Lower battery usage

### Full Sync

Used on first connection or when data may be stale:

```swift
// Fetch all contacts
let contacts = try await session.getContacts(since: nil)
```

When to use:
- First connection ever
- Device was reset
- Long time since last sync
- Data corruption suspected

## Sync Activity Callbacks

The coordinator provides callbacks for UI feedback:

```swift
public func setSyncActivityCallbacks(
    onStarted: @escaping @Sendable () async -> Void,
    onEnded: @escaping @Sendable () async -> Void
)
```

### UI Pill Display

```swift
// AppState observes sync state
var shouldShowSyncingPill: Bool {
    switch syncCoordinator.syncState {
    case .syncing(let progress):
        // Only show pill for contacts and channels
        return progress == .contacts || progress == .channels
    default:
        return false
    }
}
```

The pill is NOT shown for message sync because:
- Message polling can take variable time
- Users shouldn't wait for it
- It happens in background

## Error Handling

### Sync Errors

```swift
public enum SyncCoordinatorError: Error {
    case notConnected
    case syncInProgress
    case contactSyncFailed(Error)
    case channelSyncFailed(Error)
    case messageSyncFailed(Error)
}
```

### Recovery Strategy

```swift
do {
    try await performFullSync(...)
    syncState = .synced
} catch {
    syncState = .failed(error)

    // Log for debugging
    logger.error("Sync failed: \(error)")

    // Notify UI
    await onSyncFailed?(error)
}
```

On failure:
1. State transitions to `.failed`
2. UI shows error indicator
3. User can trigger manual retry via pull-to-refresh

## Message Handler Wiring

### Contact Message Handler

```swift
// Handles direct messages from contacts
messagePollingService.contactMessageHandler = { message, contact in
    // Create DTO
    let messageDTO = MessageDTO(
        id: UUID(),
        text: message.text,
        timestamp: Date(timeIntervalSince1970: TimeInterval(message.timestamp)),
        isIncoming: true,
        status: .delivered,
        snr: message.snr,
        pathLength: message.pathLength
    )

    // Save to database
    try await dataStore.saveMessage(messageDTO, contactID: contact.id)

    // Update unread count
    try await dataStore.incrementUnreadCount(contactID: contact.id)

    // Post notification
    NotificationCenter.default.post(name: .newMessageReceived, object: messageDTO)

    // Notify broadcaster
    await onDirectMessageReceived?(messageDTO, contact)
}
```

### Channel Message Handler

```swift
// Handles channel broadcast messages
messagePollingService.channelMessageHandler = { message, channelIndex in
    // Parse "NodeName: text" format
    let (senderName, text) = parseChannelMessage(message.text)

    let messageDTO = MessageDTO(
        id: UUID(),
        text: text,
        timestamp: Date(timeIntervalSince1970: TimeInterval(message.timestamp)),
        isIncoming: true,
        status: .delivered,
        senderNodeName: senderName
    )

    try await dataStore.saveChannelMessage(messageDTO, channelIndex: channelIndex)

    await onChannelMessageReceived?(messageDTO, channelIndex)
}
```

## Discovery Handlers

### New Contact Discovered

```swift
// Triggered when device advertises a new contact
syncCoordinator.onContactDiscovered = { contact in
    // Post notification for manual-add UI
    NotificationCenter.default.post(
        name: .newContactDiscovered,
        object: contact
    )

    // Refresh contact list
    notifyContactsChanged()
}
```

### Auto-Add Mode

```swift
// Triggered when device wants us to sync contacts
syncCoordinator.onSyncContactsRequested = { [weak self] in
    // Debounce rapid requests
    guard let self, !syncInProgress else { return }

    // Sync contacts from device
    try await contactService.syncContacts(deviceID: deviceID)
}
```

## Observable State for SwiftUI

The coordinator provides observable counters for SwiftUI updates:

```swift
@MainActor
public var contactsVersion: Int = 0

@MainActor
public var conversationsVersion: Int = 0

@MainActor
public func notifyContactsChanged() {
    contactsVersion += 1
    onContactsChanged?()
}
```

SwiftUI views observe these:

```swift
struct ContactsView: View {
    @Environment(SyncCoordinator.self) var coordinator

    var body: some View {
        List(contacts) { contact in
            ContactRow(contact: contact)
        }
        .onChange(of: coordinator.contactsVersion) {
            // Reload contacts
            Task { await loadContacts() }
        }
    }
}
```

## See Also

- [SyncCoordinator API](../api/PocketMeshServices.md#synccoordinator-public-actor)
- [Architecture Overview](../Architecture.md)
- [Messaging Guide](Messaging.md)
