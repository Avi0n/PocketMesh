# PocketMeshServices API Reference

The `PocketMeshServices` layer provides actor-isolated business logic, managing services, persistence, and device connections.

## Package Information

- **Location:** `PocketMeshServices/`
- **Type:** Swift Package (single library target)
- **Dependencies:** MeshCore

---

## ConnectionManager (public, @MainActor, @Observable class)

**File:** `PocketMeshServices/Sources/PocketMeshServices/ConnectionManager.swift`

The primary entry point for managing the connection to a MeshCore device and coordinating services.

### Properties

| Property | Type | Description |
|----------|------|-------------|
| `connectionState` | `ConnectionState` | Current state: `.disconnected`, `.connecting`, `.connected`, `.ready` |
| `connectedDevice` | `DeviceDTO?` | Currently connected device info |
| `services` | `ServiceContainer?` | Business logic services (available when `.ready`) |

### Methods

| Method | Description |
|--------|-------------|
| `activate() async` | Initializes and attempts auto-reconnect to last device |
| `pairNewDevice() async throws` | Starts AccessorySetupKit pairing flow |
| `connect(to:) async throws` | Connects to a previously paired device |
| `disconnect() async` | Gracefully disconnects and stops services |
| `forgetDevice() async throws` | Removes device from app and system pairings |

---

## SyncCoordinator (public, actor)

**File:** `PocketMeshServices/Sources/PocketMeshServices/SyncCoordinator.swift`

Orchestrates data synchronization between the MeshCore device and local database through three phases.

### Sync Phases

```swift
public enum SyncPhase: Sendable, Equatable {
    case contacts   // Phase 1: Sync contacts from device
    case channels   // Phase 2: Sync channel configurations
    case messages   // Phase 3: Poll pending messages
}
```

### Sync State

```swift
public enum SyncState: Sendable, Equatable {
    case idle
    case syncing(progress: SyncProgress)
    case synced
    case failed(SyncCoordinatorError)
}
```

### Key Methods

| Method | Description |
|--------|-------------|
| `performFullSync(services:deviceID:) async throws` | Executes contacts → channels → messages sync |
| `onConnectionEstablished(services:deviceID:) async throws` | Called after BLE connection; wires handlers and syncs |
| `setSyncActivityCallbacks(onStarted:onEnded:)` | Sets UI callbacks for sync pill display |

### Connection Lifecycle

1. Wire message handlers (before events arrive)
2. Start event monitoring
3. Perform full sync (contacts, channels, messages)
4. Wire discovery handlers (for ongoing contact discovery)

---

## MessageService (public, actor)

**File:** `PocketMeshServices/Sources/PocketMeshServices/Services/MessageService.swift`

Handles message sending with automatic retry logic, flood routing fallback, and ACK tracking.

### Configuration

```swift
public struct MessageServiceConfig: Sendable {
    let maxAttempts: Int           // Total attempts (default: 4)
    let floodAfter: Int            // Switch to flood after N (default: 2)
    let maxFloodAttempts: Int      // Max flood attempts (default: 2)
    let minTimeout: TimeInterval   // Minimum timeout seconds
    let floodFallbackOnRetry: Bool // Use flood on manual retry
}
```

### Messaging Methods

| Method | Description |
|--------|-------------|
| `sendMessageWithRetry(text:to:...) async throws -> MessageDTO` | Sends with auto-retry and flood fallback |
| `sendDirectMessage(text:to:...) async throws -> MessageDTO` | Single attempt send |
| `sendChannelMessage(text:channelIndex:...) async throws -> UUID` | Broadcasts to channel |
| `retryDirectMessage(messageID:to:) async throws -> MessageDTO` | Manual retry of failed message |

### ACK Tracking

| Method | Description |
|--------|-------------|
| `startAckExpiryChecking(interval:)` | Starts periodic expired ACK checks (default: 5s) |
| `stopAckExpiryChecking()` | Stops background ACK checking |
| `handleAcknowledgement(_:) async` | Processes incoming ACK, updates message status |

### Retry Flow

1. Attempts 1-2: Direct routing (using contact's outbound path)
2. Attempts 3-4: Flood routing (broadcast to all nearby nodes)
3. Returns immediately when ACK received
4. Marks failed if all attempts exhausted

---

## ContactService (public, actor)

**File:** `PocketMeshServices/Sources/PocketMeshServices/Services/ContactService.swift`

Manages discovery, synchronization, and storage of mesh contacts.

### Methods

| Method | Description |
|--------|-------------|
| `syncContacts(deviceID:since:) async throws -> ContactSyncResult` | Incremental or full contact sync |
| `sendPathDiscovery(deviceID:publicKey:) async throws -> MessageSentInfo` | Initiates route discovery |
| `addOrUpdateContact(deviceID:contact:) async throws` | Adds/updates contact on device and local store |
| `removeContact(deviceID:publicKey:) async throws` | Deletes from device and local store |
| `resetPath(deviceID:publicKey:) async throws` | Resets routing, forces mesh rediscovery |

---

## ChannelService (public, actor)

**File:** `PocketMeshServices/Sources/PocketMeshServices/Services/ChannelService.swift`

Manages group messaging channels and secure slot configuration.

### Methods

| Method | Description |
|--------|-------------|
| `syncChannels(deviceID:) async throws -> ChannelSyncResult` | Syncs all channel slot configurations |
| `setChannel(deviceID:index:name:passphrase:) async throws` | Configures slot with passphrase (SHA-256 hashed) |
| `clearChannel(deviceID:index:) async throws` | Resets a channel slot |
| `setupPublicChannel(deviceID:) async throws` | Initializes default public channel on slot 0 |

---

## RemoteNodeService (public, actor)

**File:** `PocketMeshServices/Sources/PocketMeshServices/Services/RemoteNodeService.swift`

Queries remote mesh nodes using the binary protocol.

### Methods

| Method | Description |
|--------|-------------|
| `requestStatus(deviceID:publicKey:) async throws -> StatusResponse` | Gets battery, uptime, SNR from remote |
| `requestTelemetry(deviceID:publicKey:) async throws -> TelemetryResponse` | Gets sensor telemetry from remote |
| `fetchNeighbours(deviceID:publicKey:) async throws -> NeighboursResponse` | Gets neighbor table from remote |

---

## PersistenceStore (public, @ModelActor actor)

**File:** `PocketMeshServices/Sources/PocketMeshServices/Services/PersistenceStore.swift`

Type alias: `DataStore = PersistenceStore`

The unified interface for SwiftData persistence, shared across all services.

### Responsibilities

- CRUD operations for `Device`, `Contact`, `Message`, `Channel` models
- Thread-safe access via actor model
- Uses DTOs for cross-boundary data transfer

---

## Data Transfer Objects

### MessageDTO (public, struct)

**File:** `PocketMeshServices/Sources/PocketMeshServices/Models/Message.swift:209`

| Property | Type | Description |
|----------|------|-------------|
| `id` | `UUID` | Unique identifier |
| `text` | `String` | Message content |
| `timestamp` | `Date` | Send/receive time |
| `isIncoming` | `Bool` | True if received |
| `status` | `MessageStatus` | `.queued`, `.sending`, `.sent`, `.delivered`, `.failed` |
| `ackCode` | `UInt32?` | ACK code for tracking |
| `snr` | `Int8?` | Signal-to-noise ratio |
| `pathLength` | `Int8?` | Hop count |

### ContactDTO (public, struct)

**File:** `PocketMeshServices/Sources/PocketMeshServices/Models/Contact.swift:193`

| Property | Type | Description |
|----------|------|-------------|
| `id` | `UUID` | Local identifier |
| `publicKey` | `Data` | 32-byte public key |
| `name` | `String` | Display name |
| `type` | `ContactType` | `.chat`, `.repeater`, `.room` |
| `latitude` | `Double?` | Location |
| `longitude` | `Double?` | Location |
| `unreadCount` | `Int` | Unread messages |
| `outPathLength` | `Int` | Hop count (-1 = flood) |

### DeviceDTO (public, struct)

**File:** `PocketMeshServices/Sources/PocketMeshServices/Models/Device.swift:152`

| Property | Type | Description |
|----------|------|-------------|
| `id` | `UUID` | Device identifier |
| `name` | `String` | Device name |
| `firmwareVersion` | `String?` | Firmware version |
| `batteryLevel` | `Int?` | Battery percentage |
| `publicKey` | `Data` | Device public key |

### ChannelDTO (public, struct)

**File:** `PocketMeshServices/Sources/PocketMeshServices/Models/Channel.swift:92`

| Property | Type | Description |
|----------|------|-------------|
| `id` | `UUID` | Local identifier |
| `index` | `UInt8` | Slot number (0-7) |
| `name` | `String` | Channel name |
| `unreadCount` | `Int` | Unread messages |

---

## Additional Services

| Service | Type | Description |
|---------|------|-------------|
| `MessagePollingService` | public, actor | Polls device for pending messages, routes to handlers |
| `SettingsService` | public, actor | Manages device settings (name, location, radio) |
| `AdvertisementService` | public, actor | Sends advertisements to mesh |
| `RoomServerService` | public, actor | Handles room server messaging |
| `RepeaterAdminService` | public, actor | Admin commands for repeater nodes |
| `BinaryProtocolService` | public, actor | Binary protocol encoding/decoding |
| `KeychainService` | public, actor | Secure credential storage |
| `NotificationService` | public, actor | Local notification scheduling |
| `ServiceContainer` | public, class | Holds all service instances |

---

## See Also

- [Architecture Overview](../Architecture.md)
- [Sync Guide](../guides/Sync.md)
- [Messaging Guide](../guides/Messaging.md)
