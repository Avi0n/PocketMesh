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

## Phase 1: Project Setup & Mock BLE Device Foundation

### Overview
Create project structure with XcodeGen, establish the BLE transport layer, and build the Mock BLE Device that will enable all future testing.

### Changes Required:

#### 1. XcodeGen Configuration
**File**: `project.yml`
```yaml
name: PocketMesh
options:
  bundleIdPrefix: com.pocketmesh
  deploymentTarget:
    iOS: "18.0"
  xcodeVersion: "26.1"
  generateEmptyDirectories: true

settings:
  base:
    SWIFT_VERSION: "6.1"
    SWIFT_STRICT_CONCURRENCY: complete
    ENABLE_USER_SCRIPT_SANDBOXING: YES
    CODE_SIGN_IDENTITY: "Apple Development"
    DEVELOPMENT_TEAM: ""

targets:
  PocketMesh:
    type: application
    platform: iOS
    sources:
      - path: PocketMesh
        excludes:
          - "**/*.md"
    dependencies:
      - target: PocketMeshKit
    settings:
      base:
        INFOPLIST_FILE: PocketMesh/Info.plist
        PRODUCT_BUNDLE_IDENTIFIER: com.pocketmesh.app
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        UIBackgroundModes:
          - bluetooth-central
        NSBluetoothAlwaysUsageDescription: "PocketMesh uses Bluetooth to connect to MeshCore radios for off-grid messaging."
        NSBluetoothPeripheralUsageDescription: "PocketMesh uses Bluetooth to connect to MeshCore radios."
        NSLocationWhenInUseUsageDescription: "PocketMesh can share your location with contacts on the mesh network."

  PocketMeshKit:
    type: framework
    platform: iOS
    sources:
      - path: PocketMeshKit
    settings:
      base:
        INFOPLIST_FILE: PocketMeshKit/Info.plist
        PRODUCT_BUNDLE_IDENTIFIER: com.pocketmesh.kit

  PocketMeshTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: PocketMeshTests
    dependencies:
      - target: PocketMesh
      - target: PocketMeshKit
    settings:
      base:
        INFOPLIST_FILE: PocketMeshTests/Info.plist
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/PocketMesh.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/PocketMesh"
        BUNDLE_LOADER: "$(TEST_HOST)"

schemes:
  PocketMesh:
    build:
      targets:
        PocketMesh: all
        PocketMeshKit: all
        PocketMeshTests: [test]
    run:
      config: Debug
    test:
      config: Debug
      targets:
        - PocketMeshTests
    profile:
      config: Release
    analyze:
      config: Debug
    archive:
      config: Release
```

#### 2. Directory Structure
```bash
mkdir -p PocketMesh/{Views/{Onboarding,Chats,Contacts,Map,Settings},Resources}
mkdir -p PocketMeshKit/{Models,Services,Protocol,Extensions,Utilities}
mkdir -p PocketMeshTests/{Mock,Protocol,Services,Integration,Performance}
```

#### 3. Protocol Constants
**File**: `PocketMeshKit/Protocol/ProtocolConstants.swift`
```swift
import Foundation

// MARK: - BLE Service UUIDs
public enum BLEServiceUUID {
    public static let nordicUART = "6E400001-B5A3-F393-E0A9-E50E24DCCA9E"
    public static let txCharacteristic = "6E400002-B5A3-F393-E0A9-E50E24DCCA9E"
    public static let rxCharacteristic = "6E400003-B5A3-F393-E0A9-E50E24DCCA9E"
}

// MARK: - Command Codes (Client → Device)
public enum CommandCode: UInt8, Sendable {
    case appStart = 0x01
    case sendTextMessage = 0x02
    case sendChannelTextMessage = 0x03
    case getContacts = 0x04
    case getDeviceTime = 0x05
    case setDeviceTime = 0x06
    case sendSelfAdvert = 0x07
    case setAdvertName = 0x08
    case addUpdateContact = 0x09
    case syncNextMessage = 0x0A
    case setRadioParams = 0x0B
    case setRadioTxPower = 0x0C
    case resetPath = 0x0D
    case setAdvertLatLon = 0x0E
    case removeContact = 0x0F
    case shareContact = 0x10
    case exportContact = 0x11
    case importContact = 0x12
    case reboot = 0x13
    case getBatteryAndStorage = 0x14
    case setTuningParams = 0x15
    case deviceQuery = 0x16
    case exportPrivateKey = 0x17
    case importPrivateKey = 0x18
    case sendRawData = 0x19
    case sendLogin = 0x1A
    case sendStatusRequest = 0x1B
    case hasConnection = 0x1C
    case logout = 0x1D
    case getContactByKey = 0x1E
    case getChannel = 0x1F
    case setChannel = 0x20
    case signStart = 0x21
    case signData = 0x22
    case signFinish = 0x23
    case sendTracePath = 0x24
    case setDevicePin = 0x25
    case setOtherParams = 0x26
    case sendTelemetryRequest = 0x27
    case getCustomVars = 0x28
    case setCustomVar = 0x29
    case getAdvertPath = 0x2A
    case getTuningParams = 0x2B
    case sendBinaryRequest = 0x32
    case factoryReset = 0x33
    case sendPathDiscoveryRequest = 0x34
    case setFloodScope = 0x36
    case sendControlData = 0x37
    case getStats = 0x38
}

// MARK: - Response Codes (Device → Client)
public enum ResponseCode: UInt8, Sendable {
    case ok = 0x00
    case error = 0x01
    case contactsStart = 0x02
    case contact = 0x03
    case endOfContacts = 0x04
    case selfInfo = 0x05
    case sent = 0x06
    case contactMessageReceived = 0x07
    case channelMessageReceived = 0x08
    case currentTime = 0x09
    case noMoreMessages = 0x0A
    case exportContact = 0x0B
    case batteryAndStorage = 0x0C
    case deviceInfo = 0x0D
    case privateKey = 0x0E
    case disabled = 0x0F
    case contactMessageReceivedV3 = 0x10
    case channelMessageReceivedV3 = 0x11
    case channelInfo = 0x12
    case signStart = 0x13
    case signature = 0x14
    case customVars = 0x15
    case advertPath = 0x16
    case tuningParams = 0x17
    case stats = 0x18
}

// MARK: - Push Codes (Device → Client, Unsolicited)
public enum PushCode: UInt8, Sendable {
    case advert = 0x80
    case pathUpdated = 0x81
    case sendConfirmed = 0x82
    case messageWaiting = 0x83
    case rawData = 0x84
    case loginSuccess = 0x85
    case loginFail = 0x86
    case statusResponse = 0x87
    case logRxData = 0x88
    case traceData = 0x89
    case newAdvert = 0x8A
    case telemetryResponse = 0x8B
    case binaryResponse = 0x8C
    case pathDiscoveryResponse = 0x8D
    case controlData = 0x8E
}

// MARK: - Error Codes
public enum ProtocolError: UInt8, Sendable, Error {
    case unsupportedCommand = 0x01
    case notFound = 0x02
    case tableFull = 0x03
    case badState = 0x04
    case fileIOError = 0x05
    case illegalArgument = 0x06
}

// MARK: - Protocol Limits
public enum ProtocolLimits {
    public static let publicKeySize = 32
    public static let maxPathSize = 64
    public static let maxFrameSize = 250
    public static let signatureSize = 64
    public static let maxContacts = 100
    public static let maxChannels = 8
    public static let offlineQueueSize = 16
    public static let maxNameLength = 32
    public static let channelSecretSize = 16
    public static let maxMessageLength = 160
}

// MARK: - Contact Types
public enum ContactType: UInt8, Sendable, Codable {
    case chat = 0x00
    case repeater = 0x01
    case room = 0x02
}

// MARK: - Text Types
public enum TextType: UInt8, Sendable {
    case plain = 0x00
    case cliData = 0x01
    case signedPlain = 0x02
}

// MARK: - Stats Types
public enum StatsType: UInt8, Sendable {
    case core = 0x00
    case radio = 0x01
    case packets = 0x02
}

// MARK: - Telemetry Modes
public enum TelemetryMode: UInt8, Sendable, Codable {
    case deny = 0
    case allowFlags = 1
    case allowAll = 2
}

// MARK: - Advert Location Policy
public enum AdvertLocationPolicy: UInt8, Sendable, Codable {
    case none = 0
    case share = 1
}
```

#### 4. Protocol Frame Types
**File**: `PocketMeshKit/Protocol/ProtocolFrames.swift`
```swift
import Foundation

// MARK: - Sendable Frame Types

public struct DeviceInfo: Sendable, Equatable {
    public let firmwareVersion: UInt8
    public let maxContacts: UInt8
    public let maxChannels: UInt8
    public let blePin: UInt32
    public let buildDate: String
    public let manufacturerName: String
    public let firmwareVersionString: String

    public init(
        firmwareVersion: UInt8,
        maxContacts: UInt8,
        maxChannels: UInt8,
        blePin: UInt32,
        buildDate: String,
        manufacturerName: String,
        firmwareVersionString: String
    ) {
        self.firmwareVersion = firmwareVersion
        self.maxContacts = maxContacts
        self.maxChannels = maxChannels
        self.blePin = blePin
        self.buildDate = buildDate
        self.manufacturerName = manufacturerName
        self.firmwareVersionString = firmwareVersionString
    }
}

public struct SelfInfo: Sendable, Equatable {
    public let nodeType: UInt8
    public let txPower: UInt8
    public let maxTxPower: UInt8
    public let publicKey: Data  // 32 bytes
    public let latitude: Double
    public let longitude: Double
    public let multiAcks: UInt8
    public let advertLocationPolicy: AdvertLocationPolicy
    public let telemetryModes: UInt8
    public let manualAddContacts: UInt8
    public let frequency: UInt32  // kHz
    public let bandwidth: UInt32  // kHz
    public let spreadingFactor: UInt8
    public let codingRate: UInt8
    public let nodeName: String

    public init(
        nodeType: UInt8,
        txPower: UInt8,
        maxTxPower: UInt8,
        publicKey: Data,
        latitude: Double,
        longitude: Double,
        multiAcks: UInt8,
        advertLocationPolicy: AdvertLocationPolicy,
        telemetryModes: UInt8,
        manualAddContacts: UInt8,
        frequency: UInt32,
        bandwidth: UInt32,
        spreadingFactor: UInt8,
        codingRate: UInt8,
        nodeName: String
    ) {
        self.nodeType = nodeType
        self.txPower = txPower
        self.maxTxPower = maxTxPower
        self.publicKey = publicKey
        self.latitude = latitude
        self.longitude = longitude
        self.multiAcks = multiAcks
        self.advertLocationPolicy = advertLocationPolicy
        self.telemetryModes = telemetryModes
        self.manualAddContacts = manualAddContacts
        self.frequency = frequency
        self.bandwidth = bandwidth
        self.spreadingFactor = spreadingFactor
        self.codingRate = codingRate
        self.nodeName = nodeName
    }
}

public struct ContactFrame: Sendable, Equatable {
    public let publicKey: Data  // 32 bytes
    public let type: ContactType
    public let flags: UInt8
    public let outPathLength: Int8
    public let outPath: Data  // up to 64 bytes
    public let name: String
    public let lastAdvertTimestamp: UInt32
    public let latitude: Float
    public let longitude: Float
    public let lastModified: UInt32

    public init(
        publicKey: Data,
        type: ContactType,
        flags: UInt8,
        outPathLength: Int8,
        outPath: Data,
        name: String,
        lastAdvertTimestamp: UInt32,
        latitude: Float,
        longitude: Float,
        lastModified: UInt32
    ) {
        self.publicKey = publicKey
        self.type = type
        self.flags = flags
        self.outPathLength = outPathLength
        self.outPath = outPath
        self.name = name
        self.lastAdvertTimestamp = lastAdvertTimestamp
        self.latitude = latitude
        self.longitude = longitude
        self.lastModified = lastModified
    }
}

public struct MessageFrame: Sendable, Equatable {
    public let senderPublicKeyPrefix: Data  // 6 bytes
    public let pathLength: UInt8
    public let textType: TextType
    public let timestamp: UInt32
    public let text: String
    public let snr: Int8?  // v3+ only, scaled by 4
    public let extraData: Data?  // For signed messages

    public init(
        senderPublicKeyPrefix: Data,
        pathLength: UInt8,
        textType: TextType,
        timestamp: UInt32,
        text: String,
        snr: Int8? = nil,
        extraData: Data? = nil
    ) {
        self.senderPublicKeyPrefix = senderPublicKeyPrefix
        self.pathLength = pathLength
        self.textType = textType
        self.timestamp = timestamp
        self.text = text
        self.snr = snr
        self.extraData = extraData
    }
}

public struct ChannelMessageFrame: Sendable, Equatable {
    public let channelIndex: UInt8
    public let pathLength: UInt8
    public let textType: TextType
    public let timestamp: UInt32
    public let text: String
    public let snr: Int8?  // v3+ only

    public init(
        channelIndex: UInt8,
        pathLength: UInt8,
        textType: TextType,
        timestamp: UInt32,
        text: String,
        snr: Int8? = nil
    ) {
        self.channelIndex = channelIndex
        self.pathLength = pathLength
        self.textType = textType
        self.timestamp = timestamp
        self.text = text
        self.snr = snr
    }
}

public struct SentResponse: Sendable, Equatable {
    public let isFlood: Bool
    public let ackCode: UInt32
    public let estimatedTimeout: UInt32

    public init(isFlood: Bool, ackCode: UInt32, estimatedTimeout: UInt32) {
        self.isFlood = isFlood
        self.ackCode = ackCode
        self.estimatedTimeout = estimatedTimeout
    }
}

public struct BatteryAndStorage: Sendable, Equatable {
    public let batteryMillivolts: UInt16
    public let storageUsedKB: UInt32
    public let storageTotalKB: UInt32

    public init(batteryMillivolts: UInt16, storageUsedKB: UInt32, storageTotalKB: UInt32) {
        self.batteryMillivolts = batteryMillivolts
        self.storageUsedKB = storageUsedKB
        self.storageTotalKB = storageTotalKB
    }
}

public struct ChannelInfo: Sendable, Equatable {
    public let index: UInt8
    public let name: String
    public let secret: Data  // 16 bytes

    public init(index: UInt8, name: String, secret: Data) {
        self.index = index
        self.name = name
        self.secret = secret
    }
}

public struct SendConfirmation: Sendable, Equatable {
    public let ackCode: UInt32
    public let roundTripTime: UInt32

    public init(ackCode: UInt32, roundTripTime: UInt32) {
        self.ackCode = ackCode
        self.roundTripTime = roundTripTime
    }
}

public struct LoginResult: Sendable, Equatable {
    public let success: Bool
    public let isAdmin: Bool
    public let publicKeyPrefix: Data
    public let serverTimestamp: UInt32?
    public let aclPermissions: UInt8?
    public let firmwareLevel: UInt8?

    public init(
        success: Bool,
        isAdmin: Bool,
        publicKeyPrefix: Data,
        serverTimestamp: UInt32? = nil,
        aclPermissions: UInt8? = nil,
        firmwareLevel: UInt8? = nil
    ) {
        self.success = success
        self.isAdmin = isAdmin
        self.publicKeyPrefix = publicKeyPrefix
        self.serverTimestamp = serverTimestamp
        self.aclPermissions = aclPermissions
        self.firmwareLevel = firmwareLevel
    }
}

public struct CoreStats: Sendable, Equatable {
    public let batteryMillivolts: UInt16
    public let uptimeSeconds: UInt32
    public let errorFlags: UInt16
    public let queueLength: UInt8

    public init(batteryMillivolts: UInt16, uptimeSeconds: UInt32, errorFlags: UInt16, queueLength: UInt8) {
        self.batteryMillivolts = batteryMillivolts
        self.uptimeSeconds = uptimeSeconds
        self.errorFlags = errorFlags
        self.queueLength = queueLength
    }
}

public struct RadioStats: Sendable, Equatable {
    public let noiseFloor: Int16
    public let lastRSSI: Int8
    public let lastSNR: Int8  // scaled by 4
    public let txAirSeconds: UInt32
    public let rxAirSeconds: UInt32

    public init(noiseFloor: Int16, lastRSSI: Int8, lastSNR: Int8, txAirSeconds: UInt32, rxAirSeconds: UInt32) {
        self.noiseFloor = noiseFloor
        self.lastRSSI = lastRSSI
        self.lastSNR = lastSNR
        self.txAirSeconds = txAirSeconds
        self.rxAirSeconds = rxAirSeconds
    }
}

public struct PacketStats: Sendable, Equatable {
    public let packetsReceived: UInt32
    public let packetsSent: UInt32
    public let floodSent: UInt32
    public let directSent: UInt32
    public let floodReceived: UInt32
    public let directReceived: UInt32

    public init(
        packetsReceived: UInt32,
        packetsSent: UInt32,
        floodSent: UInt32,
        directSent: UInt32,
        floodReceived: UInt32,
        directReceived: UInt32
    ) {
        self.packetsReceived = packetsReceived
        self.packetsSent = packetsSent
        self.floodSent = floodSent
        self.directSent = directSent
        self.floodReceived = floodReceived
        self.directReceived = directReceived
    }
}
```

#### 5. Frame Encoder/Decoder
**File**: `PocketMeshKit/Protocol/FrameCodec.swift`
```swift
import Foundation

public enum FrameCodec {

    // MARK: - Encoding

    public static func encodeDeviceQuery(protocolVersion: UInt8) -> Data {
        Data([CommandCode.deviceQuery.rawValue, protocolVersion])
    }

    public static func encodeAppStart(appName: String) -> Data {
        var data = Data([CommandCode.appStart.rawValue])
        data.append(Data(repeating: 0, count: 7))  // reserved
        data.append(appName.data(using: .utf8) ?? Data())
        return data
    }

    public static func encodeSendTextMessage(
        textType: TextType,
        attempt: UInt8,
        timestamp: UInt32,
        recipientKeyPrefix: Data,
        text: String
    ) -> Data {
        var data = Data([CommandCode.sendTextMessage.rawValue])
        data.append(textType.rawValue)
        data.append(attempt)
        data.append(contentsOf: withUnsafeBytes(of: timestamp.littleEndian) { Array($0) })
        data.append(recipientKeyPrefix.prefix(6))
        data.append(text.data(using: .utf8) ?? Data())
        return data
    }

    public static func encodeSendChannelMessage(
        textType: TextType,
        channelIndex: UInt8,
        timestamp: UInt32,
        text: String
    ) -> Data {
        var data = Data([CommandCode.sendChannelTextMessage.rawValue])
        data.append(textType.rawValue)
        data.append(channelIndex)
        data.append(contentsOf: withUnsafeBytes(of: timestamp.littleEndian) { Array($0) })
        data.append(text.data(using: .utf8) ?? Data())
        return data
    }

    public static func encodeGetContacts(since: UInt32? = nil) -> Data {
        var data = Data([CommandCode.getContacts.rawValue])
        if let since {
            data.append(contentsOf: withUnsafeBytes(of: since.littleEndian) { Array($0) })
        }
        return data
    }

    public static func encodeSyncNextMessage() -> Data {
        Data([CommandCode.syncNextMessage.rawValue])
    }

    public static func encodeSendSelfAdvert(flood: Bool) -> Data {
        Data([CommandCode.sendSelfAdvert.rawValue, flood ? 1 : 0])
    }

    public static func encodeSetRadioParams(
        frequencyKHz: UInt32,
        bandwidthKHz: UInt32,
        spreadingFactor: UInt8,
        codingRate: UInt8
    ) -> Data {
        var data = Data([CommandCode.setRadioParams.rawValue])
        data.append(contentsOf: withUnsafeBytes(of: frequencyKHz.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bandwidthKHz.littleEndian) { Array($0) })
        data.append(spreadingFactor)
        data.append(codingRate)
        return data
    }

    public static func encodeSetRadioTxPower(_ power: UInt8) -> Data {
        Data([CommandCode.setRadioTxPower.rawValue, power])
    }

    public static func encodeGetBatteryAndStorage() -> Data {
        Data([CommandCode.getBatteryAndStorage.rawValue])
    }

    public static func encodeSetAdvertName(_ name: String) -> Data {
        var data = Data([CommandCode.setAdvertName.rawValue])
        let nameData = name.data(using: .utf8) ?? Data()
        data.append(nameData.prefix(ProtocolLimits.maxNameLength - 1))
        return data
    }

    public static func encodeSetAdvertLatLon(latitude: Int32, longitude: Int32) -> Data {
        var data = Data([CommandCode.setAdvertLatLon.rawValue])
        data.append(contentsOf: withUnsafeBytes(of: latitude.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: longitude.littleEndian) { Array($0) })
        return data
    }

    public static func encodeGetChannel(index: UInt8) -> Data {
        Data([CommandCode.getChannel.rawValue, index])
    }

    public static func encodeSetChannel(index: UInt8, name: String, secret: Data) -> Data {
        var data = Data([CommandCode.setChannel.rawValue, index])
        var nameBytes = (name.data(using: .utf8) ?? Data()).prefix(32)
        nameBytes.append(Data(repeating: 0, count: 32 - nameBytes.count))
        data.append(nameBytes)
        data.append(secret.prefix(16))
        return data
    }

    public static func encodeSetDeviceTime(_ timestamp: UInt32) -> Data {
        var data = Data([CommandCode.setDeviceTime.rawValue])
        data.append(contentsOf: withUnsafeBytes(of: timestamp.littleEndian) { Array($0) })
        return data
    }

    public static func encodeGetDeviceTime() -> Data {
        Data([CommandCode.getDeviceTime.rawValue])
    }

    public static func encodeSendLogin(publicKey: Data, password: String) -> Data {
        var data = Data([CommandCode.sendLogin.rawValue])
        data.append(publicKey.prefix(32))
        data.append(password.data(using: .utf8) ?? Data())
        return data
    }

    public static func encodeReboot() -> Data {
        var data = Data([CommandCode.reboot.rawValue])
        data.append("reboot".data(using: .utf8) ?? Data())
        return data
    }

    // MARK: - Decoding

    public static func decodeDeviceInfo(from data: Data) throws -> DeviceInfo {
        guard data.count >= 80, data[0] == ResponseCode.deviceInfo.rawValue else {
            throw ProtocolError.illegalArgument
        }

        let firmwareVersion = data[1]
        let maxContacts = data[2]
        let maxChannels = data[3]
        let blePin = data.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let buildDate = String(data: data.subdata(in: 8..<20), encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? ""
        let manufacturerName = String(data: data.subdata(in: 20..<60), encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? ""
        let firmwareVersionString = String(data: data.subdata(in: 60..<80), encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? ""

        return DeviceInfo(
            firmwareVersion: firmwareVersion,
            maxContacts: maxContacts,
            maxChannels: maxChannels,
            blePin: blePin,
            buildDate: buildDate,
            manufacturerName: manufacturerName,
            firmwareVersionString: firmwareVersionString
        )
    }

    public static func decodeSelfInfo(from data: Data) throws -> SelfInfo {
        guard data.count >= 56, data[0] == ResponseCode.selfInfo.rawValue else {
            throw ProtocolError.illegalArgument
        }

        let nodeType = data[1]
        let txPower = data[2]
        let maxTxPower = data[3]
        let publicKey = data.subdata(in: 4..<36)

        let latRaw = data.subdata(in: 36..<40).withUnsafeBytes { $0.load(as: Int32.self).littleEndian }
        let lonRaw = data.subdata(in: 40..<44).withUnsafeBytes { $0.load(as: Int32.self).littleEndian }
        let latitude = Double(latRaw) / 1_000_000.0
        let longitude = Double(lonRaw) / 1_000_000.0

        let multiAcks = data[44]
        let advertLocPolicy = AdvertLocationPolicy(rawValue: data[45]) ?? .none
        let telemetryModes = data[46]
        let manualAddContacts = data[47]

        let frequency = data.subdata(in: 48..<52).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let bandwidth = data.subdata(in: 52..<56).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let sf = data[56]
        let cr = data[57]

        let nodeName = String(data: data.suffix(from: 58), encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? ""

        return SelfInfo(
            nodeType: nodeType,
            txPower: txPower,
            maxTxPower: maxTxPower,
            publicKey: publicKey,
            latitude: latitude,
            longitude: longitude,
            multiAcks: multiAcks,
            advertLocationPolicy: advertLocPolicy,
            telemetryModes: telemetryModes,
            manualAddContacts: manualAddContacts,
            frequency: frequency,
            bandwidth: bandwidth,
            spreadingFactor: sf,
            codingRate: cr,
            nodeName: nodeName
        )
    }

    public static func decodeContact(from data: Data) throws -> ContactFrame {
        guard data.count >= 117,
              (data[0] == ResponseCode.contact.rawValue ||
               data[0] == PushCode.newAdvert.rawValue) else {
            throw ProtocolError.illegalArgument
        }

        var offset = 1
        let publicKey = data.subdata(in: offset..<(offset + 32))
        offset += 32

        let type = ContactType(rawValue: data[offset]) ?? .chat
        offset += 1

        let flags = data[offset]
        offset += 1

        let pathLen = Int8(bitPattern: data[offset])
        offset += 1

        let path = data.subdata(in: offset..<(offset + 64))
        offset += 64

        let nameData = data.subdata(in: offset..<(offset + 32))
        let name = String(data: nameData, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? ""
        offset += 32

        let timestamp = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        offset += 4

        let lat = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: Float.self) }
        offset += 4

        let lon = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: Float.self) }
        offset += 4

        let lastMod = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

        return ContactFrame(
            publicKey: publicKey,
            type: type,
            flags: flags,
            outPathLength: pathLen,
            outPath: path,
            name: name,
            lastAdvertTimestamp: timestamp,
            latitude: lat,
            longitude: lon,
            lastModified: lastMod
        )
    }

    public static func decodeSentResponse(from data: Data) throws -> SentResponse {
        guard data.count >= 10, data[0] == ResponseCode.sent.rawValue else {
            throw ProtocolError.illegalArgument
        }

        let isFlood = data[1] == 1
        let ackCode = data.subdata(in: 2..<6).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let timeout = data.subdata(in: 6..<10).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

        return SentResponse(isFlood: isFlood, ackCode: ackCode, estimatedTimeout: timeout)
    }

    public static func decodeBatteryAndStorage(from data: Data) throws -> BatteryAndStorage {
        guard data.count >= 11, data[0] == ResponseCode.batteryAndStorage.rawValue else {
            throw ProtocolError.illegalArgument
        }

        let battery = data.subdata(in: 1..<3).withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
        let used = data.subdata(in: 3..<7).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let total = data.subdata(in: 7..<11).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

        return BatteryAndStorage(batteryMillivolts: battery, storageUsedKB: used, storageTotalKB: total)
    }

    public static func decodeMessageV3(from data: Data) throws -> MessageFrame {
        guard data.count >= 16, data[0] == ResponseCode.contactMessageReceivedV3.rawValue else {
            throw ProtocolError.illegalArgument
        }

        let snr = Int8(bitPattern: data[1])
        // data[2], data[3] reserved

        let senderPrefix = data.subdata(in: 4..<10)
        let pathLen = data[10]
        let txtType = TextType(rawValue: data[11]) ?? .plain
        let timestamp = data.subdata(in: 12..<16).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

        let textData = data.suffix(from: 16)
        let text = String(data: textData, encoding: .utf8) ?? ""

        return MessageFrame(
            senderPublicKeyPrefix: senderPrefix,
            pathLength: pathLen,
            textType: txtType,
            timestamp: timestamp,
            text: text,
            snr: snr
        )
    }

    public static func decodeChannelMessageV3(from data: Data) throws -> ChannelMessageFrame {
        guard data.count >= 12, data[0] == ResponseCode.channelMessageReceivedV3.rawValue else {
            throw ProtocolError.illegalArgument
        }

        let snr = Int8(bitPattern: data[1])
        // data[2], data[3] reserved

        let channelIdx = data[4]
        let pathLen = data[5]
        let txtType = TextType(rawValue: data[6]) ?? .plain
        let timestamp = data.subdata(in: 7..<11).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

        let textData = data.suffix(from: 11)
        let text = String(data: textData, encoding: .utf8) ?? ""

        return ChannelMessageFrame(
            channelIndex: channelIdx,
            pathLength: pathLen,
            textType: txtType,
            timestamp: timestamp,
            text: text,
            snr: snr
        )
    }

    public static func decodeSendConfirmation(from data: Data) throws -> SendConfirmation {
        guard data.count >= 9, data[0] == PushCode.sendConfirmed.rawValue else {
            throw ProtocolError.illegalArgument
        }

        let ackCode = data.subdata(in: 1..<5).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let rtt = data.subdata(in: 5..<9).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

        return SendConfirmation(ackCode: ackCode, roundTripTime: rtt)
    }

    public static func decodeChannelInfo(from data: Data) throws -> ChannelInfo {
        guard data.count >= 50, data[0] == ResponseCode.channelInfo.rawValue else {
            throw ProtocolError.illegalArgument
        }

        let index = data[1]
        let nameData = data.subdata(in: 2..<34)
        let name = String(data: nameData, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? ""
        let secret = data.subdata(in: 34..<50)

        return ChannelInfo(index: index, name: name, secret: secret)
    }
}
```

#### 6. Mock BLE Peripheral
**File**: `PocketMeshTests/Mock/MockBLEPeripheral.swift`
```swift
import Foundation
import Testing
@testable import PocketMeshKit

/// A complete mock of a MeshCore BLE device for testing.
/// Implements the full Companion Radio Protocol to enable testing without hardware.
actor MockBLEPeripheral {

    // MARK: - Device State

    private var isConnected = false
    private var protocolVersion: UInt8 = 0

    // Device identity
    private let publicKey: Data
    private var nodeName: String
    private var latitude: Double = 0.0
    private var longitude: Double = 0.0

    // Radio configuration
    private var frequency: UInt32 = 915_000  // kHz
    private var bandwidth: UInt32 = 250_000  // kHz
    private var spreadingFactor: UInt8 = 10
    private var codingRate: UInt8 = 5
    private var txPower: UInt8 = 20

    // Telemetry modes
    private var telemetryModeBase: UInt8 = 2
    private var telemetryModeLoc: UInt8 = 0
    private var telemetryModeEnv: UInt8 = 0
    private var advertLocationPolicy: UInt8 = 0
    private var manualAddContacts: UInt8 = 0
    private var multiAcks: UInt8 = 0

    // Device info
    private let firmwareVersion: UInt8 = 8
    private let maxContacts: UInt8 = 50
    private let maxChannels: UInt8 = 8
    private var blePin: UInt32 = 123456

    // Contacts
    private var contacts: [Data: ContactFrame] = [:]
    private var contactIterator: Array<ContactFrame>.Iterator?
    private var contactFilterSince: UInt32 = 0

    // Channels
    private var channels: [UInt8: ChannelInfo] = [:]

    // Message queue
    private var messageQueue: [Data] = []

    // Pending ACKs
    private var pendingAcks: [UInt32: ContactFrame] = [:]
    private var nextAckCode: UInt32 = 1000

    // Response handler
    private var responseHandler: ((Data) -> Void)?

    // MARK: - Initialization

    init(publicKey: Data? = nil, nodeName: String = "MockNode") {
        self.publicKey = publicKey ?? Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        self.nodeName = nodeName

        // Pre-configure public channel
        let publicSecret = Data(repeating: 0, count: 16)
        channels[0] = ChannelInfo(index: 0, name: "Public", secret: publicSecret)
    }

    // MARK: - Connection

    func connect() {
        isConnected = true
    }

    func disconnect() {
        isConnected = false
        protocolVersion = 0
        contactIterator = nil
    }

    func setResponseHandler(_ handler: @escaping (Data) -> Void) {
        responseHandler = handler
    }

    // MARK: - Command Processing

    func processCommand(_ data: Data) throws -> Data? {
        guard isConnected, !data.isEmpty else {
            throw ProtocolError.badState
        }

        guard let command = CommandCode(rawValue: data[0]) else {
            return makeErrorFrame(.unsupportedCommand)
        }

        switch command {
        case .deviceQuery:
            return handleDeviceQuery(data)
        case .appStart:
            return handleAppStart(data)
        case .getContacts:
            return handleGetContacts(data)
        case .syncNextMessage:
            return handleSyncNextMessage()
        case .sendTextMessage:
            return handleSendTextMessage(data)
        case .sendChannelTextMessage:
            return handleSendChannelTextMessage(data)
        case .sendSelfAdvert:
            return handleSendSelfAdvert(data)
        case .setAdvertName:
            return handleSetAdvertName(data)
        case .setAdvertLatLon:
            return handleSetAdvertLatLon(data)
        case .setRadioParams:
            return handleSetRadioParams(data)
        case .setRadioTxPower:
            return handleSetRadioTxPower(data)
        case .getBatteryAndStorage:
            return handleGetBatteryAndStorage()
        case .getDeviceTime:
            return handleGetDeviceTime()
        case .setDeviceTime:
            return handleSetDeviceTime(data)
        case .getChannel:
            return handleGetChannel(data)
        case .setChannel:
            return handleSetChannel(data)
        case .addUpdateContact:
            return handleAddUpdateContact(data)
        case .removeContact:
            return handleRemoveContact(data)
        case .getContactByKey:
            return handleGetContactByKey(data)
        case .setOtherParams:
            return handleSetOtherParams(data)
        case .setDevicePin:
            return handleSetDevicePin(data)
        case .reboot:
            return handleReboot(data)
        case .getTuningParams:
            return handleGetTuningParams()
        case .setTuningParams:
            return handleSetTuningParams(data)
        case .getStats:
            return handleGetStats(data)
        default:
            return makeErrorFrame(.unsupportedCommand)
        }
    }

    // MARK: - Command Handlers

    private func handleDeviceQuery(_ data: Data) -> Data {
        guard data.count >= 2 else {
            return makeErrorFrame(.illegalArgument)
        }
        protocolVersion = data[1]

        var response = Data([ResponseCode.deviceInfo.rawValue])
        response.append(firmwareVersion)
        response.append(maxContacts)
        response.append(maxChannels)
        response.append(contentsOf: withUnsafeBytes(of: blePin.littleEndian) { Array($0) })

        // Build date (12 bytes)
        var buildDate = "06 Dec 2025".data(using: .utf8) ?? Data()
        buildDate.append(Data(repeating: 0, count: max(0, 12 - buildDate.count)))
        response.append(buildDate.prefix(12))

        // Manufacturer name (40 bytes)
        var manufacturer = "MockBLE".data(using: .utf8) ?? Data()
        manufacturer.append(Data(repeating: 0, count: max(0, 40 - manufacturer.count)))
        response.append(manufacturer.prefix(40))

        // Firmware version string (20 bytes)
        var fwVersion = "v1.11.0-mock".data(using: .utf8) ?? Data()
        fwVersion.append(Data(repeating: 0, count: max(0, 20 - fwVersion.count)))
        response.append(fwVersion.prefix(20))

        return response
    }

    private func handleAppStart(_ data: Data) -> Data {
        var response = Data([ResponseCode.selfInfo.rawValue])
        response.append(0x00)  // nodeType = CHAT
        response.append(txPower)
        response.append(20)  // maxTxPower
        response.append(publicKey)

        let latInt = Int32(latitude * 1_000_000)
        let lonInt = Int32(longitude * 1_000_000)
        response.append(contentsOf: withUnsafeBytes(of: latInt.littleEndian) { Array($0) })
        response.append(contentsOf: withUnsafeBytes(of: lonInt.littleEndian) { Array($0) })

        response.append(multiAcks)
        response.append(advertLocationPolicy)
        response.append((telemetryModeEnv << 4) | (telemetryModeLoc << 2) | telemetryModeBase)
        response.append(manualAddContacts)

        response.append(contentsOf: withUnsafeBytes(of: frequency.littleEndian) { Array($0) })
        response.append(contentsOf: withUnsafeBytes(of: bandwidth.littleEndian) { Array($0) })
        response.append(spreadingFactor)
        response.append(codingRate)

        response.append(nodeName.data(using: .utf8) ?? Data())

        return response
    }

    private func handleGetContacts(_ data: Data) -> Data {
        if data.count >= 5 {
            contactFilterSince = data.subdata(in: 1..<5).withUnsafeBytes {
                $0.load(as: UInt32.self).littleEndian
            }
        } else {
            contactFilterSince = 0
        }

        let filteredContacts = contacts.values.filter { $0.lastModified > contactFilterSince }
        contactIterator = Array(filteredContacts).makeIterator()

        var response = Data([ResponseCode.contactsStart.rawValue])
        let count = UInt32(contacts.count)
        response.append(contentsOf: withUnsafeBytes(of: count.littleEndian) { Array($0) })

        return response
    }

    /// Call this repeatedly after getContacts to iterate through contacts
    func getNextContact() -> Data? {
        guard var iterator = contactIterator else { return nil }

        if let contact = iterator.next() {
            contactIterator = iterator
            return encodeContactFrame(contact)
        } else {
            contactIterator = nil

            var response = Data([ResponseCode.endOfContacts.rawValue])
            let mostRecent = contacts.values.map { $0.lastModified }.max() ?? 0
            response.append(contentsOf: withUnsafeBytes(of: mostRecent.littleEndian) { Array($0) })
            return response
        }
    }

    private func handleSyncNextMessage() -> Data {
        if let message = messageQueue.first {
            messageQueue.removeFirst()
            return message
        }
        return Data([ResponseCode.noMoreMessages.rawValue])
    }

    private func handleSendTextMessage(_ data: Data) -> Data {
        guard data.count >= 14 else {
            return makeErrorFrame(.illegalArgument)
        }

        let recipientPrefix = data.subdata(in: 7..<13)

        // Find contact by prefix
        let contact = contacts.first { key, _ in
            key.prefix(6) == recipientPrefix
        }

        guard contact != nil else {
            return makeErrorFrame(.notFound)
        }

        let ackCode = nextAckCode
        nextAckCode += 1

        var response = Data([ResponseCode.sent.rawValue])
        response.append(0)  // not flood
        response.append(contentsOf: withUnsafeBytes(of: ackCode.littleEndian) { Array($0) })
        let timeout: UInt32 = 5000
        response.append(contentsOf: withUnsafeBytes(of: timeout.littleEndian) { Array($0) })

        return response
    }

    private func handleSendChannelTextMessage(_ data: Data) -> Data {
        guard data.count >= 7 else {
            return makeErrorFrame(.illegalArgument)
        }

        let channelIdx = data[2]
        guard channels[channelIdx] != nil else {
            return makeErrorFrame(.notFound)
        }

        return Data([ResponseCode.ok.rawValue])
    }

    private func handleSendSelfAdvert(_ data: Data) -> Data {
        // Just acknowledge - in a real device this would send a packet
        return Data([ResponseCode.ok.rawValue])
    }

    private func handleSetAdvertName(_ data: Data) -> Data {
        guard data.count >= 2 else {
            return makeErrorFrame(.illegalArgument)
        }

        let nameData = data.suffix(from: 1)
        if let name = String(data: nameData, encoding: .utf8) {
            nodeName = String(name.prefix(31))
        }

        return Data([ResponseCode.ok.rawValue])
    }

    private func handleSetAdvertLatLon(_ data: Data) -> Data {
        guard data.count >= 9 else {
            return makeErrorFrame(.illegalArgument)
        }

        let latInt = data.subdata(in: 1..<5).withUnsafeBytes { $0.load(as: Int32.self).littleEndian }
        let lonInt = data.subdata(in: 5..<9).withUnsafeBytes { $0.load(as: Int32.self).littleEndian }

        guard latInt >= -90_000_000 && latInt <= 90_000_000 &&
              lonInt >= -180_000_000 && lonInt <= 180_000_000 else {
            return makeErrorFrame(.illegalArgument)
        }

        latitude = Double(latInt) / 1_000_000.0
        longitude = Double(lonInt) / 1_000_000.0

        return Data([ResponseCode.ok.rawValue])
    }

    private func handleSetRadioParams(_ data: Data) -> Data {
        guard data.count >= 11 else {
            return makeErrorFrame(.illegalArgument)
        }

        let freq = data.subdata(in: 1..<5).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let bw = data.subdata(in: 5..<9).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let sf = data[9]
        let cr = data[10]

        guard freq >= 300_000 && freq <= 2_500_000 &&
              bw >= 7_000 && bw <= 500_000 &&
              sf >= 5 && sf <= 12 &&
              cr >= 5 && cr <= 8 else {
            return makeErrorFrame(.illegalArgument)
        }

        frequency = freq
        bandwidth = bw
        spreadingFactor = sf
        codingRate = cr

        return Data([ResponseCode.ok.rawValue])
    }

    private func handleSetRadioTxPower(_ data: Data) -> Data {
        guard data.count >= 2 else {
            return makeErrorFrame(.illegalArgument)
        }

        let power = data[1]
        guard power >= 1 && power <= 20 else {
            return makeErrorFrame(.illegalArgument)
        }

        txPower = power
        return Data([ResponseCode.ok.rawValue])
    }

    private func handleGetBatteryAndStorage() -> Data {
        var response = Data([ResponseCode.batteryAndStorage.rawValue])
        let battery: UInt16 = 4200  // 4.2V
        let used: UInt32 = 128
        let total: UInt32 = 1024

        response.append(contentsOf: withUnsafeBytes(of: battery.littleEndian) { Array($0) })
        response.append(contentsOf: withUnsafeBytes(of: used.littleEndian) { Array($0) })
        response.append(contentsOf: withUnsafeBytes(of: total.littleEndian) { Array($0) })

        return response
    }

    private func handleGetDeviceTime() -> Data {
        var response = Data([ResponseCode.currentTime.rawValue])
        let time = UInt32(Date().timeIntervalSince1970)
        response.append(contentsOf: withUnsafeBytes(of: time.littleEndian) { Array($0) })
        return response
    }

    private func handleSetDeviceTime(_ data: Data) -> Data {
        guard data.count >= 5 else {
            return makeErrorFrame(.illegalArgument)
        }
        // In mock, we just acknowledge
        return Data([ResponseCode.ok.rawValue])
    }

    private func handleGetChannel(_ data: Data) -> Data {
        guard data.count >= 2 else {
            return makeErrorFrame(.illegalArgument)
        }

        let idx = data[1]
        guard let channel = channels[idx] else {
            return makeErrorFrame(.notFound)
        }

        var response = Data([ResponseCode.channelInfo.rawValue])
        response.append(idx)

        var nameData = channel.name.data(using: .utf8) ?? Data()
        nameData.append(Data(repeating: 0, count: max(0, 32 - nameData.count)))
        response.append(nameData.prefix(32))
        response.append(channel.secret.prefix(16))

        return response
    }

    private func handleSetChannel(_ data: Data) -> Data {
        guard data.count >= 50 else {
            return makeErrorFrame(.illegalArgument)
        }

        let idx = data[1]
        guard idx < 8 else {
            return makeErrorFrame(.notFound)
        }

        let nameData = data.subdata(in: 2..<34)
        let name = String(data: nameData, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? ""
        let secret = data.subdata(in: 34..<50)

        channels[idx] = ChannelInfo(index: idx, name: name, secret: secret)

        return Data([ResponseCode.ok.rawValue])
    }

    private func handleAddUpdateContact(_ data: Data) -> Data {
        guard data.count >= 36 else {
            return makeErrorFrame(.illegalArgument)
        }

        do {
            let contact = try FrameCodec.decodeContact(from: Data([ResponseCode.contact.rawValue]) + data.suffix(from: 1))
            contacts[contact.publicKey] = contact
            return Data([ResponseCode.ok.rawValue])
        } catch {
            return makeErrorFrame(.illegalArgument)
        }
    }

    private func handleRemoveContact(_ data: Data) -> Data {
        guard data.count >= 33 else {
            return makeErrorFrame(.illegalArgument)
        }

        let publicKey = data.subdata(in: 1..<33)

        if contacts.removeValue(forKey: publicKey) != nil {
            return Data([ResponseCode.ok.rawValue])
        }

        return makeErrorFrame(.notFound)
    }

    private func handleGetContactByKey(_ data: Data) -> Data {
        guard data.count >= 33 else {
            return makeErrorFrame(.illegalArgument)
        }

        let publicKey = data.subdata(in: 1..<33)

        if let contact = contacts[publicKey] {
            return encodeContactFrame(contact)
        }

        return makeErrorFrame(.notFound)
    }

    private func handleSetOtherParams(_ data: Data) -> Data {
        guard data.count >= 2 else {
            return makeErrorFrame(.illegalArgument)
        }

        manualAddContacts = data[1]

        if data.count >= 3 {
            let modes = data[2]
            telemetryModeBase = modes & 0x03
            telemetryModeLoc = (modes >> 2) & 0x03
            telemetryModeEnv = (modes >> 4) & 0x03
        }

        if data.count >= 4 {
            advertLocationPolicy = data[3]
        }

        if data.count >= 5 {
            multiAcks = data[4]
        }

        return Data([ResponseCode.ok.rawValue])
    }

    private func handleSetDevicePin(_ data: Data) -> Data {
        guard data.count >= 5 else {
            return makeErrorFrame(.illegalArgument)
        }

        let pin = data.subdata(in: 1..<5).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

        guard pin == 0 || (pin >= 100_000 && pin <= 999_999) else {
            return makeErrorFrame(.illegalArgument)
        }

        blePin = pin
        return Data([ResponseCode.ok.rawValue])
    }

    private func handleReboot(_ data: Data) -> Data {
        guard data.count >= 7 else {
            return makeErrorFrame(.illegalArgument)
        }

        let confirmData = data.subdata(in: 1..<7)
        guard String(data: confirmData, encoding: .utf8) == "reboot" else {
            return makeErrorFrame(.illegalArgument)
        }

        // Simulate reboot by resetting state
        disconnect()
        return Data([ResponseCode.ok.rawValue])
    }

    private func handleGetTuningParams() -> Data {
        var response = Data([ResponseCode.tuningParams.rawValue])
        let rxDelay: UInt32 = 0
        let airtime: UInt32 = 1000  // 1.0
        response.append(contentsOf: withUnsafeBytes(of: rxDelay.littleEndian) { Array($0) })
        response.append(contentsOf: withUnsafeBytes(of: airtime.littleEndian) { Array($0) })
        return response
    }

    private func handleSetTuningParams(_ data: Data) -> Data {
        guard data.count >= 9 else {
            return makeErrorFrame(.illegalArgument)
        }
        // Just acknowledge
        return Data([ResponseCode.ok.rawValue])
    }

    private func handleGetStats(_ data: Data) -> Data {
        guard data.count >= 2 else {
            return makeErrorFrame(.illegalArgument)
        }

        let statsType = data[1]

        switch StatsType(rawValue: statsType) {
        case .core:
            var response = Data([ResponseCode.stats.rawValue, StatsType.core.rawValue])
            let battery: UInt16 = 4200
            let uptime: UInt32 = 3600
            let errors: UInt16 = 0
            let queue: UInt8 = UInt8(messageQueue.count)
            response.append(contentsOf: withUnsafeBytes(of: battery.littleEndian) { Array($0) })
            response.append(contentsOf: withUnsafeBytes(of: uptime.littleEndian) { Array($0) })
            response.append(contentsOf: withUnsafeBytes(of: errors.littleEndian) { Array($0) })
            response.append(queue)
            return response

        case .radio:
            var response = Data([ResponseCode.stats.rawValue, StatsType.radio.rawValue])
            let noise: Int16 = -120
            let rssi: Int8 = -60
            let snr: Int8 = 40  // 10.0 * 4
            let txAir: UInt32 = 100
            let rxAir: UInt32 = 200
            response.append(contentsOf: withUnsafeBytes(of: noise.littleEndian) { Array($0) })
            response.append(Int8(bitPattern: UInt8(bitPattern: rssi)))
            response.append(Int8(bitPattern: UInt8(bitPattern: snr)))
            response.append(contentsOf: withUnsafeBytes(of: txAir.littleEndian) { Array($0) })
            response.append(contentsOf: withUnsafeBytes(of: rxAir.littleEndian) { Array($0) })
            return response

        case .packets:
            var response = Data([ResponseCode.stats.rawValue, StatsType.packets.rawValue])
            let recv: UInt32 = 50
            let sent: UInt32 = 30
            let floodSent: UInt32 = 10
            let directSent: UInt32 = 20
            let floodRecv: UInt32 = 25
            let directRecv: UInt32 = 25
            response.append(contentsOf: withUnsafeBytes(of: recv.littleEndian) { Array($0) })
            response.append(contentsOf: withUnsafeBytes(of: sent.littleEndian) { Array($0) })
            response.append(contentsOf: withUnsafeBytes(of: floodSent.littleEndian) { Array($0) })
            response.append(contentsOf: withUnsafeBytes(of: directSent.littleEndian) { Array($0) })
            response.append(contentsOf: withUnsafeBytes(of: floodRecv.littleEndian) { Array($0) })
            response.append(contentsOf: withUnsafeBytes(of: directRecv.littleEndian) { Array($0) })
            return response

        default:
            return makeErrorFrame(.illegalArgument)
        }
    }

    // MARK: - Test Helpers

    func addContact(_ contact: ContactFrame) {
        contacts[contact.publicKey] = contact
    }

    func queueIncomingMessage(_ message: Data) {
        messageQueue.append(message)
    }

    func simulatePush(_ pushCode: PushCode, data: Data) {
        var frame = Data([pushCode.rawValue])
        frame.append(data)
        responseHandler?(frame)
    }

    func simulateMessageReceived(from senderPrefix: Data, text: String, timestamp: UInt32 = 0) {
        let ts = timestamp > 0 ? timestamp : UInt32(Date().timeIntervalSince1970)

        var frame = Data([ResponseCode.contactMessageReceivedV3.rawValue])
        frame.append(40)  // SNR * 4 = 10.0
        frame.append(0)   // reserved
        frame.append(0)   // reserved
        frame.append(senderPrefix.prefix(6))
        frame.append(2)   // path_len
        frame.append(TextType.plain.rawValue)
        frame.append(contentsOf: withUnsafeBytes(of: ts.littleEndian) { Array($0) })
        frame.append(text.data(using: .utf8) ?? Data())

        messageQueue.append(frame)

        // Send push notification
        responseHandler?(Data([PushCode.messageWaiting.rawValue]))
    }

    func simulateSendConfirmed(ackCode: UInt32, roundTrip: UInt32 = 500) {
        var frame = Data([PushCode.sendConfirmed.rawValue])
        frame.append(contentsOf: withUnsafeBytes(of: ackCode.littleEndian) { Array($0) })
        frame.append(contentsOf: withUnsafeBytes(of: roundTrip.littleEndian) { Array($0) })
        responseHandler?(frame)
    }

    // MARK: - Private Helpers

    private func makeErrorFrame(_ error: ProtocolError) -> Data {
        Data([ResponseCode.error.rawValue, error.rawValue])
    }

    private func encodeContactFrame(_ contact: ContactFrame) -> Data {
        var response = Data([ResponseCode.contact.rawValue])
        response.append(contact.publicKey)
        response.append(contact.type.rawValue)
        response.append(contact.flags)
        response.append(UInt8(bitPattern: Int8(contact.outPathLength)))
        response.append(contact.outPath)
        response.append(Data(repeating: 0, count: max(0, 64 - contact.outPath.count)))

        var nameData = contact.name.data(using: .utf8) ?? Data()
        nameData.append(Data(repeating: 0, count: max(0, 32 - nameData.count)))
        response.append(nameData.prefix(32))

        response.append(contentsOf: withUnsafeBytes(of: contact.lastAdvertTimestamp.littleEndian) { Array($0) })
        response.append(contentsOf: withUnsafeBytes(of: contact.latitude) { Array($0) })
        response.append(contentsOf: withUnsafeBytes(of: contact.longitude) { Array($0) })
        response.append(contentsOf: withUnsafeBytes(of: contact.lastModified.littleEndian) { Array($0) })

        return response
    }
}
```

#### 7. Initial Tests
**File**: `PocketMeshTests/Protocol/ProtocolCodecTests.swift`
```swift
import Testing
import Foundation
@testable import PocketMeshKit

@Suite("Protocol Codec Tests")
struct ProtocolCodecTests {

    @Test("Encode device query")
    func encodeDeviceQuery() {
        let data = FrameCodec.encodeDeviceQuery(protocolVersion: 8)
        #expect(data.count == 2)
        #expect(data[0] == CommandCode.deviceQuery.rawValue)
        #expect(data[1] == 8)
    }

    @Test("Encode app start")
    func encodeAppStart() {
        let data = FrameCodec.encodeAppStart(appName: "PocketMesh")
        #expect(data.count == 18)
        #expect(data[0] == CommandCode.appStart.rawValue)
        #expect(String(data: data.suffix(from: 8), encoding: .utf8) == "PocketMesh")
    }

    @Test("Encode send text message")
    func encodeSendTextMessage() {
        let recipientKey = Data(repeating: 0xAB, count: 6)
        let data = FrameCodec.encodeSendTextMessage(
            textType: .plain,
            attempt: 1,
            timestamp: 1234567890,
            recipientKeyPrefix: recipientKey,
            text: "Hello"
        )

        #expect(data[0] == CommandCode.sendTextMessage.rawValue)
        #expect(data[1] == TextType.plain.rawValue)
        #expect(data[2] == 1)  // attempt
    }

    @Test("Encode radio params")
    func encodeRadioParams() {
        let data = FrameCodec.encodeSetRadioParams(
            frequencyKHz: 915000,
            bandwidthKHz: 250000,
            spreadingFactor: 10,
            codingRate: 5
        )

        #expect(data[0] == CommandCode.setRadioParams.rawValue)
        #expect(data.count == 11)
    }

    @Test("Decode battery and storage")
    func decodeBatteryAndStorage() throws {
        var testData = Data([ResponseCode.batteryAndStorage.rawValue])
        let battery: UInt16 = 4200
        let used: UInt32 = 128
        let total: UInt32 = 1024
        testData.append(contentsOf: withUnsafeBytes(of: battery.littleEndian) { Array($0) })
        testData.append(contentsOf: withUnsafeBytes(of: used.littleEndian) { Array($0) })
        testData.append(contentsOf: withUnsafeBytes(of: total.littleEndian) { Array($0) })

        let result = try FrameCodec.decodeBatteryAndStorage(from: testData)
        #expect(result.batteryMillivolts == 4200)
        #expect(result.storageUsedKB == 128)
        #expect(result.storageTotalKB == 1024)
    }
}
```

**File**: `PocketMeshTests/Mock/MockBLEPeripheralTests.swift`
```swift
import Testing
import Foundation
@testable import PocketMeshKit

@Suite("Mock BLE Peripheral Tests")
struct MockBLEPeripheralTests {

    @Test("Device query returns device info")
    func deviceQuery() async throws {
        let mock = MockBLEPeripheral(nodeName: "TestNode")
        await mock.connect()

        let query = FrameCodec.encodeDeviceQuery(protocolVersion: 8)
        let response = try await mock.processCommand(query)

        #expect(response != nil)
        #expect(response![0] == ResponseCode.deviceInfo.rawValue)

        let info = try FrameCodec.decodeDeviceInfo(from: response!)
        #expect(info.firmwareVersion == 8)
        #expect(info.maxChannels == 8)
    }

    @Test("App start returns self info")
    func appStart() async throws {
        let mock = MockBLEPeripheral(nodeName: "TestNode")
        await mock.connect()

        // First need device query
        _ = try await mock.processCommand(FrameCodec.encodeDeviceQuery(protocolVersion: 8))

        let appStart = FrameCodec.encodeAppStart(appName: "PocketMesh")
        let response = try await mock.processCommand(appStart)

        #expect(response != nil)
        #expect(response![0] == ResponseCode.selfInfo.rawValue)

        let selfInfo = try FrameCodec.decodeSelfInfo(from: response!)
        #expect(selfInfo.nodeName == "TestNode")
    }

    @Test("Set radio params validates input")
    func setRadioParamsValidation() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        // Valid params
        let validParams = FrameCodec.encodeSetRadioParams(
            frequencyKHz: 915000,
            bandwidthKHz: 250000,
            spreadingFactor: 10,
            codingRate: 5
        )
        let validResponse = try await mock.processCommand(validParams)
        #expect(validResponse?[0] == ResponseCode.ok.rawValue)

        // Invalid SF
        let invalidParams = FrameCodec.encodeSetRadioParams(
            frequencyKHz: 915000,
            bandwidthKHz: 250000,
            spreadingFactor: 20,  // Invalid!
            codingRate: 5
        )
        let invalidResponse = try await mock.processCommand(invalidParams)
        #expect(invalidResponse?[0] == ResponseCode.error.rawValue)
        #expect(invalidResponse?[1] == ProtocolError.illegalArgument.rawValue)
    }

    @Test("Get and set channel")
    func channelOperations() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        // Get public channel (pre-configured)
        let getPublic = FrameCodec.encodeGetChannel(index: 0)
        let publicResponse = try await mock.processCommand(getPublic)

        #expect(publicResponse?[0] == ResponseCode.channelInfo.rawValue)
        let channelInfo = try FrameCodec.decodeChannelInfo(from: publicResponse!)
        #expect(channelInfo.name == "Public")

        // Set custom channel
        let secret = Data(repeating: 0x42, count: 16)
        let setChannel = FrameCodec.encodeSetChannel(index: 1, name: "Private", secret: secret)
        let setResponse = try await mock.processCommand(setChannel)
        #expect(setResponse?[0] == ResponseCode.ok.rawValue)

        // Verify it was set
        let getPrivate = FrameCodec.encodeGetChannel(index: 1)
        let privateResponse = try await mock.processCommand(getPrivate)
        let privateInfo = try FrameCodec.decodeChannelInfo(from: privateResponse!)
        #expect(privateInfo.name == "Private")
    }

    @Test("Message queue operations")
    func messageQueue() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        // Empty queue
        let syncEmpty = FrameCodec.encodeSyncNextMessage()
        let emptyResponse = try await mock.processCommand(syncEmpty)
        #expect(emptyResponse?[0] == ResponseCode.noMoreMessages.rawValue)

        // Add message to queue
        let senderPrefix = Data(repeating: 0xAB, count: 6)
        await mock.simulateMessageReceived(from: senderPrefix, text: "Hello!")

        // Sync message
        let syncMessage = FrameCodec.encodeSyncNextMessage()
        let messageResponse = try await mock.processCommand(syncMessage)
        #expect(messageResponse?[0] == ResponseCode.contactMessageReceivedV3.rawValue)

        let message = try FrameCodec.decodeMessageV3(from: messageResponse!)
        #expect(message.text == "Hello!")
    }

    @Test("Stats retrieval")
    func statsRetrieval() async throws {
        let mock = MockBLEPeripheral()
        await mock.connect()

        // Core stats
        var statsCmd = Data([CommandCode.getStats.rawValue, StatsType.core.rawValue])
        var response = try await mock.processCommand(statsCmd)
        #expect(response?[0] == ResponseCode.stats.rawValue)
        #expect(response?[1] == StatsType.core.rawValue)

        // Radio stats
        statsCmd = Data([CommandCode.getStats.rawValue, StatsType.radio.rawValue])
        response = try await mock.processCommand(statsCmd)
        #expect(response?[0] == ResponseCode.stats.rawValue)
        #expect(response?[1] == StatsType.radio.rawValue)

        // Packet stats
        statsCmd = Data([CommandCode.getStats.rawValue, StatsType.packets.rawValue])
        response = try await mock.processCommand(statsCmd)
        #expect(response?[0] == ResponseCode.stats.rawValue)
        #expect(response?[1] == StatsType.packets.rawValue)
    }
}
```

### Success Criteria:

#### Automated Verification:
- [x] `xcodegen generate` succeeds without errors
- [x] `xcodebuild -scheme PocketMesh build` succeeds
- [x] `xcodebuild test -scheme PocketMesh -destination 'platform=iOS Simulator,name=iPhone 17'` passes
- [x] All protocol constants match firmware exactly
- [x] Mock BLE peripheral handles all core commands

#### Manual Verification:
- [x] Project opens in Xcode 26 without issues
- [x] Directory structure matches specification
- [x] Code passes strict concurrency checking

**Implementation Note**: After completing this phase and all automated verification passes, pause here for manual confirmation before proceeding to Phase 2.

---

Continued in 2025-12-06-pocketmesh-implementation-part2.md