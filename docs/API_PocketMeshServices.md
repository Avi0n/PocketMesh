# PocketMeshServices API Reference

The `PocketMeshServices` layer provides actor-isolated business logic, managing services, persistence, and device connections.

## ConnectionManager (MainActor, Observable)

The primary entry point for managing the connection to a MeshCore device and coordinating services.

### Properties

- `connectionState: ConnectionState`
  The current state of the device connection (`.disconnected`, `.connecting`, `.connected`, `.ready`).
- `connectedDevice: DeviceDTO?`
  Information about the currently connected device.
- `services: ServiceContainer?`
  Container holding the business logic services, available once the connection is `.ready`.

### Methods

- `activate() async`
  Initializes the manager and attempts to auto-reconnect to the last known device.
- `pairNewDevice() async throws`
  Starts the **AccessorySetupKit** pairing flow to find and connect to a new device.
- `connect(to deviceID: UUID) async throws`
  Connects to a previously paired device.
- `disconnect() async`
  Gracefully disconnects and stops all services.
- `forgetDevice() async throws`
  Removes the device from the app and the system's AccessorySetupKit pairings.

---

## MessageService (Actor)

Handles sending and receiving messages, delivery tracking, and retry logic.

### Messaging

- `sendMessageWithRetry(text: String, to: ContactDTO, ...) async throws -> MessageDTO`
  Sends a direct message with automatic retries and flood fallback.
- `sendDirectMessage(text: String, to: ContactDTO, ...) async throws -> MessageDTO`
  Sends a message with a single attempt.
- `sendChannelMessage(text: String, channelIndex: UInt8, ...) async throws -> UUID`
  Broadcasts a message to a specific channel.
- `retryDirectMessage(messageID: UUID, to: ContactDTO) async throws -> MessageDTO`
  Manually retries a failed message.

### ACK Tracking

- `startAckExpiryChecking(interval: TimeInterval = 5.0)`
  Starts periodic background checks for expired message acknowledgments.
- `stopAckExpiryChecking()`
  Stops the background ACK checking.

---

## ContactService (Actor)

Manages discovery, synchronization, and storage of mesh contacts.

### Sync & Discovery

- `syncContacts(deviceID: UUID, since: Date? = nil) async throws -> ContactSyncResult`
  Performs an incremental or full sync of contacts from the device.
- `sendPathDiscovery(deviceID: UUID, publicKey: Data) async throws -> MessageSentInfo`
  Initiates a path discovery request to find a route to a remote node.

### Contact Management

- `addOrUpdateContact(deviceID: UUID, contact: ContactFrame) async throws`
  Adds or updates a contact on both the device and in local persistence.
- `removeContact(deviceID: UUID, publicKey: Data) async throws`
  Deletes a contact from the device and local persistence.
- `resetPath(deviceID: UUID, publicKey: Data) async throws`
  Resets the routing information for a contact, forcing mesh rediscovery.

---

## ChannelService (Actor)

Manages group messaging channels and secure slot configuration.

### Channel Operations

- `syncChannels(deviceID: UUID) async throws -> ChannelSyncResult`
  Synchronizes all channel slot configurations from the device.
- `setChannel(deviceID: UUID, index: UInt8, name: String, passphrase: String) async throws`
  Configures a channel slot using a passphrase (hashed to a 16-byte secret via SHA-256).
- `clearChannel(deviceID: UUID, index: UInt8) async throws`
  Resets a channel slot on the device.
- `setupPublicChannel(deviceID: UUID) async throws`
  Initializes the default public channel on slot 0.

---

## PersistenceStore (Actor)

The unified interface for SwiftData persistence, shared across all services.

- Handles CRUD operations for `Device`, `Contact`, `Message`, and `Channel` models.
- Provides thread-safe access to the data store via the actor model.
- Uses DTOs (Data Transfer Objects) for passing data between services and the UI.
