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
│   ├── Services/            # App-level services (NotificationService, MessageEventBroadcaster)
│   ├── Views/               # SwiftUI views organized by feature
│   │   ├── Chats/           # Conversation UI
│   │   ├── Contacts/        # Contact management UI
│   │   ├── Map/             # MapKit-based location display
│   │   ├── Settings/        # Configuration screens
│   │   ├── RemoteNodes/     # Room server and repeater UI
│   │   ├── Onboarding/      # First-launch flow
│   │   ├── Components/      # Reusable UI components
│   │   └── Modifiers/       # Custom view modifiers
│   ├── Extensions/          # Swift extensions
│   ├── Resources/           # Assets and Info.plist
│   ├── AppState.swift       # Central app state manager
│   └── ContentView.swift    # Root view with tab navigation
│
├── PocketMeshKit/           # Framework Target (Business Logic)
│   ├── Models/              # SwiftData models (Device, Contact, Message, Channel)
│   ├── Protocol/            # Binary protocol encoding/decoding
│   ├── Services/            # Core services (BLE, Messaging, Contacts)
│   └── Utilities/           # Shared utilities
│
├── PocketMeshTests/         # Unit Test Target
│   ├── Mock/                # Mock implementations
│   ├── Services/            # Service layer tests
│   ├── Protocol/            # Protocol codec tests
│   ├── Integration/         # Integration tests
│   ├── ViewModels/          # ViewModel tests
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
│   SwiftUI Views + ViewModels + AppState                │
├─────────────────────────────────────────────────────────┤
│                   Services Layer                        │
│   MessageService, ContactService, ChannelService, etc. │
├─────────────────────────────────────────────────────────┤
│                   Protocol Layer                        │
│   FrameCodec (encoding/decoding) + BLEService          │
├─────────────────────────────────────────────────────────┤
│                    Data Layer                           │
│   SwiftData Models + DataStore Actor                   │
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

All models are defined in `PocketMeshKit/Models/` and stored in a single `ModelContainer` managed by the `DataStore` actor.

#### Device (`Device.swift`)

Represents a connected MeshCore BLE device. Each device has its own isolated data store.

| Property | Type | Description |
|----------|------|-------------|
| `id` | `UUID` | Derived from BLE peripheral identifier |
| `publicKey` | `Data` | 32-byte Ed25519 public key |
| `nodeName` | `String` | Human-readable name |
| `firmwareVersion` | `UInt8` | Firmware version code |
| `frequency` | `UInt32` | Radio frequency in kHz |
| `bandwidth` | `UInt32` | Radio bandwidth in kHz |
| `spreadingFactor` | `UInt8` | LoRa SF (5-12) |
| `codingRate` | `UInt8` | LoRa CR (5-8) |
| `txPower` | `UInt8` | Transmit power in dBm |
| `latitude`, `longitude` | `Double` | Node location |
| `isActive` | `Bool` | Currently active device |
| `lastContactSync` | `UInt32` | Watermark for incremental sync |

#### Contact (`Contact.swift`)

Represents a contact discovered on the mesh network.

| Property | Type | Description |
|----------|------|-------------|
| `id` | `UUID` | Derived from public key hash |
| `deviceID` | `UUID` | Parent device (isolation key) |
| `publicKey` | `Data` | 32-byte public key |
| `name` | `String` | Display name |
| `typeRawValue` | `UInt8` | Contact type (chat/repeater/room) |
| `outPathLength` | `Int8` | Routing path length (-1 = flood) |
| `outPath` | `Data` | Routing path bytes (up to 64) |
| `latitude`, `longitude` | `Double` | Contact location |
| `lastAdvertTimestamp` | `UInt32` | Last advertisement timestamp |
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
| `statusRawValue` | `Int` | MessageStatus enum |
| `ackCode` | `UInt32?` | ACK tracking code |
| `snr` | `Int8?` | Signal-to-noise ratio (×4) |
| `roundTripTime` | `UInt32?` | RTT in milliseconds |

**Message Status Flow:**
```
pending → sending → sent → delivered
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

#### RemoteNodeSession (`RemoteNodeSession.swift`)

Represents an authenticated session with a remote node (room server or repeater).

| Property | Type | Description |
|----------|------|-------------|
| `deviceID` | `UUID` | Companion radio used for access |
| `publicKey` | `Data` | 32-byte remote node public key |
| `roleRawValue` | `UInt8` | RemoteNodeRole (repeater/roomServer) |
| `permissionLevelRawValue` | `UInt8` | RoomPermissionLevel (guest/readWrite/admin) |
| `isConnected` | `Bool` | Currently authenticated |

#### RoomMessage (`RoomMessage.swift`)

Represents a message in a room server conversation.

| Property | Type | Description |
|----------|------|-------------|
| `sessionID` | `UUID` | Parent RemoteNodeSession |
| `authorKeyPrefix` | `Data` | 4-byte author public key prefix |
| `authorName` | `String?` | Resolved author name |
| `text` | `String` | Message content |
| `deduplicationKey` | `String` | Key for preventing duplicates |

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

### Command Codes (Selected)

| Code | Name | Purpose |
|------|------|---------|
| `0x01` | appStart | Initialize app session |
| `0x02` | sendTextMessage | Send direct message |
| `0x03` | sendChannelTextMessage | Send channel message |
| `0x04` | getContacts | Retrieve contact list |
| `0x07` | sendSelfAdvert | Broadcast advertisement |
| `0x09` | addUpdateContact | Add or update contact |
| `0x0A` | syncNextMessage | Retrieve next queued message |
| `0x0B` | setRadioParams | Configure LoRa parameters |
| `0x16` | deviceQuery | Query device capabilities |
| `0x1A` | sendLogin | Authenticate with remote node |
| `0x32` | sendBinaryRequest | Binary protocol request |

### Response Codes (Selected)

| Code | Name | Purpose |
|------|------|---------|
| `0x00` | ok | Success |
| `0x01` | error | Error with error code |
| `0x03` | contact | Single contact entry |
| `0x05` | selfInfo | Device self-information |
| `0x06` | sent | Message queued (with ACK code) |
| `0x0D` | deviceInfo | Device capabilities |
| `0x10` | contactMessageReceivedV3 | Direct message with SNR |
| `0x11` | channelMessageReceivedV3 | Channel message with SNR |

### Push Codes

| Code | Name | Purpose |
|------|------|---------|
| `0x80` | advert | Contact advertisement received |
| `0x81` | pathUpdated | Routing path changed |
| `0x82` | sendConfirmed | Message delivery confirmed |
| `0x83` | messageWaiting | New message available |
| `0x85` | loginSuccess | Remote node authentication succeeded |
| `0x86` | loginFail | Remote node authentication failed |
| `0x8A` | newAdvert | New contact discovered |

### FrameCodec

`PocketMeshKit/Protocol/FrameCodec.swift`

Static methods for encoding commands and decoding responses:

```swift
// Encoding
FrameCodec.encodeDeviceQuery(protocolVersion: 8)
FrameCodec.encodeSendTextMessage(textType:attempt:timestamp:recipientKeyPrefix:text:)
FrameCodec.encodeAddUpdateContact(_:)

// Decoding
FrameCodec.decodeDeviceInfo(from:)
FrameCodec.decodeSelfInfo(from:)
FrameCodec.decodeContactFrame(from:)
FrameCodec.decodeMessageV3(from:)
```

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
│   MessageService, ContactService, ChannelService, etc.         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                       DataStore                                 │
│   SwiftData persistence (ModelActor)                           │
└─────────────────────────────────────────────────────────────────┘
```

### BLEService (`PocketMeshKit/Services/BLEService.swift`)

Core BLE transport implementation:

- **Connection States**: `disconnected → connecting → connected → ready`
- **Send Serialization**: Only one send operation at a time (others queue)
- **Response Timeout**: 5 seconds for normal operations, 40 seconds for pairing
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

**Retry Logic:**
```
Attempt 1-2: Direct routing
Attempt 3+: Flood routing (fallback)
Backoff: 200ms × attempt
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

### SettingsService (`PocketMeshKit/Services/SettingsService.swift`)

Device configuration:

- Radio parameters (frequency, bandwidth, SF, CR)
- TX power
- Node name and location
- Telemetry modes
- Factory reset

**Verified Settings:**
Read-modify-verify pattern with tolerance checking for coordinates.

### NotificationService (`PocketMesh/Services/NotificationService.swift`)

`@MainActor @Observable` class for local notifications:

- Categories: direct messages (with reply), channel messages, room messages, low battery
- Quick reply support via UNTextInputNotificationResponse
- Draft storage for failed quick replies
- Badge count management

---

## UI Layer

### Tab Structure

`ContentView.swift` uses SwiftUI's modern `TabView` with `Tab` API:

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

Central state manager injected via environment:

**Key State:**
- Onboarding: `hasCompletedOnboarding`, `onboardingStep`
- Connection: `connectionState`, `connectedDevice`, `isBLEBusy`
- Navigation: `selectedTab`, `pendingChatContact`, `pendingRoomSession`
- Sync: `isContactsSyncing`, `contactsSyncProgress`

**Services:**
All services are properties on AppState and passed to ViewModels.

### Reusable Components

| Component | Location | Purpose |
|-----------|----------|---------|
| `UnifiedMessageBubble` | `Views/Chats/Components/` | iMessage-style message display |
| `ChatInputBar` | `Views/Chats/Components/` | Text input with character counter |
| `BLEStatusIndicatorView` | `Views/Components/` | Connection status in toolbar |
| `SyncingPillView` | `Views/Components/` | Floating sync overlay |
| `NodeAvatar` | `Views/Components/` | Avatar for remote nodes |
| `ContactAnnotationView` | `Views/Map/` | Custom map pins |

---

## Testing Architecture

### Test Organization

Tests use Swift Testing framework with comprehensive mocks:

```
PocketMeshTests/
├── Mock/              # MockBLEPeripheral, MockKeychainService
├── Services/          # Service unit tests
├── Protocol/          # Protocol codec tests (150+ tests)
├── Integration/       # Multi-component tests
├── ViewModels/        # UI logic tests
├── Models/            # Data model tests
└── Helpers/           # Test utilities
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

### Test Patterns

**Service Tests:**
- Use `TestBLETransport` with queued responses
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

### Test Utilities

**MutableBox:** Thread-safe wrapper for capturing values in async closures
**Test Factories:** `createTestContact()`, `createTestMessage()`, `createSentResponse()`
**Service Stack Builder:** Wires up full service dependencies for integration tests

---

## Key File References

### Core Files

| File | Purpose |
|------|---------|
| `PocketMeshKit/Services/BLEService.swift` | BLE transport |
| `PocketMeshKit/Services/DataStore.swift` | SwiftData persistence |
| `PocketMeshKit/Protocol/FrameCodec.swift` | Protocol encoding/decoding |
| `PocketMeshKit/Protocol/ProtocolConstants.swift` | Command/response codes |
| `PocketMesh/AppState.swift` | Central state manager |
| `PocketMesh/ContentView.swift` | Root view with tabs |

### Models

| File | Purpose |
|------|---------|
| `PocketMeshKit/Models/Device.swift` | BLE device model |
| `PocketMeshKit/Models/Contact.swift` | Contact model |
| `PocketMeshKit/Models/Message.swift` | Message model |
| `PocketMeshKit/Models/Channel.swift` | Channel model |
| `PocketMeshKit/Models/RemoteNodeSession.swift` | Remote node session |
| `PocketMeshKit/Models/RoomMessage.swift` | Room message model |

### Services

| File | Purpose |
|------|---------|
| `PocketMeshKit/Services/MessageService.swift` | Message sending/retry |
| `PocketMeshKit/Services/ContactService.swift` | Contact management |
| `PocketMeshKit/Services/ChannelService.swift` | Channel management |
| `PocketMeshKit/Services/MessagePollingService.swift` | Incoming message polling |
| `PocketMeshKit/Services/RemoteNodeService.swift` | Remote node auth |
| `PocketMeshKit/Services/SettingsService.swift` | Device configuration |

### Views

| File | Purpose |
|------|---------|
| `PocketMesh/Views/Chats/ChatsListView.swift` | Conversations list |
| `PocketMesh/Views/Chats/ChatView.swift` | Direct message view |
| `PocketMesh/Views/Chats/ChatViewModel.swift` | Chat logic |
| `PocketMesh/Views/Contacts/ContactsListView.swift` | Contact list |
| `PocketMesh/Views/Map/MapView.swift` | Contact map |
| `PocketMesh/Views/Settings/SettingsView.swift` | Settings screen |
