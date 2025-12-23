# MeshCore API Reference

The `MeshCore` framework provides the low-level protocol implementation for MeshCore mesh networking devices.

## Package Information

- **Location:** `MeshCore/`
- **Type:** Swift Package (single library target)
- **Dependencies:** None (pure Swift)

---

## MeshCoreSession (public, actor)

**File:** `MeshCore/Sources/MeshCore/Session/MeshCoreSession.swift`

The primary entry point for communicating with a MeshCore device. Serializes all device communication through actor isolation.

### Lifecycle

| Method | Description |
|--------|-------------|
| `init(transport: any MeshTransport, configuration: SessionConfiguration)` | Initializes a session with the given transport |
| `start() async throws` | Connects to the device and initializes the session |
| `stop() async` | Stops the session and disconnects the transport |

### Events

| Property/Method | Description |
|-----------------|-------------|
| `events() async -> AsyncStream<MeshEvent>` | Returns a stream of all incoming events from the device |
| `connectionState: AsyncStream<ConnectionState>` | Stream reflecting the current connection state |

### Messaging

| Method | Description |
|--------|-------------|
| `sendMessage(to:text:timestamp:) async throws -> MessageSentInfo` | Sends a direct message to a contact (6-byte public key prefix) |
| `sendMessageWithRetry(to:text:maxAttempts:floodAfter:maxFloodAttempts:timeout:) async throws -> MessageSentInfo?` | Sends with automatic retry and flood fallback (requires 32-byte key) |
| `sendChannelMessage(channel:text:timestamp:) async throws` | Broadcasts to a channel slot (0-7) |
| `getMessage() async throws -> MessageResult` | Fetches next pending message from device queue |
| `startAutoMessageFetching() async` | Begins automatically fetching messages on notifications |

### Contact Management

| Method | Description |
|--------|-------------|
| `getContacts(since:) async throws -> [MeshContact]` | Fetches contacts, optionally since a date |
| `addContact(_:) async throws` | Adds a contact to the device |
| `removeContact(publicKey:) async throws` | Removes a contact from the device |
| `resetPath(publicKey:) async throws` | Resets routing path for a contact |

### Device Configuration

| Method | Description |
|--------|-------------|
| `queryDevice() async throws -> DeviceCapabilities` | Queries hardware capabilities and firmware |
| `getBattery() async throws -> BatteryInfo` | Requests battery level and voltage |
| `setName(_:) async throws` | Sets the device's advertised name |
| `setCoordinates(latitude:longitude:) async throws` | Sets device location for advertisements |
| `setRadio(frequency:bandwidth:spreadingFactor:codingRate:) async throws` | Configures LoRa radio parameters |

### Remote Node Queries (Binary Protocol)

| Method | Description |
|--------|-------------|
| `requestStatus(from:) async throws -> StatusResponse` | Requests status from a remote node |
| `requestTelemetry(from:) async throws -> TelemetryResponse` | Requests telemetry from a remote node |
| `fetchAllNeighbours(from:) async throws -> NeighboursResponse` | Fetches neighbor table from a remote node |

---

## MeshTransport (public, protocol)

**File:** `MeshCore/Sources/MeshCore/Transport/MeshTransport.swift`

Abstraction for underlying transport layers, enabling different implementations for production and testing.

```swift
public protocol MeshTransport: Actor, Sendable {
    var receivedData: AsyncStream<Data> { get async }
    func connect() async throws
    func disconnect() async
    func send(_ data: Data) async throws
}
```

### Implementations

| Type | Description |
|------|-------------|
| `BLETransport` (public, actor) | CoreBluetooth-based transport for physical devices |
| `MockTransport` (public, actor) | Deterministic transport for unit testing |

---

## EventDispatcher (public, actor)

**File:** `MeshCore/Sources/MeshCore/Events/EventDispatcher.swift`

Broadcasts `MeshEvent`s to multiple subscribers via `AsyncStream`. Manages event distribution from the session to all listeners.

### Methods

| Method | Description |
|--------|-------------|
| `subscribe() -> AsyncStream<MeshEvent>` | Returns a new stream for receiving events |
| `dispatch(_:) async` | Broadcasts an event to all subscribers |

---

## MeshEvent (public, enum)

**File:** `MeshCore/Sources/MeshCore/Events/MeshEvent.swift`

Represents any event received from the device.

### Cases

| Case | Payload |
|------|---------|
| `.contactMessageReceived` | `ContactMessage` |
| `.channelMessageReceived` | `ChannelMessage` |
| `.advertisement` | `publicKey: Data` |
| `.battery` | `BatteryInfo` |
| `.acknowledgement` | `code: Data` |
| `.statusResponse` | `StatusResponse` |
| `.telemetryResponse` | `TelemetryResponse` |
| `.neighboursResponse` | `NeighboursResponse` |
| `.currentTime` | `Date` |
| `.deviceInfo` | `DeviceCapabilities` |

---

## Models

### MeshContact (public, struct)

**File:** `MeshCore/Sources/MeshCore/Models/Contact.swift`

Represents a contact in the mesh network.

| Property | Type | Description |
|----------|------|-------------|
| `publicKey` | `Data` | 32-byte public key |
| `advertisedName` | `String` | Display name from advertisement |
| `type` | `UInt8` | Node type: 0=Chat, 1=Repeater, 2=Room |
| `latitude` | `Double?` | Location latitude |
| `longitude` | `Double?` | Location longitude |
| `lastAdvertisement` | `Date` | Last advertisement timestamp |
| `outPath` | `Data?` | Routing information |
| `outPathLength` | `Int` | Hop count (-1 = flood) |

### ContactMessage (public, struct)

**File:** `MeshCore/Sources/MeshCore/Events/MeshEvent.swift:354`

Represents a direct message from a contact.

| Property | Type | Description |
|----------|------|-------------|
| `senderPublicKey` | `Data` | 6-byte sender key prefix |
| `text` | `String` | Message content |
| `textType` | `UInt8` | Message type (0=plain, 1=CLI, 2=signed) |
| `timestamp` | `UInt32` | Unix timestamp |
| `snr` | `Int8` | Signal-to-noise ratio |
| `rssi` | `Int8` | Received signal strength |
| `pathLength` | `Int8` | Hop count |

### ChannelMessage (public, struct)

**File:** `MeshCore/Sources/MeshCore/Events/MeshEvent.swift:403`

Represents a message received on a channel.

| Property | Type | Description |
|----------|------|-------------|
| `channelIndex` | `UInt8` | Channel slot (0-7) |
| `text` | `String` | Message content (format: "NodeName: text") |
| `timestamp` | `UInt32` | Unix timestamp |
| `snr` | `Int8` | Signal-to-noise ratio |
| `rssi` | `Int8` | Received signal strength |

---

## Utilities

### PacketBuilder (public, enum)

**File:** `MeshCore/Sources/MeshCore/Protocol/PacketBuilder.swift`

Stateless enum for constructing binary protocol packets.

### PacketParser (public, enum)

**File:** `MeshCore/Sources/MeshCore/Protocol/PacketParser.swift`

Stateless enum for parsing binary protocol packets into `MeshEvent`s.

### LPPDecoder (public, enum)

**File:** `MeshCore/Sources/MeshCore/LPP/LPPDecoder.swift`

Decodes Cayenne Low Power Payload (LPP) telemetry data.

```swift
public static func decode(_ data: Data) -> [LPPDataPoint]
```

---

## See Also

- [Architecture Overview](../Architecture.md)
- [BLE Transport Guide](../guides/BLE_Transport.md)
- [Messaging Guide](../guides/Messaging.md)
