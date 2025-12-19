# MeshCore API Reference

The `MeshCore` framework provides the low-level protocol implementation for MeshCore devices.

## MeshCoreSession (Actor)

The primary entry point for communicating with a MeshCore device.

### Lifecycle

- `init(transport: any MeshTransport, configuration: SessionConfiguration = .default)`
  Initializes a new session with the given transport.
- `start() async throws`
  Connects to the device and initializes the session.
- `stop() async`
  Stops the session and disconnects the transport.

### Events

- `events() async -> AsyncStream<MeshEvent>`
  Returns a stream of all incoming events from the device.
- `connectionState: AsyncStream<ConnectionState>`
  A stream reflecting the current connection state.

### Messaging

- `sendMessage(to destination: Data, text: String, timestamp: Date = Date()) async throws -> MessageSentInfo`
  Sends a direct message to a contact (6-byte public key prefix).
- `sendMessageWithRetry(to destination: Data, text: String, ...) async throws -> MessageSentInfo?`
  Sends a message with automatic retry logic and path reset (requires 32-byte public key).
- `sendChannelMessage(channel: UInt8, text: String, timestamp: Date = Date()) async throws`
  Broadcasts a message to a specific channel slot (0-7).
- `getMessage() async throws -> MessageResult`
  Fetches the next pending message from the device queue.
- `startAutoMessageFetching() async`
  Begins automatically fetching messages when notifications are received.

### Contact Management

- `getContacts(since lastModified: Date? = nil) async throws -> [MeshContact]`
  Fetches contacts from the device, optionally since a specific date.
- `addContact(_ contact: MeshContact) async throws`
  Adds a contact to the device.
- `removeContact(publicKey: Data) async throws`
  Removes a contact from the device.
- `resetPath(publicKey: Data) async throws`
  Resets the routing path for a specific contact.

### Device Configuration

- `queryDevice() async throws -> DeviceCapabilities`
  Queries hardware capabilities and firmware version.
- `getBattery() async throws -> BatteryInfo`
  Requests current battery level and voltage.
- `setName(_ name: String) async throws`
  Sets the device's advertised name.
- `setCoordinates(latitude: Double, longitude: Double) async throws`
  Sets the device's location for advertisements.
- `setRadio(frequency: Double, bandwidth: Double, spreadingFactor: UInt8, codingRate: UInt8) async throws`
  Configures the LoRa radio parameters.

### Remote Node Queries (Binary Protocol)

- `requestStatus(from publicKey: Data) async throws -> StatusResponse`
  Requests status (battery, uptime, SNR) from a remote node.
- `requestTelemetry(from publicKey: Data) async throws -> TelemetryResponse`
  Requests telemetry data from a remote node.
- `fetchAllNeighbours(from publicKey: Data) async throws -> NeighboursResponse`
  Fetches the full neighbor table from a remote node.

---

## Models

### MeshEvent (Enum)

Represents any event received from the device:
- `.contactMessageReceived(ContactMessage)`
- `.channelMessageReceived(ChannelMessage)`
- `.advertisement(publicKey: Data)`
- `.battery(BatteryInfo)`
- `.acknowledgement(code: Data)`
- `.statusResponse(StatusResponse)`
- `.telemetryResponse(TelemetryResponse)`
- ... and more.

### MeshContact (Struct)

Represents a contact in the mesh network:
- `publicKey: Data` (32 bytes)
- `advertisedName: String`
- `type: UInt8` (Chat, Repeater, Room)
- `latitude`, `longitude`: Location data
- `lastAdvertisement: Date`
- `outPath`: Routing information

---

## Utilities

### LPPDecoder

Decodes Cayenne Low Power Payload (LPP) data points:
- `static func decode(_ data: Data) -> [LPPDataPoint]`

### PacketBuilder / PacketParser

Stateless enums for manual packet construction and parsing if needed (internal use recommended).
