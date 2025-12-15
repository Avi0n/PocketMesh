# PocketMesh Architecture

PocketMesh is a native iOS application for off-grid mesh messaging over MeshCore BLE devices. This document describes the system architecture and component interactions.

## Table of Contents

1. [Project Structure](#project-structure)
2. [Architecture Overview](#architecture-overview)
3. [Data Layer](#data-layer)
4. [Protocol Layer](#protocol-layer)
5. [Services Layer](#services-layer)
6. [UI Layer](#ui-layer)
7. [Testing Architecture](#testing-architecture)

---

## Project Structure

```
PocketMesh/
├── PocketMesh/              # iOS App Target
│   ├── Models/              # UI-specific models (Conversation, NotificationPreferences)
│   ├── Services/            # App-level services (MessageEventBroadcaster)
│   ├── Views/               # SwiftUI views organized by feature
│   │   ├── Chats/           # Conversation UI
│   │   │   └── Components/  # Chat-specific components (bubbles, input bar)
│   │   ├── Contacts/        # Contact management UI
│   │   ├── Map/             # MapKit-based location display
│   │   ├── Settings/        # Configuration screens
│   │   │   └── Sections/    # Modular settings sections
│   │   ├── RemoteNodes/     # Room server and repeater UI
│   │   ├── Onboarding/      # First-launch flow
│   │   ├── Components/      # Reusable UI components
│   │   └── Modifiers/       # Custom view modifiers
│   ├── Extensions/          # Swift extensions
│   ├── Resources/           # Assets and Info.plist
│   ├── PocketMeshApp.swift  # App entry point (@main)
│   ├── AppState.swift       # Central app state manager
│   └── ContentView.swift    # Root view (onboarding/main switch)
│
├── PocketMeshKit/           # Framework Target (Business Logic)
│   ├── Models/              # SwiftData models + DTOs + utility types
│   ├── Protocol/            # Binary protocol encoding/decoding
│   └── Services/            # Core services (BLE, Messaging, Contacts, etc.)
│
├── PocketMeshTests/         # Unit Test Target
│   ├── Mock/                # Mock implementations (MockBLEPeripheral, MockBLEPeripheralTests, MockKeychainService)
│   ├── Services/            # Service layer tests
│   ├── Protocol/            # Protocol codec tests
│   ├── Integration/         # Multi-component integration tests
│   ├── ViewModels/          # ViewModel tests
│   ├── Models/              # Data model tests
│   ├── BLE/                 # BLE-specific tests (reconnection, etc.)
│   └── Helpers/             # Test utilities
│
├── project.yml              # XcodeGen configuration
└── PRD.md                   # Product Requirements Document
```

### Target Dependencies

```
PocketMesh (App) ──depends──> PocketMeshKit (Framework)
PocketMeshTests  ──depends──> PocketMesh + PocketMeshKit
```

---

## Architecture Overview

PocketMesh follows a layered architecture with clear separation of concerns:

```
┌─────────────────────────────────────────────────────────┐
│                      UI Layer                           │
│     SwiftUI Views + ViewModels + AppState               │
├─────────────────────────────────────────────────────────┤
│                   Services Layer                        │
│  MessageService, ContactService, ChannelService, etc.   │
├─────────────────────────────────────────────────────────┤
│                   Protocol Layer                        │
│     FrameCodec (encoding/decoding) + BLEService         │
├─────────────────────────────────────────────────────────┤
│                    Data Layer                           │
│         SwiftData Models + DataStore Actor              │
└─────────────────────────────────────────────────────────┘
```

### Key Design Principles

1. **Actor Isolation**: All services except UI-related ones use Swift actors for thread-safe concurrency
2. **Per-Device Data Isolation**: All data (contacts, messages, channels) scoped by device ID
3. **@Observable Pattern**: ViewModels use Swift's `@Observable` macro for reactive UI updates
4. **Environment-Based DI**: Services injected via `AppState` environment object
5. **Protocol-First**: Binary protocol encoding/decoding isolated in `FrameCodec`

---

## Data Layer

### SwiftData Models

All models are defined in `PocketMeshKit/Models/` and stored in a single `ModelContainer` managed by the `DataStore` actor. Each model has a corresponding `DTO` struct for thread-safe cross-actor transfers.

#### Device (`Device.swift`)

Represents a connected MeshCore BLE device. Each device has its own isolated data store.

| Property | Type | Description |
|----------|------|-------------|
| `id` | `UUID` | Derived from BLE peripheral identifier |
| `publicKey` | `Data` | 32-byte Ed25519 public key |
| `nodeName` | `String` | Human-readable name |
| `firmwareVersion` | `UInt8` | Firmware version code |
| `firmwareVersionString` | `String` | Firmware version string (e.g., "v1.11.0") |
| `manufacturerName` | `String` | Manufacturer name |
| `buildDate` | `String` | Build date string |
| `maxContacts` | `UInt8` | Maximum contacts supported |
| `maxChannels` | `UInt8` | Maximum channels supported |
| `frequency` | `UInt32` | Radio frequency in kHz |
| `bandwidth` | `UInt32` | Radio bandwidth in kHz |
| `spreadingFactor` | `UInt8` | LoRa SF (5-12) |
| `codingRate` | `UInt8` | LoRa CR (5-8) |
| `txPower` | `UInt8` | Transmit power in dBm |
| `maxTxPower` | `UInt8` | Maximum TX power in dBm |
| `latitude`, `longitude` | `Double` | Node location |
| `blePin` | `UInt32` | BLE PIN (0 = disabled) |
| `manualAddContacts` | `Bool` | Manual add contacts mode |
| `multiAcks` | `Bool` | Multi-ACK mode enabled |
| `telemetryModeBase` | `UInt8` | Telemetry mode for base data |
| `telemetryModeLoc` | `UInt8` | Telemetry mode for location data |
| `telemetryModeEnv` | `UInt8` | Telemetry mode for environment data |
| `advertLocationPolicy` | `UInt8` | Advertisement location policy |
| `lastConnected` | `Date` | Last connection time |
| `lastContactSync` | `UInt32` | Watermark for incremental sync |
| `isActive` | `Bool` | Currently active device |

#### Contact (`Contact.swift`)

Represents a contact discovered on the mesh network.

| Property | Type | Description |
|----------|------|-------------|
| `id` | `UUID` | Derived from public key hash |
| `deviceID` | `UUID` | Parent device (isolation key) |
| `publicKey` | `Data` | 32-byte public key |
| `name` | `String` | Display name from device |
| `typeRawValue` | `UInt8` | Contact type (chat/repeater/room) |
| `flags` | `UInt8` | Permission flags |
| `outPathLength` | `Int8` | Routing path length (-1 = flood) |
| `outPath` | `Data` | Routing path bytes (up to 64) |
| `lastAdvertTimestamp` | `UInt32` | Last advertisement timestamp |
| `latitude`, `longitude` | `Double` | Contact location |
| `lastModified` | `UInt32` | Last modification timestamp (sync watermark) |
| `nickname` | `String?` | Local nickname override |
| `isBlocked` | `Bool` | Whether contact is blocked |
| `isFavorite` | `Bool` | Whether contact is pinned |
| `lastMessageDate` | `Date?` | Last message timestamp (for sorting) |
| `unreadCount` | `Int` | Unread message count |

#### Message (`Message.swift`)

Represents a message in a conversation.

| Property | Type | Description |
|----------|------|-------------|
| `id` | `UUID` | Message identifier |
| `deviceID` | `UUID` | Parent device |
| `contactID` | `UUID?` | Contact (for direct messages) |
| `channelIndex` | `UInt8?` | Channel index (for channel messages) |
| `text` | `String` | Message content |
| `timestamp` | `UInt32` | Device timestamp |
| `createdAt` | `Date` | Local creation date |
| `directionRawValue` | `Int` | MessageDirection enum |
| `statusRawValue` | `Int` | MessageStatus enum |
| `textTypeRawValue` | `UInt8` | TextType (plain/signed/cli) |
| `ackCode` | `UInt32?` | ACK tracking code |
| `pathLength` | `UInt8` | Path length when received |
| `snr` | `Int8?` | Signal-to-noise ratio (×4) |
| `senderKeyPrefix` | `Data?` | 6-byte sender public key prefix |
| `senderNodeName` | `String?` | Sender name (for channel messages) |
| `isRead` | `Bool` | Whether read locally |
| `replyToID` | `UUID?` | Reply-to message ID |
| `roundTripTime` | `UInt32?` | RTT in milliseconds |
| `heardRepeats` | `Int` | Count of mesh repeats heard |

**Message Status Flow:**
```
pending → sending → sent → delivered → read
                     ↓
                   failed
```

#### Channel (`Channel.swift`)

Represents a channel for broadcast messaging (up to 8 slots, index 0-7).

| Property | Type | Description |
|----------|------|-------------|
| `id` | `UUID` | Channel identifier |
| `deviceID` | `UUID` | Parent device |
| `index` | `UInt8` | Channel slot (0-7) |
| `name` | `String` | Channel name |
| `secret` | `Data` | 16-byte channel secret (SHA-256 of passphrase) |
| `isEnabled` | `Bool` | Whether channel is active |
| `lastMessageDate` | `Date?` | Last message timestamp |
| `unreadCount` | `Int` | Unread message count |

#### RemoteNodeSession (`RemoteNodeSession.swift`)

Represents an authenticated session with a remote node (room server or repeater).

| Property | Type | Description |
|----------|------|-------------|
| `id` | `UUID` | Session identifier |
| `deviceID` | `UUID` | Companion radio used for access |
| `publicKey` | `Data` | 32-byte remote node public key |
| `name` | `String` | Human-readable node name |
| `roleRawValue` | `UInt8` | RemoteNodeRole (repeater/roomServer) |
| `latitude`, `longitude` | `Double` | Node location |
| `isConnected` | `Bool` | Currently authenticated |
| `permissionLevelRawValue` | `UInt8` | RoomPermissionLevel (guest/readWrite/admin) |
| `lastConnectedDate` | `Date?` | Last successful connection |
| `lastBatteryMillivolts` | `UInt16?` | Cached battery level |
| `lastUptimeSeconds` | `UInt32?` | Cached uptime |
| `lastNoiseFloor` | `Int16?` | Cached noise floor |
| `unreadCount` | `Int` | Unread message count (room) |
| `lastRxAirtimeSeconds` | `UInt32?` | Last RX airtime (repeater) |
| `neighborCount` | `Int` | Number of neighbors (repeater) |

#### RoomMessage (`RoomMessage.swift`)

Represents a message in a room server conversation.

| Property | Type | Description |
|----------|------|-------------|
| `id` | `UUID` | Message identifier |
| `sessionID` | `UUID` | Parent RemoteNodeSession |
| `authorKeyPrefix` | `Data` | 4-byte author public key prefix |
| `authorName` | `String?` | Resolved author name |
| `text` | `String` | Message content |
| `timestamp` | `UInt32` | Server timestamp |
| `createdAt` | `Date` | Local creation date |
| `isFromSelf` | `Bool` | Posted by current user |
| `deduplicationKey` | `String` | Key for preventing duplicates |

#### RadioPreset (`RadioPreset.swift`)

Radio configuration preset for common regional settings (not persisted).

| Property | Type | Description |
|----------|------|-------------|
| `id` | `String` | Preset identifier |
| `name` | `String` | Display name |
| `region` | `RadioRegion` | Geographic region |
| `frequencyMHz` | `Double` | Radio frequency |
| `spreadingFactor` | `UInt8` | LoRa SF |
| `bandwidthKHz` | `Double` | Radio bandwidth |
| `codingRate` | `UInt8` | LoRa CR |

#### TelemetryModes (`TelemetryModes.swift`)

Packed telemetry modes for all three categories (utility struct).

| Property | Type | Description |
|----------|------|-------------|
| `base` | `TelemetryMode` | Base data mode |
| `location` | `TelemetryMode` | Location data mode |
| `environment` | `TelemetryMode` | Environment data mode |

#### TrustedContactsManager (`TrustedContacts.swift`)

`@MainActor @Observable` manager for app-side trusted contacts for telemetry filtering.

### DTO Pattern

All SwiftData models have corresponding `DTO` structs for safe cross-actor transfers:

- `DeviceDTO`, `ContactDTO`, `MessageDTO`, `ChannelDTO`
- `RemoteNodeSessionDTO`, `RoomMessageDTO`

DTOs are `Sendable`, `Equatable`, and `Identifiable`, with computed properties mirroring the model.

### App-Level Models

Located in `PocketMesh/Models/`, these are UI-specific models not part of the framework.

#### Conversation (`Conversation.swift`)

Enum representing a conversation in the chat list.

| Case | Associated Value | Description |
|------|------------------|-------------|
| `direct` | `ContactDTO` | Direct chat with a contact |
| `channel` | `ChannelDTO` | Channel broadcast conversation |
| `room` | `RemoteNodeSessionDTO` | Room server conversation |

**Computed Properties:** `id`, `displayName`, `lastMessageDate`, `unreadCount`, `isChannel`, `isRoom`, `channelIndex`, `contact`, `channel`, `roomSession`

#### NotificationPreferences (`NotificationPreferences.swift`)

`@MainActor @Observable` class for notification settings backed by UserDefaults.

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `contactMessagesEnabled` | `Bool` | `true` | Notify for direct messages |
| `channelMessagesEnabled` | `Bool` | `true` | Notify for channel messages |
| `roomMessagesEnabled` | `Bool` | `true` | Notify for room messages |
| `newContactDiscoveredEnabled` | `Bool` | `false` | Notify when new contacts discovered |
| `soundEnabled` | `Bool` | `true` | Enable notification sounds |
| `badgeEnabled` | `Bool` | `true` | Enable badge count on app icon |

### DataStore Actor

`PocketMeshKit/Services/DataStore.swift`

The `DataStore` is a `@ModelActor` that provides thread-safe SwiftData operations.

**Key Operations:**
- **Device**: fetch, save, setActive, delete (with cascade)
- **Contact**: fetch by device/ID/publicKey/prefix, save, update unread count
- **Message**: fetch by contact/channel, save, update status/ACK
- **Channel**: fetch by device/index, save
- **RemoteNodeSession**: fetch, save, update connection state
- **RoomMessage**: save with deduplication, fetch by session

**Per-Device Isolation:**

All queries filter by `deviceID` to ensure data separation:

```swift
let predicate = #Predicate<Contact> { contact in
    contact.deviceID == targetDeviceID
}
```

---

## Protocol Layer

### Protocol Files

| File | Purpose |
|------|---------|
| `ProtocolConstants.swift` | Command/response/push codes, enums, limits |
| `FrameCodec.swift` | Binary encoding/decoding methods |
| `ProtocolFrames.swift` | Sendable frame types (DeviceInfo, SelfInfo, ContactFrame, etc.) |
| `LPPDecoder.swift` | Cayenne Low Power Payload decoder for telemetry |

### Nordic UART Service (BLE Transport)

Communication uses the Nordic UART Service over BLE:

| UUID | Purpose |
|------|---------|
| `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` | Service UUID |
| `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` | TX Characteristic (write to device) |
| `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` | RX Characteristic (notifications from device) |

### Frame Structure

All frames use little-endian byte order with a single-byte code prefix:

**Commands (Client → Device):**
```
[CommandCode:1][Parameters:N]
```

**Responses (Device → Client):**
```
[ResponseCode:1][Data:N]
```

**Push Notifications (Device → Client, unsolicited):**
```
[PushCode:1][Data:N]  // PushCode >= 0x80
```

### Command Codes

*Note: This lists commonly-used commands. See `ProtocolConstants.swift` for the complete set (~40 commands).*

| Code | Name | Purpose |
|------|------|---------|
| `0x01` | appStart | Initialize app session |
| `0x02` | sendTextMessage | Send direct message |
| `0x03` | sendChannelTextMessage | Send channel message |
| `0x04` | getContacts | Retrieve contact list |
| `0x05` | getDeviceTime | Get device clock |
| `0x06` | setDeviceTime | Set device clock |
| `0x07` | sendSelfAdvert | Broadcast advertisement |
| `0x08` | setAdvertName | Set node name |
| `0x09` | addUpdateContact | Add or update contact |
| `0x0A` | syncNextMessage | Retrieve next queued message |
| `0x0B` | setRadioParams | Configure LoRa parameters |
| `0x0C` | setRadioTxPower | Set TX power |
| `0x0D` | resetPath | Reset contact path to flood |
| `0x0E` | setAdvertLatLon | Set node location |
| `0x0F` | removeContact | Delete a contact |
| `0x16` | deviceQuery | Query device capabilities |
| `0x1A` | sendLogin | Authenticate with remote node |
| `0x1B` | sendStatusRequest | Request node status |
| `0x1D` | logout | Logout from remote node |
| `0x1E` | getContactByKey | Get contact by public key |
| `0x1F` | getChannel | Get channel config |
| `0x20` | setChannel | Set channel config |
| `0x26` | setOtherParams | Set misc parameters |
| `0x27` | sendTelemetryRequest | Request telemetry data |
| `0x2A` | getAdvertPath | Get cached advert path |
| `0x32` | sendBinaryRequest | Binary protocol request |
| `0x33` | factoryReset | Factory reset device |
| `0x34` | sendPathDiscoveryRequest | Trigger path discovery |
| `0x37` | sendControlData | Send control data (node discovery) |
| `0x38` | getStats | Get device statistics |

### Response Codes

*Note: This lists commonly-used responses. See `ProtocolConstants.swift` for the complete set (~25 responses).*

| Code | Name | Purpose |
|------|------|---------|
| `0x00` | ok | Success |
| `0x01` | error | Error with error code |
| `0x02` | contactsStart | Contact sync starting |
| `0x03` | contact | Single contact entry |
| `0x04` | endOfContacts | Contact sync complete |
| `0x05` | selfInfo | Device self-information |
| `0x06` | sent | Message queued (with ACK code) |
| `0x09` | currentTime | Device time response |
| `0x0A` | noMoreMessages | Message queue empty |
| `0x0C` | batteryAndStorage | Battery/storage info |
| `0x0D` | deviceInfo | Device capabilities |
| `0x10` | contactMessageReceivedV3 | Direct message with SNR |
| `0x11` | channelMessageReceivedV3 | Channel message with SNR |
| `0x12` | channelInfo | Channel configuration |
| `0x16` | advertPath | Cached advertisement path |
| `0x18` | stats | Device statistics |
| `0x19` | hasConnection | Connection check response |

### Push Codes

| Code | Name | Purpose |
|------|------|---------|
| `0x80` | advert | Contact advertisement received |
| `0x81` | pathUpdated | Routing path changed |
| `0x82` | sendConfirmed | Message delivery confirmed |
| `0x83` | messageWaiting | New message available |
| `0x84` | rawData | Raw data received |
| `0x85` | loginSuccess | Remote node authentication succeeded |
| `0x86` | loginFail | Remote node authentication failed |
| `0x87` | statusResponse | Status response from remote node |
| `0x88` | logRxData | RX log data |
| `0x89` | traceData | Path trace data |
| `0x8A` | newAdvert | New contact discovered |
| `0x8B` | telemetryResponse | Telemetry data response |
| `0x8C` | binaryResponse | Binary protocol response |
| `0x8D` | pathDiscoveryResponse | Path discovery result |
| `0x8E` | controlData | Control data (node discovery) |

### FrameCodec

`PocketMeshKit/Protocol/FrameCodec.swift`

Static methods for encoding commands and decoding responses:

```swift
// Encoding
FrameCodec.encodeDeviceQuery(protocolVersion: 8)
FrameCodec.encodeSendTextMessage(textType:attempt:timestamp:recipientKeyPrefix:text:)
FrameCodec.encodeAddUpdateContact(_:)
FrameCodec.encodeSetChannel(_:)
FrameCodec.encodeSendLogin(recipientKeyPrefix:password:)

// Decoding
FrameCodec.decodeDeviceInfo(from:)
FrameCodec.decodeSelfInfo(from:)
FrameCodec.decodeContactFrame(from:)
FrameCodec.decodeMessageV3(from:)
FrameCodec.decodeChannelInfo(from:)
```

### ProtocolFrames

`PocketMeshKit/Protocol/ProtocolFrames.swift`

Sendable frame types for decoded protocol data:

- `DeviceInfo` - Device capabilities and firmware info
- `SelfInfo` - Device self-information (public key, radio config)
- `ContactFrame` - Contact data from sync
- `MessageFrame` - Direct message data
- `ChannelMessageFrame` - Channel message data
- `ChannelInfo` - Channel configuration
- `SentResponse` - ACK code after message send

### Data Encoding Conventions

| Type | Encoding |
|------|----------|
| Integers | Little-endian |
| Coordinates | Int32 microdegrees (× 1,000,000) |
| SNR | Int8 quarter-dB (× 4) |
| Strings | UTF-8, null-terminated or fixed-width |
| Public Keys | 32 bytes (Ed25519), often truncated to 6-byte prefix |
| Channel Secrets | 16 bytes (SHA-256 of passphrase, first 16 bytes) |

---

## Services Layer

### Service Architecture

All services are Swift actors for thread-safe operation:

```
┌─────────────────────────────────────────────────────────────────┐
│                        BLEService                               │
│   BLE connection management, data chunking, timeouts           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Domain Services                             │
│   MessageService, ContactService, ChannelService,              │
│   MessagePollingService, SettingsService, AdvertisementService │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Remote Node Services                          │
│   RemoteNodeService, RoomServerService, RepeaterAdminService,  │
│   BinaryProtocolService                                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                       DataStore                                 │
│   SwiftData persistence (ModelActor)                           │
└─────────────────────────────────────────────────────────────────┘
```

### Service Files

| File | Purpose |
|------|---------|
| `BLEService.swift` | BLE transport, connection management |
| `BLEStateRestoration.swift` | iOS BLE state restoration handling |
| `DataStore.swift` | SwiftData persistence (ModelActor) |
| `MessageService.swift` | Message sending with retry/ACK |
| `ContactService.swift` | Contact sync and management |
| `ChannelService.swift` | Channel configuration |
| `MessagePollingService.swift` | Incoming message polling |
| `SettingsService.swift` | Device configuration |
| `AdvertisementService.swift` | Device advertisements and path discovery |
| `RemoteNodeService.swift` | Shared remote node operations |
| `RoomServerService.swift` | Room server interactions |
| `RepeaterAdminService.swift` | Repeater management |
| `BinaryProtocolService.swift` | Binary protocol for remote nodes |
| `NotificationService.swift` | Local notifications |
| `KeychainService.swift` | Secure credential storage |
| `AccessorySetupKitService.swift` | Device discovery/pairing |

### BLEService (`PocketMeshKit/Services/BLEService.swift`)

Core BLE transport implementation:

- **Connection States**: `disconnected → connecting → connected → ready`
- **Send Serialization**: Only one send operation at a time (others queue)
- **Response Timeout**: 5 seconds for normal operations
- **Auto-Reconnect**: iOS 17+ automatic reconnection with characteristic re-subscription
- **Pairing Window**: 35-second tolerance for transient errors during iOS pairing dialog

**Connection Flow:**
```
1. Discover peripheral
2. Connect with timeout (10s)
3. Discover Nordic UART service
4. Discover TX/RX characteristics
5. Subscribe to RX notifications
6. Initialize device (deviceQuery + appStart)
7. State = ready
```

### MessageService (`PocketMeshKit/Services/MessageService.swift`)

Handles message sending with retry and ACK tracking:

**Direct Messaging:**
1. Save message as pending
2. Encode and send via BLE
3. Receive RESP_CODE_SENT with ACK code
4. Track pending ACK with timeout
5. On PUSH_CODE_SEND_CONFIRMED, mark delivered

**Retry Logic (configurable via `MessageServiceConfig`):**
```
- floodAfter: Switch to flood after N direct attempts (default: 2)
- maxAttempts: Maximum total attempts (default: 3)
- maxFloodAttempts: Maximum flood attempts (default: 2)
- Backoff: 200ms × attempt number (200ms, 400ms, 600ms...)
```

**ACK Tracking:**
- First confirmation: Mark delivered, record RTT
- Subsequent confirmations: Increment `heardRepeats` counter
- Timeout: Configurable, uses device-reported timeout × 1.2

### ContactService (`PocketMeshKit/Services/ContactService.swift`)

Manages mesh network contacts:

**Sync Operation:**
```
1. Send CMD_GET_CONTACTS (with optional since timestamp)
2. Receive RESP_CODE_CONTACTS_START (total count)
3. Poll for each contact (RESP_CODE_CONTACT)
4. Save to DataStore
5. RESP_CODE_END_OF_CONTACTS (sync timestamp)
```

**Path Management:**
- `resetPath()`: Force flood routing (outPathLength = -1)
- `sendPathDiscovery()`: Trigger bidirectional path discovery
- `getAdvertPath()`: Query cached advertisement path

### ChannelService (`PocketMeshKit/Services/ChannelService.swift`)

Manages broadcast channels:

- **Secret Hashing**: SHA-256 of passphrase, first 16 bytes
- **Public Channel**: Slot 0 with zero secret
- **Sync**: Fetches all 8 channel slots on initialization

### MessagePollingService (`PocketMeshKit/Services/MessagePollingService.swift`)

Polls incoming message queue:

**Push Handling:**
```
PUSH_CODE_MSG_WAITING → syncMessageQueue()
  → CMD_SYNC_NEXT_MSG repeatedly
  → Until RESP_CODE_NO_MORE_MESSAGES
```

**Message Processing:**
- V3 direct messages: Look up contact by 6-byte sender prefix
- V3 channel messages: Parse "NodeName: MessageText" format
- Room messages: Route to RoomServerService

### AdvertisementService (`PocketMeshKit/Services/AdvertisementService.swift`)

Manages device advertisements and path discovery:

- Send self-advertisement broadcasts
- Trigger and track path discovery requests
- Query cached advertisement paths from contacts

### RemoteNodeService (`PocketMeshKit/Services/RemoteNodeService.swift`)

Shared service for room servers and repeater admin:

**Session Management:**
- Creates/updates sessions stored in DataStore
- Stores passwords in Keychain if remembered
- Calculates timeout based on path length (5s base + 10s per hop)

**Keep-Alive:**
- Periodic keep-alive every 90 seconds
- Only works with direct routing
- ACK contains unsynced message count

### RoomServerService (`PocketMeshKit/Services/RoomServerService.swift`)

Room server-specific operations:

- Login/logout from room servers
- Message sync and posting
- Permission level handling

### RepeaterAdminService (`PocketMeshKit/Services/RepeaterAdminService.swift`)

Repeater admin operations:

- Login/logout from repeater nodes
- Status queries (battery, uptime, noise floor)
- Neighbor information

### BinaryProtocolService (`PocketMeshKit/Services/BinaryProtocolService.swift`)

Binary protocol for remote node communication:

- Status requests
- Keep-alive messages
- Telemetry queries

### SettingsService (`PocketMeshKit/Services/SettingsService.swift`)

Device configuration:

- Radio parameters (frequency, bandwidth, SF, CR)
- TX power
- Node name and location
- Telemetry modes
- Factory reset

**Verified Settings:**
Read-modify-verify pattern with tolerance checking for coordinates.

### NotificationService (`PocketMeshKit/Services/NotificationService.swift`)

`@MainActor @Observable` class for local notifications:

- Categories: direct messages (with reply), channel messages, room messages, low battery
- Quick reply support via UNTextInputNotificationResponse
- Draft storage for failed quick replies
- Badge count management

### KeychainService (`PocketMeshKit/Services/KeychainService.swift`)

Secure credential storage:

- Store/retrieve remote node passwords
- Keychain access with proper error handling

### AccessorySetupKitService (`PocketMeshKit/Services/AccessorySetupKitService.swift`)

Device discovery and pairing:

- iOS AccessorySetupKit integration
- BLE device discovery
- Pairing flow management

---

## UI Layer

### Root View Structure

`ContentView.swift` contains separate structs for the main app structure:

- `OnboardingView` - First-launch flow coordinator
- `MainTabView` - Main tab-based navigation

```swift
// ContentView.swift
if appState.hasCompletedOnboarding {
    MainTabView()
} else {
    OnboardingView()
}
```

`MainTabView` (defined in `ContentView.swift`) uses SwiftUI's modern `TabView` with `Tab` API:

| Tab | View | Purpose |
|-----|------|---------|
| 0 | ChatsListView | Conversations list |
| 1 | ContactsListView | Contact management |
| 2 | MapView | Contact locations |
| 3 | SettingsView | Configuration |

### Navigation Patterns

**Per-Tab NavigationStack:**
Each tab maintains its own `NavigationPath` for hierarchical navigation.

**Navigation Destinations:**
```swift
.navigationDestination(for: ContactDTO.self) { contact in
    ChatView(contact: contact)
}
.navigationDestination(for: ChannelDTO.self) { channel in
    ChannelChatView(channel: channel)
}
```

**Cross-Tab Navigation:**
`AppState` provides pending navigation properties for cross-tab navigation from Map or notification taps.

### ViewModels

All ViewModels use `@Observable` and `@MainActor`:

| ViewModel | Location | Purpose |
|-----------|----------|---------|
| `ChatViewModel` | `Views/Chats/` | Chat operations, message loading |
| `ContactsViewModel` | `Views/Contacts/` | Contact list, sync, filtering |
| `MapViewModel` | `Views/Map/` | Map display, contact selection |
| `PathManagementViewModel` | `Views/Contacts/` | Path discovery and editing |
| `RoomConversationViewModel` | `Views/RemoteNodes/` | Room chat |
| `RepeaterStatusViewModel` | `Views/RemoteNodes/` | Repeater admin |

**Configuration Pattern:**
```swift
@Observable
@MainActor
final class SomeViewModel {
    private var dataStore: DataStore?

    func configure(appState: AppState) {
        self.dataStore = appState.dataStore
    }
}
```

### AppState

`PocketMesh/AppState.swift`

Central state manager (`@Observable @MainActor`) injected via environment:

**Key State:**
- Onboarding: `hasCompletedOnboarding`, `onboardingStep`
- Connection: `connectionState`, `connectedDevice`, `isBLEBusy`
- Navigation: `selectedTab`, `pendingChatContact`, `pendingRoomSession`
- Sync: `isContactsSyncing`, `contactsSyncProgress`
- Activity: `shouldShowSyncingPill` (derived from sync/polling counters)

**Services (all owned by AppState):**
- `bleService`, `bleStateRestoration`, `accessorySetupKit`
- `dataStore`, `messageService`, `contactService`, `channelService`
- `messagePollingService`, `settingsService`, `advertisementService`
- `remoteNodeService`, `roomServerService`, `repeaterAdminService`
- `binaryProtocolService`, `notificationService`, `messageEventBroadcaster`

### App-Level Services

`PocketMesh/Services/` contains app-level (non-framework) services:

| Service | Purpose |
|---------|---------|
| `MessageEventBroadcaster` | Broadcasts message events for UI updates |

### Reusable Components

| Component | Location | Purpose |
|-----------|----------|---------|
| `UnifiedMessageBubble` | `Views/Chats/Components/` | iMessage-style message display |
| `ChatInputBar` | `Views/Chats/Components/` | Text input with character counter |
| `MessageTimestampView` | `Views/Chats/Components/` | Formatted message timestamps |
| `BLEStatusIndicatorView` | `Views/Components/` | Connection status in toolbar |
| `SyncingPillView` | `Views/Components/` | Floating sync overlay |
| `NodeAvatar` | `Views/Components/` | Avatar for remote nodes |
| `ContactAnnotationView` | `Views/Map/` | Custom map pins |

### Settings Sections

`Views/Settings/Sections/` contains modular settings UI:

| Section | Purpose |
|---------|---------|
| `DeviceInfoSection` | Device name and info display |
| `NodeSettingsSection` | Node name and location |
| `RadioPresetSection` | Radio preset selection |
| `AdvancedRadioSection` | Manual radio parameters |
| `TelemetrySettingsSection` | Telemetry mode configuration |
| `ContactsSettingsSection` | Contact sync settings |
| `NotificationSettingsSection` | Notification preferences |
| `BluetoothSection` | BLE connection management |
| `DangerZoneSection` | Factory reset, etc. |
| `AboutSection` | App version and info |
| `NoDeviceSection` | No device connected state |
| `ErrorAlertModifier` | Error alert presentation modifier |
| `RetryAlertModifier` | Retry confirmation alert modifier |

### Additional Views

#### Chat Views (`Views/Chats/`)

| View | Purpose |
|------|---------|
| `ChannelOptionsSheet` | Channel management options |
| `JoinPrivateChannelView` | Join private channel UI |
| `JoinPublicChannelView` | Join public channel UI |
| `JoinHashtagChannelView` | Join hashtag channel UI |
| `ScanChannelQRView` | QR code scanner for channels |
| `CreatePrivateChannelView` | Create private channel UI |
| `ChannelInfoSheet` | Channel information display |

#### Contact Views (`Views/Contacts/`)

| View | Purpose |
|------|---------|
| `PathEditingSheet` | Manual path editing UI |

#### Settings Views (`Views/Settings/`)

| View | Purpose |
|------|---------|
| `RadioConfigView` | Detailed radio configuration |
| `DeviceSelectionSheet` | Device picker sheet |
| `TrustedContactsPickerView` | Trusted contacts selection |
| `AdvancedSettingsView` | Advanced settings screen |
| `LocationPickerView` | Node location picker |
| `DeviceInfoView` | Device information display |

#### Remote Node Views (`Views/RemoteNodes/`)

| View | Purpose |
|------|---------|
| `NodeAuthenticationSheet` | Node login UI |
| `RoomMessageBubble` | Room message display component |

#### Onboarding Views (`Views/Onboarding/`)

| View | Purpose |
|------|---------|
| `WelcomeView` | Welcome screen with app introduction |
| `PermissionsView` | Bluetooth and notification permissions request |
| `DeviceScanView` | BLE device discovery and pairing |

### View Modifiers

`Views/Modifiers/` contains custom SwiftUI view modifiers:

| Modifier | Purpose |
|----------|---------|
| `KeyboardToolbarModifier` | Keyboard toolbar with dismiss button |

### Extensions

`PocketMesh/Extensions/` contains Swift extensions for the app target:

| File | Purpose |
|------|---------|
| `ViewExtensions.swift` | SwiftUI View helper extensions |

---

## Testing Architecture

### Test Organization

Tests use Swift Testing framework with comprehensive mocks:

```
PocketMeshTests/
├── Mock/              # MockBLEPeripheral, MockBLEPeripheralTests, MockKeychainService
├── Services/          # Service unit tests
├── Protocol/          # Protocol codec tests
├── Integration/       # Multi-component integration tests
├── ViewModels/        # ViewModel unit tests
├── Models/            # Data model tests (RemoteNodeSession, etc.)
├── BLE/               # BLE-specific tests (reconnection, etc.)
├── Performance/       # Performance benchmarks (reserved, currently empty)
└── Helpers/           # Test utilities (MutableBox)
```

### MockBLEPeripheral

`PocketMeshTests/Mock/MockBLEPeripheral.swift`

Complete simulator of a MeshCore BLE device:

- Processes all protocol commands
- Maintains device state (contacts, channels, radio config)
- Generates proper responses
- Simulates push notifications

**Test Helpers:**
```swift
await mock.addContact(...)           // Inject contacts
await mock.queueIncomingMessage(...) // Queue messages
await mock.simulatePush(...)         // Trigger push
await mock.simulateSendConfirmed(...) // Simulate ACK
```

### MockKeychainService

`PocketMeshTests/Mock/MockKeychainService.swift`

In-memory keychain for testing credential storage without affecting system keychain.

### Test Patterns

**Service Tests:**
- Use `TestBLETransport` with queued responses (defined in `MessageServiceTests.swift`)
- Test command encoding, error handling, database persistence
- Async with `await #expect(throws:)`

**Protocol Tests:**
- Verify byte-level frame construction
- Test all command codes and response parsing
- Validate field sizes, byte order, padding

**Integration Tests:**
- Use `MockBLEPeripheral` for full protocol simulation
- Test multi-service workflows
- In-memory DataStore via `createContainer(inMemory: true)`

**BLE Tests:**
- Reconnection behavior
- State restoration

### Test Utilities

**Shared Utilities (`Helpers/TestHelpers.swift`):**

| Utility | Purpose |
|---------|---------|
| `MutableBox` | Thread-safe wrapper for capturing values in async closures |

**Per-File Test Helpers:**

Test files define their own private factory functions as needed:
- `createTestContact()` - Factory for test contacts (various signatures per test file)
- `createTestMessage()` - Factory for test messages
- `createSentResponse()` - Factory for sent response frames
- `TestBLETransport` - Mock BLE transport with queued responses (in `MessageServiceTests.swift`)

---

## Key File References

### Core Files

| File | Purpose |
|------|---------|
| `PocketMeshKit/Services/BLEService.swift` | BLE transport |
| `PocketMeshKit/Services/DataStore.swift` | SwiftData persistence |
| `PocketMeshKit/Protocol/FrameCodec.swift` | Protocol encoding/decoding |
| `PocketMeshKit/Protocol/ProtocolConstants.swift` | Command/response codes |
| `PocketMeshKit/Protocol/ProtocolFrames.swift` | Sendable frame types |
| `PocketMeshKit/Protocol/LPPDecoder.swift` | Telemetry payload decoder |
| `PocketMesh/AppState.swift` | Central state manager |
| `PocketMesh/ContentView.swift` | Root view (onboarding/main switch) |

### Models

| File | Purpose |
|------|---------|
| `PocketMeshKit/Models/Device.swift` | BLE device model + DeviceDTO |
| `PocketMeshKit/Models/Contact.swift` | Contact model + ContactDTO |
| `PocketMeshKit/Models/Message.swift` | Message model + MessageDTO |
| `PocketMeshKit/Models/Channel.swift` | Channel model + ChannelDTO |
| `PocketMeshKit/Models/RemoteNodeSession.swift` | Remote node session + DTO |
| `PocketMeshKit/Models/RoomMessage.swift` | Room message model + DTO |
| `PocketMeshKit/Models/RadioPreset.swift` | Radio configuration presets |
| `PocketMeshKit/Models/TelemetryModes.swift` | Telemetry mode utilities |
| `PocketMeshKit/Models/TrustedContacts.swift` | Trusted contacts manager |
| `PocketMesh/Models/Conversation.swift` | Chat list conversation enum |
| `PocketMesh/Models/NotificationPreferences.swift` | Notification settings |

### Services

| File | Purpose |
|------|---------|
| `PocketMeshKit/Services/MessageService.swift` | Message sending/retry |
| `PocketMeshKit/Services/ContactService.swift` | Contact management |
| `PocketMeshKit/Services/ChannelService.swift` | Channel management |
| `PocketMeshKit/Services/MessagePollingService.swift` | Incoming message polling |
| `PocketMeshKit/Services/SettingsService.swift` | Device configuration |
| `PocketMeshKit/Services/AdvertisementService.swift` | Advertisements/path discovery |
| `PocketMeshKit/Services/RemoteNodeService.swift` | Shared remote node operations |
| `PocketMeshKit/Services/RoomServerService.swift` | Room server interactions |
| `PocketMeshKit/Services/RepeaterAdminService.swift` | Repeater management |
| `PocketMeshKit/Services/BinaryProtocolService.swift` | Binary protocol for nodes |
| `PocketMeshKit/Services/NotificationService.swift` | Local notifications |
| `PocketMeshKit/Services/KeychainService.swift` | Secure credential storage |
| `PocketMeshKit/Services/AccessorySetupKitService.swift` | Device discovery/pairing |
| `PocketMeshKit/Services/BLEStateRestoration.swift` | BLE state restoration |

### Views

| File | Purpose |
|------|---------|
| `PocketMesh/Views/Chats/ChatsListView.swift` | Conversations list |
| `PocketMesh/Views/Chats/ChatView.swift` | Direct message view |
| `PocketMesh/Views/Chats/ChatViewModel.swift` | Chat logic |
| `PocketMesh/Views/Chats/ChannelChatView.swift` | Channel message view |
| `PocketMesh/Views/Contacts/ContactsListView.swift` | Contact list |
| `PocketMesh/Views/Contacts/ContactsViewModel.swift` | Contact list logic |
| `PocketMesh/Views/Contacts/ContactDetailView.swift` | Contact details |
| `PocketMesh/Views/Map/MapView.swift` | Contact map |
| `PocketMesh/Views/Map/MapViewModel.swift` | Map logic |
| `PocketMesh/Views/Settings/SettingsView.swift` | Settings screen |
| `PocketMesh/Views/RemoteNodes/RoomConversationView.swift` | Room chat view |
| `PocketMesh/Views/RemoteNodes/RepeaterStatusView.swift` | Repeater admin view |
