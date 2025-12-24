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
│  • Message saved to SwiftData with status: .pending  │
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
| `.pending` | Saved locally, waiting to send | "Sending..." text |
| `.sending` | Transmission in progress | "Sending..." text |
| `.sent` | Radio transmitted, awaiting ACK | "Sent" text |
| `.delivered` | ACK received from recipient | "Delivered" text |
| `.failed` | All attempts exhausted | "Failed" text + red exclamation icon + red bubble background |
| `.retrying` | Manual retry in progress | "Retrying..." text + spinner |

**Note:** The retry button only appears for messages with `.failed` status. During `.retrying`, the button is replaced with a spinner to indicate the retry is in progress.

## Retry Logic

### Automatic Retry (sendMessageWithRetry)

**File:** `PocketMeshServices/Sources/PocketMeshServices/Services/MessageService.swift`

Default configuration:
- `floodFallbackOnRetry: true` - Use flood on manual retry
- `maxAttempts: 4` - Total send attempts
- `maxFloodAttempts: 2` - Maximum flood attempts
- `floodAfter: 2` - Switch to flood after 2 direct attempts
- `minTimeout: 0` - Minimum timeout seconds
- `triggerPathDiscoveryAfterFlood: true` - Trigger path discovery after flood

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

### Automatic vs Manual Retry

**Automatic Retry:**
- Initiated by `sendMessageWithRetry()` when first sending a message
- Message status remains in `.pending` or `.sending` during all attempts
- Status does NOT change to `.retrying` during automatic retry
- Retry logic managed internally by `MeshCoreSession`
- No user interaction required
- If all attempts fail, status changes to `.failed`

**Manual Retry:**
- Triggered when user taps "Retry" button on a failed message
- Message status immediately set to `.retrying` (visible in UI with spinner)
- Uses flood routing by default (`config.floodFallbackOnRetry`)
- User can see retry is in progress
- Retry button disappears while `.retrying` status is active

### Manual Retry Details

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

The UI shows:
- "Retrying..." text with a spinner icon
- No attempt count is displayed (e.g., "1/4", "2/4")
- The retry button is hidden while in `.retrying` status

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

**ACK Timeout:**
The actual ACK timeout used is 1.2x the device-suggested timeout to provide a safety margin:

```swift
// From MeshCoreSession.swift
let ackTimeout = timeout ?? (Double(sentInfo.suggestedTimeoutMs) / 1000.0 * 1.2)
```

This multiplier accounts for potential timing variations in the mesh network.

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

## Message Deduplication

**File:** `PocketMeshServices/Sources/PocketMeshServices/Models/Message.swift`

Messages include a `deduplicationKey` field to prevent duplicate incoming messages from being stored. The key is generated using a combination of timestamp, sender's public key prefix, and a hash of the message content:

```swift
// Message.generateDeduplicationKey() - lines 194-203
static func generateDeduplicationKey(
    timestamp: UInt32,
    senderKeyPrefix: Data?,
    text: String
) -> String {
    let senderHex = (senderKeyPrefix ?? unknownSenderSentinel).hex
    let contentHash = SHA256.hash(data: Data(text.utf8))
    let hashPrefix = contentHash.prefix(4).map { String(format: "%02x", $0) }.joined()
    return "\(timestamp)-\(senderHex)-\(hashPrefix)"
}

// Example format: "1703123456-a1b2c3d4e5f6-8f3a9b2c"
```

**Components:**
- **Timestamp**: Message timestamp (UInt32)
- **Sender Key Prefix**: 6-byte public key prefix in hex (or `unknownSenderSentinel` if unavailable)
- **Content Hash**: First 4 bytes of SHA256 hash of message text

When a message is received, the system checks if a message with the same deduplication key already exists. If found, the duplicate is ignored. This prevents the same message from appearing multiple times if it's received via multiple mesh paths.

The SHA256 hash ensures that:
- Identical messages from the same sender at the same timestamp are deduplicated
- Different messages at the same timestamp are stored separately
- The key is stable across app restarts

## Channel vs Direct Messaging

### Direct Messages

- Sent to a specific contact's public key (6-byte prefix)
- Encrypted end-to-end
- Support ACK/delivery confirmation
- Include deduplication key to prevent duplicates
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
