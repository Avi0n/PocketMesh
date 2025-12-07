# PocketMesh iOS Application Implementation Plan

## Overview

PocketMesh is a native iOS application that enables seamless messaging and configuration over MeshCore BLE (Bluetooth Low Energy) devices. This plan outlines a complete implementation from project setup through App Store readiness, with emphasis on 100% MeshCore protocol compliance and comprehensive testing via a Mock BLE Device.

**Target**: iOS 26.1, Swift 6.1, Strict Concurrency Mode

## Current State Analysis

### What Exists
- PRD.md with comprehensive requirements
- MeshCore-firmware-example reference code defining the complete protocol
- Empty project directory (no Swift files yet)
- XcodeGen configuration requirement
- thoughts/shared/plans directory for planning

### Key Discoveries from MeshCore Protocol Analysis

From `MyMesh.cpp` and `MyMesh.h`:

**Command Codes (Client → Device)**:
| Code | Name | Description |
|------|------|-------------|
| 0x01 | CMD_APP_START | Initialize connection, receive node info |
| 0x02 | CMD_SEND_TXT_MSG | Send direct text message |
| 0x03 | CMD_SEND_CHANNEL_TXT_MSG | Send channel broadcast |
| 0x04 | CMD_GET_CONTACTS | Request contact list (with optional since filter) |
| 0x05 | CMD_GET_DEVICE_TIME | Get device RTC time |
| 0x06 | CMD_SET_DEVICE_TIME | Set device RTC time |
| 0x07 | CMD_SEND_SELF_ADVERT | Send advertisement (0=zero-hop, 1=flood) |
| 0x08 | CMD_SET_ADVERT_NAME | Set node name |
| 0x09 | CMD_ADD_UPDATE_CONTACT | Add or update contact |
| 0x0A | CMD_SYNC_NEXT_MESSAGE | Retrieve queued message |
| 0x0B | CMD_SET_RADIO_PARAMS | Set frequency, BW, SF, CR |
| 0x0C | CMD_SET_RADIO_TX_POWER | Set transmit power (dBm) |
| 0x0D | CMD_RESET_PATH | Reset contact path |
| 0x0E | CMD_SET_ADVERT_LATLON | Set node GPS coordinates |
| 0x0F | CMD_REMOVE_CONTACT | Delete contact |
| 0x10 | CMD_SHARE_CONTACT | Share contact via zero-hop |
| 0x11 | CMD_EXPORT_CONTACT | Export contact/self as advert packet |
| 0x12 | CMD_IMPORT_CONTACT | Import contact from packet |
| 0x13 | CMD_REBOOT | Reboot device |
| 0x14 | CMD_GET_BATT_AND_STORAGE | Get battery voltage and storage |
| 0x15 | CMD_SET_TUNING_PARAMS | Set rx_delay_base, airtime_factor |
| 0x16 | CMD_DEVICE_QUERY | Query device info (first command on connect) |
| 0x17 | CMD_EXPORT_PRIVATE_KEY | Export device identity |
| 0x18 | CMD_IMPORT_PRIVATE_KEY | Import device identity |
| 0x19 | CMD_SEND_RAW_DATA | Send raw data packet |
| 0x1A | CMD_SEND_LOGIN | Login to repeater |
| 0x1B | CMD_SEND_STATUS_REQ | Request status from repeater |
| 0x1C | CMD_HAS_CONNECTION | Check if connected to repeater |
| 0x1D | CMD_LOGOUT | Disconnect from repeater |
| 0x1E | CMD_GET_CONTACT_BY_KEY | Get specific contact by public key |
| 0x1F | CMD_GET_CHANNEL | Get channel info by index |
| 0x20 | CMD_SET_CHANNEL | Set channel (name + 16-byte secret) |
| 0x21 | CMD_SIGN_START | Begin signing session |
| 0x22 | CMD_SIGN_DATA | Add data to sign |
| 0x23 | CMD_SIGN_FINISH | Complete signing, get signature |
| 0x24 | CMD_SEND_TRACE_PATH | Send trace route packet |
| 0x25 | CMD_SET_DEVICE_PIN | Set BLE PIN |
| 0x26 | CMD_SET_OTHER_PARAMS | Set misc params (manual_add, telemetry modes) |
| 0x27 | CMD_SEND_TELEMETRY_REQ | Request telemetry from contact |
| 0x28 | CMD_GET_CUSTOM_VARS | Get custom variables |
| 0x29 | CMD_SET_CUSTOM_VAR | Set custom variable |
| 0x2A | CMD_GET_ADVERT_PATH | Get cached advert path |
| 0x2B | CMD_GET_TUNING_PARAMS | Get rx_delay_base, airtime_factor |
| 0x32 | CMD_SEND_BINARY_REQ | Send binary request to contact |
| 0x33 | CMD_FACTORY_RESET | Factory reset device |
| 0x34 | CMD_SEND_PATH_DISCOVERY_REQ | Path discovery request |
| 0x36 | CMD_SET_FLOOD_SCOPE | Set flood scope transport key |
| 0x37 | CMD_SEND_CONTROL_DATA | Send control data |
| 0x38 | CMD_GET_STATS | Get stats (core/radio/packets) |

**Response Codes (Device → Client)**:
| Code | Name | Description |
|------|------|-------------|
| 0x00 | RESP_CODE_OK | Success |
| 0x01 | RESP_CODE_ERR | Error with code |
| 0x02 | RESP_CODE_CONTACTS_START | Start of contact list |
| 0x03 | RESP_CODE_CONTACT | Contact data |
| 0x04 | RESP_CODE_END_OF_CONTACTS | End of contact list |
| 0x05 | RESP_CODE_SELF_INFO | Node info (reply to APP_START) |
| 0x06 | RESP_CODE_SENT | Message sent (with ACK code, timeout) |
| 0x07 | RESP_CODE_CONTACT_MSG_RECV | Contact message (v<3) |
| 0x08 | RESP_CODE_CHANNEL_MSG_RECV | Channel message (v<3) |
| 0x09 | RESP_CODE_CURR_TIME | Current device time |
| 0x0A | RESP_CODE_NO_MORE_MESSAGES | Message queue empty |
| 0x0B | RESP_CODE_EXPORT_CONTACT | Exported contact data |
| 0x0C | RESP_CODE_BATT_AND_STORAGE | Battery and storage info |
| 0x0D | RESP_CODE_DEVICE_INFO | Device info (reply to QUERY) |
| 0x0E | RESP_CODE_PRIVATE_KEY | Private key (if enabled) |
| 0x0F | RESP_CODE_DISABLED | Feature disabled |
| 0x10 | RESP_CODE_CONTACT_MSG_RECV_V3 | Contact message (v>=3) |
| 0x11 | RESP_CODE_CHANNEL_MSG_RECV_V3 | Channel message (v>=3) |
| 0x12 | RESP_CODE_CHANNEL_INFO | Channel info |
| 0x13 | RESP_CODE_SIGN_START | Sign session started |
| 0x14 | RESP_CODE_SIGNATURE | Signature data |
| 0x15 | RESP_CODE_CUSTOM_VARS | Custom variables |
| 0x16 | RESP_CODE_ADVERT_PATH | Advert path data |
| 0x17 | RESP_CODE_TUNING_PARAMS | Tuning parameters |
| 0x18 | RESP_CODE_STATS | Stats response |

**Push Codes (Device → Client, Unsolicited)**:
| Code | Name | Description |
|------|------|-------------|
| 0x80 | PUSH_CODE_ADVERT | New advertisement received |
| 0x81 | PUSH_CODE_PATH_UPDATED | Contact path updated |
| 0x82 | PUSH_CODE_SEND_CONFIRMED | Message ACK received |
| 0x83 | PUSH_CODE_MSG_WAITING | Message queued for retrieval |
| 0x84 | PUSH_CODE_RAW_DATA | Raw data received |
| 0x85 | PUSH_CODE_LOGIN_SUCCESS | Repeater login success |
| 0x86 | PUSH_CODE_LOGIN_FAIL | Repeater login failed |
| 0x87 | PUSH_CODE_STATUS_RESPONSE | Status response from repeater |
| 0x88 | PUSH_CODE_LOG_RX_DATA | Raw RX log data |
| 0x89 | PUSH_CODE_TRACE_DATA | Trace route data |
| 0x8A | PUSH_CODE_NEW_ADVERT | New contact advert (manual add mode) |
| 0x8B | PUSH_CODE_TELEMETRY_RESPONSE | Telemetry response |
| 0x8C | PUSH_CODE_BINARY_RESPONSE | Binary request response |
| 0x8D | PUSH_CODE_PATH_DISCOVERY_RESPONSE | Path discovery response |
| 0x8E | PUSH_CODE_CONTROL_DATA | Control data received |

**Error Codes**:
| Code | Name |
|------|------|
| 0x01 | ERR_CODE_UNSUPPORTED_CMD |
| 0x02 | ERR_CODE_NOT_FOUND |
| 0x03 | ERR_CODE_TABLE_FULL |
| 0x04 | ERR_CODE_BAD_STATE |
| 0x05 | ERR_CODE_FILE_IO_ERROR |
| 0x06 | ERR_CODE_ILLEGAL_ARG |

**BLE Service UUIDs**:
- Nordic UART Service: `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`
- TX Characteristic: `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` (write)
- RX Characteristic: `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` (notify)

**Key Protocol Constants**:
- `PUB_KEY_SIZE` = 32 bytes
- `MAX_PATH_SIZE` = 64 bytes
- `MAX_FRAME_SIZE` = ~250 bytes
- `SIGNATURE_SIZE` = 64 bytes
- `FIRMWARE_VER_CODE` = 8
- `MAX_CONTACTS` = 100
- `MAX_GROUP_CHANNELS` = 8
- `OFFLINE_QUEUE_SIZE` = 16

**Data Structures**:

ContactInfo (156 bytes):
```
pub_key[32]           // 32-byte public key
name[32]              // Node name
type: uint8           // ADV_TYPE_CHAT/REPEATER/ROOM
flags: uint8          // Permission bits
out_path_len: uint8   // Path length (-1 = flood)
out_path[64]          // Routing path
last_advert_timestamp: uint32
gps_lat: float        // Latitude * 1e6
gps_lon: float        // Longitude * 1e6
lastmod: uint32       // Last modification timestamp
sync_since: uint32    // For incremental sync
```

ChannelDetails (68 bytes):
```
name[32]              // Channel name
secret[32]            // Channel secret (only 16 bytes used)
```

NodePrefs:
```
airtime_factor: float
node_name[32]: char
freq: float           // MHz
sf: uint8             // 5-12
cr: uint8             // 5-8
bw: float             // kHz
tx_power_dbm: uint8   // 1-20
manual_add_contacts: uint8
telemetry_mode_base: uint8
telemetry_mode_loc: uint8
telemetry_mode_env: uint8
rx_delay_base: float
ble_pin: uint32
advert_loc_policy: uint8
multi_acks: uint8
buzzer_quiet: uint8
```

## Desired End State

A production-ready iOS application with:
1. Complete MeshCore BLE protocol implementation (100% command coverage)
2. MockBLE device for comprehensive testing without hardware
3. iMessage-style chat interface with delivery status
4. MapKit integration for contact locations
5. Device configuration UI (radio params, repeater settings)
6. Background BLE with state restoration
7. Local notifications for incoming messages
8. SwiftData persistence with per-device isolation
9. >80% test coverage
10. App Store submission readiness

### Key Verification Criteria:
- All 56 commands implemented and tested
- All 24 response codes handled
- All 15 push codes processed
- Mock device passes 100% protocol compliance tests
- Build succeeds with zero warnings in strict concurrency mode
- All UI flows work on iPhone/iPad/macOS Catalyst

## What We're NOT Doing

- Custom encryption (firmware handles this)
- Cloud sync (SwiftData local only)
- Multi-language support (English only for v1)
- Advanced features like trace paths UI (protocol support only)
- Third-party dependencies (100% Apple frameworks)
- watchOS/tvOS support

## Implementation Approach

We will implement in 10 phases, building from foundation to polish. Each phase produces testable, working code. The Mock BLE Device is created early (Phase 1) to enable TDD throughout.

**Architecture Overview**:
```
┌────────────────────────────────────────────────────────────┐
│                    SwiftUI Views                           │
│  (auto @MainActor in iOS 26)                               │
└────────────────────────┬───────────────────────────────────┘
                         │
┌────────────────────────▼───────────────────────────────────┐
│              @Observable @MainActor ViewModels             │
│  ChatViewModel, ContactsViewModel, SettingsViewModel       │
└──────────┬─────────────────────────────────────┬───────────┘
           │                                     │
┌──────────▼──────────┐           ┌──────────────▼───────────┐
│   BLEService Actor  │           │  @ModelActor DataStore   │
│  - CoreBluetooth    │           │  - SwiftData persistence │
│  - Protocol encode  │           │  - Per-device isolation  │
│  - Frame handling   │           │  - Background writes     │
└─────────────────────┘           └──────────────────────────┘
           │
┌──────────▼──────────┐
│  MockBLEPeripheral  │ (Test target only)
│  - Simulates device │
│  - Protocol replies │
└─────────────────────┘
```

---

## Phase 1:
Phase 1 is already complete: 2025-12-06-pocketmesh-implementation.md (only look up this file if absolutely necessary, it is very large)

## Phase 2: SwiftData Models & BLE Service

### Overview
Create the persistence layer with SwiftData and build the CoreBluetooth service actor for real device communication.

### Changes Required:

#### 1. SwiftData Models
**File**: `PocketMeshKit/Models/Device.swift`
**File**: `PocketMeshKit/Models/Contact.swift`
**File**: `PocketMeshKit/Models/Message.swift`
**File**: `PocketMeshKit/Models/Channel.swift`

#### 2. BLE Service Actor
**File**: `PocketMeshKit/Services/BLEService.swift`
- Use `@preconcurrency import CoreBluetooth`
- Actor-isolated BLE operations
- Nordic UART Service handling
- Frame-based communication
- State restoration support

#### 3. Data Store Actor
**File**: `PocketMeshKit/Services/DataStore.swift`
- `@ModelActor` for background SwiftData operations
- Per-device database isolation
- Sendable DTO conversions

### Success Criteria:
- [x] SwiftData models compile with strict concurrency
- [x] BLE service discovers and connects to mock peripheral
- [x] DataStore saves and retrieves all model types
- [x] Integration tests pass

---

## Phase 3: Core Messaging Service

### Overview
Implement the messaging layer with send/receive, ACK tracking, retry logic, and delivery status.

### Changes Required:

#### 1. Message Service
**File**: `PocketMeshKit/Services/MessageService.swift`
- Send direct messages with retry logic (3 attempts, exponential backoff)
- Flood mode fallback
- ACK tracking and confirmation handling
- Message queue management

#### 2. Message Polling Service
**File**: `PocketMeshKit/Services/MessagePollingService.swift`
- Handle PUSH_CODE_MSG_WAITING
- Sync message queue from device
- Parse message frames

### Success Criteria:
- [x] Messages send with proper retry logic
- [x] ACK confirmations update message status
- [x] Flood fallback works when direct fails
- [x] Incoming messages parsed correctly

---

## Phase 4: Contact & Advertisement Service

### Overview
Implement contact management with discovery, sync, and location sharing.

### Changes Required:

#### 1. Advertisement Service
**File**: `PocketMeshKit/Services/AdvertisementService.swift`
- Send self advertisement (zero-hop/flood)
- Process incoming adverts
- Handle PUSH_CODE_ADVERT and PUSH_CODE_NEW_ADVERT

#### 2. Contact Service
**File**: `PocketMeshKit/Services/ContactService.swift`
- Contact sync with timestamp watermarking
- Add/update/remove contacts
- Path management

### Success Criteria:
- [x] Advertisements send correctly
- [x] Contact discovery works in auto and manual modes
- [x] Incremental sync reduces data transfer
- [x] Path updates tracked

---

## Phase 5: Channel Support

### Overview
Implement channel (group) messaging with SHA-256 secret hashing.

### Changes Required:

#### 1. Channel Service
**File**: `PocketMeshKit/Services/ChannelService.swift`
- Channel CRUD (slots 0-7)
- Secret hashing with CryptoKit SHA-256
- Broadcast messaging

### Success Criteria:
- [x] Channels create/read/update/delete correctly
- [x] Public channel (slot 0) pre-configured
- [x] Channel messages broadcast without ACK
- [x] Secret hashing matches firmware

---

## Phase 6: UI - Onboarding & Settings

### Overview
Build the onboarding flow and settings screens.

### Changes Required:

#### 1. Views
**Files**:
- `PocketMesh/Views/Onboarding/WelcomeView.swift`
- `PocketMesh/Views/Onboarding/PermissionsView.swift`
- `PocketMesh/Views/Onboarding/DeviceScanView.swift`
- `PocketMesh/Views/Onboarding/DevicePairView.swift`
- `PocketMesh/Views/Settings/SettingsView.swift`
- `PocketMesh/Views/Settings/RadioConfigView.swift`
- `PocketMesh/Views/Settings/DeviceInfoView.swift`

### Success Criteria:
- [x] Onboarding flow guides through permissions
- [x] Device scanning shows available devices
- [x] PIN entry and pairing works
- [x] Settings screens update device config

---

## Phase 7: UI - Messaging & Contacts

### Overview
Build the iMessage-style chat interface and contact list.

### Changes Required:

#### 1. Views
**Files**:
- `PocketMesh/Views/Chats/ChatsListView.swift`
- `PocketMesh/Views/Chats/ChatView.swift`
- `PocketMesh/Views/Chats/MessageBubbleView.swift`
- `PocketMesh/Views/Contacts/ContactsListView.swift`
- `PocketMesh/Views/Contacts/ContactDetailView.swift`

### Success Criteria:
- [x] Chat list shows conversations
- [x] Messages display with proper styling
- [x] Delivery status updates in real-time
- [ ] Reply UI works with quoted text
- [x] Contacts searchable and editable

---

## Phase 8: Map Integration

### Overview
Add MapKit integration for contact locations.

### Changes Required:

#### 1. Views
**Files**:
- `PocketMesh/Views/Map/MapView.swift`
- `PocketMesh/Views/Map/ContactAnnotationView.swift`

### Success Criteria:
- [ ] Map shows contacts with location
- [ ] Different markers for contact types
- [ ] 30-second cache refresh
- [ ] Auto-centering works

---

## Phase 9: Notifications & Background BLE

### Overview
Implement local notifications and background BLE support.

### Changes Required:

#### 1. Notification Service
**File**: `PocketMeshKit/Services/NotificationService.swift`
- Local notifications for messages
- Quick reply actions
- Low battery warnings

#### 2. Background BLE
**File**: `PocketMeshKit/Services/BLEStateRestoration.swift`
- State preservation/restoration
- Background connection management

### Success Criteria:
- [ ] Notifications appear for new messages
- [ ] Quick reply sends message
- [ ] BLE reconnects after app termination
- [ ] Background modes work correctly

---

## Phase 10: Testing & Refinement

### Overview
Complete test coverage, performance optimization, and App Store preparation.

### Changes Required:

#### 1. Comprehensive Tests
- Protocol compliance tests (100% command coverage)
- Integration tests for all flows
- Performance tests for large datasets
- Edge case tests

#### 2. Optimization
- SwiftData query optimization
- UI performance tuning
- Memory management review

#### 3. App Store Prep
- Icons and launch screen
- Privacy manifest
- Entitlements verification

### Success Criteria:
- [ ] >80% code coverage
- [ ] All protocol commands tested
- [ ] Performance acceptable with 10k+ messages
- [ ] App Store submission ready

---

## Testing Strategy

### Unit Tests (PocketMeshTests/Protocol/, PocketMeshTests/Services/)
- Frame encoding/decoding accuracy
- Channel secret hashing
- Coordinate encoding
- Retry logic timing
- Error handling paths

### Integration Tests (PocketMeshTests/Integration/)
- Full connection flow with mock
- Message send/receive cycle
- Contact sync with filtering
- Channel operations
- State restoration

### Performance Tests (PocketMeshTests/Performance/)
- 10k message query performance (<100ms)
- Contact sync speed
- Frame encoding throughput
- UI scroll performance

### Hardware Testing Checklist
- [ ] Connect to physical MeshCore device
- [ ] Send/receive messages over mesh
- [ ] Multi-hop path discovery
- [ ] Degraded signal handling
- [ ] Battery drain measurement
- [ ] Background reconnection

## Migration Notes

Not applicable - greenfield implementation.

## References

- PRD: `PRD.md`
- MeshCore Protocol: `MeshCore-firmware-example/MyMesh.cpp:1-119` (command codes)
- MeshCore Protocol: `MeshCore-firmware-example/MyMesh.cpp:140-161` (contact frame format)
- MeshCore Protocol: `MeshCore-firmware-example/MyMesh.h:79-86` (AdvertPath structure)
- MeshCore Protocol: `MeshCore-firmware-example/NodePrefs.h:11-28` (NodePrefs structure)
- MeshCore Protocol: `MeshCore-firmware-example/DataStore.cpp:262-320` (contact persistence format)
