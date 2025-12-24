# Sync Guide

This guide covers the SyncCoordinator, connection lifecycle phases, and sync flows in PocketMesh.

## Overview

When PocketMesh connects to a MeshCore device, it must synchronize local data with the device's state. The `SyncCoordinator` orchestrates this process through three phases: contacts, channels, and messages.

## SyncCoordinator

**File:** `PocketMeshServices/Sources/PocketMeshServices/SyncCoordinator.swift`

```swift
public actor SyncCoordinator {
    public var lastSyncDate: Date?
}

public enum SyncState: Sendable, Equatable {
    case idle
    case syncing(progress: SyncProgress)
    case synced
    case failed(SyncCoordinatorError)
}

public struct SyncProgress: Sendable, Equatable {
    public let phase: SyncPhase
    public let current: Int
    public let total: Int
}

public enum SyncPhase: Sendable, Equatable {
    case contacts
    case channels
    case messages
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
│     • Contact message handler (textType = 0x00)             │
│     • Channel message handler (textType = 0x03)             │
│     • Signed message handler (textType = 0x02, room servers)│
│     • CLI message handler (textType = 0x01, repeater admin) │
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
syncState = .syncing(progress: SyncProgress(phase: .contacts, current: 0, total: 0))
await onSyncStarted?()  // Shows UI pill

let result = try await contactService.syncContacts(
    deviceID: deviceID,
    since: lastContactSync  // Incremental if available
)
```

**ContactService.syncContacts:**

```swift
// Fetch from device
let meshContacts = try await session.getContacts(since: lastSync)

var receivedCount = 0
var lastTimestamp: UInt32 = 0

// Save each to local database
for meshContact in meshContacts {
    let frame = meshContact.toContactFrame()
    _ = try await dataStore.saveContact(deviceID: deviceID, from: frame)
    receivedCount += 1

    let modifiedTimestamp = UInt32(meshContact.lastModified.timeIntervalSince1970)
    if modifiedTimestamp > lastTimestamp {
        lastTimestamp = modifiedTimestamp
    }
}

return ContactSyncResult(
    contactsReceived: receivedCount,
    lastSyncTimestamp: lastTimestamp,
    isIncremental: lastSync != nil
)
```

### Phase 2: Channel Sync

```swift
syncState = .syncing(progress: SyncProgress(phase: .channels, current: 0, total: 0))

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

syncState = .syncing(progress: SyncProgress(phase: .messages, current: 0, total: 0))

await messagePollingService.pollAllMessages()
```

**MessagePollingService.pollAllMessages:**

```swift
var count = 0

while true {
    let result = try await session.getMessage()

    switch result {
    case .noMoreMessages:
        return count  // Queue empty

    case .contactMessage(let message):
        // Handled by event monitoring handlers
        count += 1

    case .channelMessage(let message):
        // Handled by event monitoring handlers
        count += 1
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
// AppState tracks sync activity via counter
private var syncActivityCount: Int = 0

var shouldShowSyncingPill: Bool {
    syncActivityCount > 0
}

// SyncCoordinator calls these during contacts/channels phases
await onSyncActivityStarted?()  // syncActivityCount += 1
await onSyncActivityEnded?()    // syncActivityCount -= 1
```

The pill is shown for:
- Contacts sync phase
- Channels sync phase
- On-demand settings operations

The pill is NOT shown for message sync because:
- Message polling can take variable time
- Users shouldn't wait for it
- It happens in background

## Error Handling

### Sync Errors

```swift
public enum SyncCoordinatorError: Error, Sendable {
    case notConnected
    case syncFailed(String)
    case alreadySyncing
}
```

### Recovery Strategy

```swift
do {
    try await performFullSync(
        deviceID: deviceID,
        contactService: contactService,
        channelService: channelService,
        messagePollingService: messagePollingService
    )
    await setState(.synced)
} catch {
    let syncError = SyncCoordinatorError.syncFailed(error.localizedDescription)
    await setState(.failed(syncError))

    // Log for debugging
    logger.error("Sync failed: \(error)")
}
```

On failure:
1. State transitions to `.failed(SyncCoordinatorError)`
2. UI shows error indicator
3. User can trigger manual retry via pull-to-refresh

## Message Handler Wiring

### Contact Message Handler

```swift
// Handles direct messages from contacts (textType = 0x00)
await messagePollingService.setContactMessageHandler { message, contact in
    let timestamp = UInt32(message.senderTimestamp.timeIntervalSince1970)

    // Create DTO
    let messageDTO = MessageDTO(
        id: UUID(),
        deviceID: deviceID,
        contactID: contact?.id,
        channelIndex: nil,
        text: message.text,
        timestamp: timestamp,
        createdAt: Date(),
        direction: .incoming,
        status: .delivered,
        textType: TextType(rawValue: message.textType) ?? .plain,
        ackCode: nil,
        pathLength: message.pathLength,
        snr: message.snr,
        senderKeyPrefix: message.senderPublicKeyPrefix,
        senderNodeName: nil,
        isRead: false,
        replyToID: nil,
        roundTripTime: nil,
        heardRepeats: 0,
        retryAttempt: 0,
        maxRetryAttempts: 0
    )

    // Save to database
    try await dataStore.saveMessage(messageDTO)

    // Update contact's last message date and unread count
    if let contactID = contact?.id {
        try await dataStore.updateContactLastMessage(contactID: contactID, date: Date())
        try await dataStore.incrementUnreadCount(contactID: contactID)
    }

    // Post notification
    if let contactID = contact?.id {
        await services.notificationService.postDirectMessageNotification(
            from: contact?.displayName ?? "Unknown",
            contactID: contactID,
            messageText: message.text,
            messageID: messageDTO.id
        )
    }
    await services.notificationService.updateBadgeCount()

    // Notify UI via SyncCoordinator
    await syncCoordinator.notifyConversationsChanged()

    // Notify MessageEventBroadcaster for real-time chat updates
    if let contact {
        await onDirectMessageReceived?(messageDTO, contact)
    }
}
```

### Channel Message Handler

```swift
// Handles channel broadcast messages (textType = 0x03)
await messagePollingService.setChannelMessageHandler { message, channel in
    // Parse "NodeName: text" format for sender name
    let (senderNodeName, messageText) = parseChannelMessage(message.text)

    let timestamp = UInt32(message.senderTimestamp.timeIntervalSince1970)
    let messageDTO = MessageDTO(
        id: UUID(),
        deviceID: deviceID,
        contactID: nil,
        channelIndex: message.channelIndex,
        text: messageText,
        timestamp: timestamp,
        createdAt: Date(),
        direction: .incoming,
        status: .delivered,
        textType: TextType(rawValue: message.textType) ?? .plain,
        ackCode: nil,
        pathLength: message.pathLength,
        snr: message.snr,
        senderKeyPrefix: nil,
        senderNodeName: senderNodeName,
        isRead: false,
        replyToID: nil,
        roundTripTime: nil,
        heardRepeats: 0,
        retryAttempt: 0,
        maxRetryAttempts: 0
    )

    // Save to database
    try await dataStore.saveMessage(messageDTO)

    // Update channel's last message date and unread count
    if let channelID = channel?.id {
        try await dataStore.updateChannelLastMessage(channelID: channelID, date: Date())
        try await dataStore.incrementChannelUnreadCount(channelID: channelID)
    }

    // Post notification
    await services.notificationService.postChannelMessageNotification(
        channelName: channel?.name ?? "Channel \(message.channelIndex)",
        channelIndex: message.channelIndex,
        deviceID: deviceID,
        senderName: senderNodeName,
        messageText: messageText,
        messageID: messageDTO.id
    )
    await services.notificationService.updateBadgeCount()

    // Notify UI via SyncCoordinator
    await syncCoordinator.notifyConversationsChanged()

    // Notify MessageEventBroadcaster for real-time chat updates
    await onChannelMessageReceived?(messageDTO, message.channelIndex)
}

// Helper function to parse channel messages
private static func parseChannelMessage(_ text: String) -> (senderNodeName: String?, messageText: String) {
    let parts = text.split(separator: ":", maxSplits: 1)
    if parts.count > 1 {
        let senderName = String(parts[0]).trimmingCharacters(in: .whitespaces)
        let messageText = String(parts[1]).trimmingCharacters(in: .whitespaces)
        return (senderName, messageText)
    }
    return (nil, text)
}
```

### Signed Message Handler

```swift
// Handles signed messages from room servers (textType = 0x02)
await messagePollingService.setSignedMessageHandler { message, contact in
    // For signed room messages, the signature contains the 4-byte author key prefix
    guard let authorPrefix = message.signature?.prefix(4), authorPrefix.count == 4 else {
        logger.warning("Dropping signed message: missing or invalid author prefix")
        return
    }

    let timestamp = UInt32(message.senderTimestamp.timeIntervalSince1970)

    // Process room server message
    try await roomServerService.handleIncomingMessage(
        senderPublicKeyPrefix: message.senderPublicKeyPrefix,
        timestamp: timestamp,
        authorPrefix: Data(authorPrefix),
        text: message.text
    )
}
```

### CLI Message Handler

```swift
// Handles CLI messages from repeater admin (textType = 0x01)
await messagePollingService.setCLIMessageHandler { message, contact in
    // Process repeater administrative responses
    if let contact {
        await repeaterAdminService.invokeCLIHandler(message, fromContact: contact)
    } else {
        logger.warning("Dropping CLI response: no contact found for sender")
    }
}
```

## Message Event Callbacks

The SyncCoordinator provides callbacks for real-time UI updates when messages arrive. These are separate from the handlers above and are used by the MessageEventBroadcaster for live chat updates.

### Wiring Event Callbacks

```swift
// Wire message event callbacks for real-time chat updates
await syncCoordinator.setMessageEventCallbacks(
    onDirectMessageReceived: { [weak self] message, contact in
        await self?.messageEventBroadcaster.handleDirectMessage(message, from: contact)
    },
    onChannelMessageReceived: { [weak self] message, channelIndex in
        await self?.messageEventBroadcaster.handleChannelMessage(message, channelIndex: channelIndex)
    }
)
```

### How Event Callbacks Work

When a message arrives:

1. **Message Handler** (in SyncCoordinator):
   - Saves message to database
   - Updates unread counts
   - Posts system notification
   - Updates UI refresh counters

2. **Event Callback** (to MessageEventBroadcaster):
   - Broadcasts to open chat views
   - Updates message lists in real-time
   - Handles message status updates
   - Updates chat UI without database reload

This separation ensures:
- Messages are persisted immediately
- Open chats update instantly
- Closed chats show notifications
- No duplicate database queries

## Discovery Handlers

### New Contact Discovered

```swift
// Triggered when device advertises a new contact (manual-add mode)
await advertisementService.setNewContactDiscoveredHandler { contactName, contactID in
    // Post notification for manual-add UI
    await services.notificationService.postNewContactNotification(
        contactName: contactName,
        contactID: contactID
    )

    // Refresh contact list
    await syncCoordinator.notifyContactsChanged()
}
```

### Auto-Add Mode

```swift
// Triggered when device wants us to sync contacts (auto-add mode)
await advertisementService.setContactSyncRequestHandler { _ in
    // Sync contacts from device
    do {
        _ = try await services.contactService.syncContacts(deviceID: deviceID)
        await syncCoordinator.notifyContactsChanged()
    } catch {
        logger.warning("Auto-sync after discovery failed: \(error.localizedDescription)")
    }
}
```

## Disconnection Handling

When the device disconnects, the sync state resets:

```swift
// Called by ConnectionManager when disconnecting
await syncCoordinator.onDisconnected()

// In SyncCoordinator:
public func onDisconnected() async {
    await setState(.idle)
    logger.info("Disconnected, sync state reset to idle")
}

// In AppState.wireServicesIfConnected:
guard let services else {
    // Clear syncCoordinator when services are nil
    syncCoordinator = nil
    // Reset sync activity count to prevent stuck pill
    syncActivityCount = 0
    return
}
```

This ensures:
- Sync state transitions to `.idle`
- Sync activity count resets to 0
- UI pill is hidden
- Clean state when reconnecting
- No stale sync indicators

## Observable State for SwiftUI

The coordinator provides observable counters for SwiftUI updates. Since actors don't participate in SwiftUI's observation system, we use callbacks to update version counters in AppState.

### SyncCoordinator Version Counters

```swift
// In SyncCoordinator (actor)
@MainActor public private(set) var contactsVersion: Int = 0
@MainActor public private(set) var conversationsVersion: Int = 0

@MainActor
public func notifyContactsChanged() {
    contactsVersion += 1
    onContactsChanged?()  // Calls back to AppState
}

@MainActor
public func notifyConversationsChanged() {
    conversationsVersion += 1
    onConversationsChanged?()  // Calls back to AppState
}
```

### Wiring Callbacks to AppState

```swift
// In AppState.wireServicesIfConnected
await services.syncCoordinator.setDataChangeCallbacks(
    onContactsChanged: { @MainActor [weak self] in
        self?.contactsVersion += 1
    },
    onConversationsChanged: { @MainActor [weak self] in
        self?.conversationsVersion += 1
    }
)
```

### SwiftUI Views Observing Changes

```swift
struct ContactsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        List(contacts) { contact in
            ContactRow(contact: contact)
        }
        .onChange(of: appState.contactsVersion) {
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
