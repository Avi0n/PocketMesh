# Messaging Guide

This guide covers the message lifecycle, delivery states, retry logic, and ACK handling in PocketMesh.

## Message Lifecycle

```
┌──────────────────────────────────────────────────────┐
│                        COMPOSE                       │
│  User types message in ChatView                      │
└──────────────────────────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────┐
│                         QUEUE                        │
│  MessageService.sendMessageWithRetry() called        │
│  • Message saved to SwiftData with status: .queued   │
│  • onMessageCreated callback notifies UI             │
└──────────────────────────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────┐
│                         SEND                         │
│  MeshCoreSession.sendMessageWithRetry() called       │
│  • Attempts 1-2: Direct routing                      │
│  • Attempts 3-4: Flood routing (if direct fails)     │
│  • Message status: .sending                          │
└──────────────────────────────────────────────────────┘
                            │
              ┌─────────────┴─────────────┐
              ▼                           ▼
┌─────────────────────────┐   ┌────────────────────────┐
│     ACK RECEIVED        │   │     ALL ATTEMPTS       │
│                         │   │      EXHAUSTED         │
│  • Status: .delivered   │   │                        │
│  • RTT recorded         │   │  • Status: .failed     │
│  • UI updated           │   │  • User can retry      │
└─────────────────────────┘   └────────────────────────┘
```

## Delivery States

| State | Description | UI Display |
|-------|-------------|------------|
| `.queued` | Saved locally, waiting to send | Single gray checkmark |
| `.sending` | Transmission in progress | Single gray checkmark, spinner |
| `.sent` | Radio transmitted, awaiting ACK | Single gray checkmark |
| `.delivered` | ACK received from recipient | Double blue checkmarks |
| `.failed` | All attempts exhausted | Red exclamation, "Retry" option |
| `.retrying` | Manual retry in progress | Spinner with attempt count |

## Retry Logic

### Automatic Retry (sendMessageWithRetry)

**File:** `PocketMeshServices/Sources/PocketMeshServices/Services/MessageService.swift`

Default configuration:
- `maxAttempts: 4` - Total send attempts
- `floodAfter: 2` - Switch to flood after 2 direct attempts
- `maxFloodAttempts: 2` - Maximum flood attempts

```
Attempt 1: Direct routing (use contact's outPath)
    │
    ▼ Timeout, no ACK
Attempt 2: Direct routing (retry same path)
    │
    ▼ Timeout, no ACK
Attempt 3: Flood routing (broadcast to all)
    │
    ▼ Timeout, no ACK
Attempt 4: Flood routing (final attempt)
    │
    ▼ Timeout, no ACK
FAILED
```

### Direct vs Flood Routing

**Direct Routing:**
- Uses the contact's known `outPath` (routing nodes)
- More efficient, fewer radio transmissions
- Fails if path is stale or nodes are unreachable

**Flood Routing:**
- Broadcasts to all nearby nodes
- Message propagates through entire mesh
- More likely to succeed but uses more bandwidth
- Indicated by `outPathLength < 0` (-1)

### Path Reset During Retry

When switching from direct to flood routing:

```swift
// Reset path before flood attempt
try await session.resetPath(publicKey: contact.publicKey)
```

This clears the contact's cached routing path, forcing the mesh to rediscover the route.

### Manual Retry

When a user taps "Retry" on a failed message:

```swift
// MessageService.retryDirectMessage()
try await dataStore.updateMessageRetryStatus(
    id: messageID,
    status: .retrying,
    retryAttempt: 0,
    maxRetryAttempts: config.maxAttempts
)

// Uses flood mode for manual retry (config.floodFallbackOnRetry)
```

The UI shows retry progress:
- "Retrying 1/4..."
- "Retrying 2/4..."
- etc.

## ACK Tracking

### PendingAck Structure

```swift
public struct PendingAck: Sendable {
    let messageID: UUID
    let ackCode: Data        // 4-byte ACK code
    let sentAt: Date
    let timeout: TimeInterval
    var heardRepeats: Int    // Count of duplicate ACKs
    var isDelivered: Bool
    var isRetryManaged: Bool // Skip expiry check if retry manages it
}
```

### ACK Flow

```
Message sent
    │
    ▼ ACK code generated (4 bytes)
PendingAck created
    │
    ├───── ACK received ─────► Mark delivered, update UI
    │
    └───── Timeout (5s check) ─► Mark failed (if not retry-managed)
```

### ACK Expiry Checking

Background task runs every 5 seconds:

```swift
// MessageService.startAckExpiryChecking()
ackCheckTask = Task {
    while !Task.isCancelled {
        try await Task.sleep(for: .seconds(5))
        try? await checkExpiredAcks()
        await cleanupDeliveredAcks()
    }
}
```

**checkExpiredAcks:**
- Finds ACKs where `now - sentAt > timeout`
- Excludes retry-managed ACKs (those handled by retry loop)
- Marks corresponding messages as `.failed`

**cleanupDeliveredAcks:**
- Removes delivered ACKs after grace period (60 seconds)
- Grace period allows counting repeat ACKs for mesh analysis

### Repeat ACKs

When the same ACK is received multiple times:

```swift
pendingAcks[code]?.heardRepeats += 1

try? await dataStore.updateMessageHeardRepeats(
    id: tracking.messageID,
    heardRepeats: repeatCount
)
```

Repeat ACKs indicate the message was heard by multiple nodes - useful for mesh debugging.

## Channel vs Direct Messaging

### Direct Messages

- Sent to a specific contact's public key (6-byte prefix)
- Encrypted end-to-end
- Support ACK/delivery confirmation
- Use `sendMessageWithRetry()` or `sendDirectMessage()`

### Channel Messages

- Broadcast to a channel slot (0-7)
- Encrypted with shared channel secret (SHA-256 of passphrase)
- No ACK support (broadcast, not point-to-point)
- Use `sendChannelMessage()`

```swift
// Channel message format: "NodeName: message text"
let text = "\(deviceName): \(userText)"
try await session.sendChannelMessage(channel: channelIndex, text: text)
```

## MessageEventBroadcaster Integration

**File:** `PocketMesh/Services/MessageEventBroadcaster.swift`

The broadcaster bridges service callbacks to SwiftUI:

```swift
// Service layer callback
messageService.ackConfirmationHandler = { [weak self] ackCode, rtt in
    Task { @MainActor in
        self?.broadcaster.handleAcknowledgement(ackCode: ackCode)
    }
}

// Broadcaster updates observable state
func handleAcknowledgement(ackCode: UInt32) {
    self.latestEvent = .messageStatusUpdated(ackCode: ackCode)
    self.newMessageCount += 1  // Triggers SwiftUI update
}
```

### Event Types

| Event | Trigger |
|-------|---------|
| `.directMessageReceived` | New incoming direct message |
| `.channelMessageReceived` | New incoming channel message |
| `.messageStatusUpdated` | ACK received for outgoing message |
| `.messageFailed` | Message delivery failed |
| `.messageRetrying` | Manual retry in progress |
| `.routingChanged` | Contact switched to/from flood routing |

## Message Polling

**File:** `PocketMeshServices/Sources/PocketMeshServices/Services/MessagePollingService.swift`

Messages are pulled from the device queue:

```swift
// Triggered by MeshCore notification
func pollAllMessages() async {
    while true {
        let result = try await session.getMessage()

        if case .noMessages = result {
            break  // Queue empty
        }

        // Process message...
    }
}
```

### Auto-Fetching

When enabled, messages are automatically fetched on BLE notification:

```swift
await session.startAutoMessageFetching()
```

The session monitors the notification characteristic and calls `getMessage()` when data arrives.

## See Also

- [MessageService API](../api/PocketMeshServices.md#messageservice-public-actor)
- [Architecture Overview](../Architecture.md)
- [BLE Transport Guide](BLE_Transport.md)
