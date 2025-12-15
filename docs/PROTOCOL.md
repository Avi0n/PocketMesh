# PocketMesh Protocol Reference

This document describes the binary protocol used for communication between PocketMesh and MeshCore BLE devices via Nordic UART Service.

## Transport Layer

### Nordic UART Service (NUS)

| UUID | Name | Direction |
|------|------|-----------|
| `6E400001-B5A3-F393-E0A9-E50E24DCCA9E` | Service | - |
| `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` | TX | App → Device (write) |
| `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` | RX | Device → App (notify) |

### Frame Structure

All frames are binary with a single-byte type code prefix:

```
[TypeCode:1][Payload:0-249]
```

Maximum frame size: 250 bytes

### Byte Order

All multi-byte integers use **little-endian** byte order.

---

## Command Codes (App → Device)

### Device Management

| Code | Name | Payload | Response |
|------|------|---------|----------|
| `0x16` | deviceQuery | `[protocolVersion:1]` | deviceInfo (0x0D) |
| `0x01` | appStart | `[appName:UTF-8]` | selfInfo (0x05) |
| `0x05` | getDeviceTime | - | currentTime (0x09) |
| `0x06` | setDeviceTime | `[timestamp:4]` | ok (0x00) |
| `0x14` | getBatteryAndStorage | - | batteryAndStorage (0x0C) |
| `0x13` | reboot | - | (disconnects) |
| `0x33` | factoryReset | - | ok (0x00) |

### Messaging

| Code | Name | Payload |
|------|------|---------|
| `0x02` | sendTextMessage | `[textType:1][attempt:1][timestamp:4][recipientKeyPrefix:6][text:UTF-8]` |
| `0x03` | sendChannelTextMessage | `[textType:1][channelIndex:1][timestamp:4][text:UTF-8]` |
| `0x0A` | syncNextMessage | - |

**Text Types:**
- `0x00` - plain
- `0x01` - cliData
- `0x02` - signedPlain (for room messages)

### Contact Management

| Code | Name | Payload |
|------|------|---------|
| `0x04` | getContacts | `[since:4]?` (optional timestamp) |
| `0x09` | addUpdateContact | See ContactFrame format |
| `0x0F` | removeContact | `[publicKey:32]` |
| `0x1E` | getContactByKey | `[publicKey:32]` |
| `0x0D` | resetPath | `[publicKey:32]` |
| `0x10` | shareContact | `[publicKey:32]` |
| `0x11` | exportContact | `[publicKey:32]` |
| `0x12` | importContact | See ContactFrame format |

### Radio Configuration

| Code | Name | Payload |
|------|------|---------|
| `0x0B` | setRadioParams | `[frequency:4][bandwidth:4][spreadingFactor:1][codingRate:1]` |
| `0x0C` | setRadioTxPower | `[txPower:1]` |
| `0x07` | sendSelfAdvert | `[flood:1]` (0=zero-hop, 1=flood) |
| `0x08` | setAdvertName | `[name:UTF-8]` (max 31 bytes) |
| `0x0E` | setAdvertLatLon | `[latitude:4][longitude:4]` (microdegrees) |
| `0x15` | setTuningParams | `[params:variable]` |
| `0x2B` | getTuningParams | - |
| `0x26` | setOtherParams | `[telemetryMode:1][locationPolicy:1]` |
| `0x36` | setFloodScope | `[scope:1]` |

### Channel Management

| Code | Name | Payload |
|------|------|---------|
| `0x1F` | getChannel | `[index:1]` |
| `0x20` | setChannel | `[index:1][name:UTF-8][secret:16]` |

### Authentication

| Code | Name | Payload |
|------|------|---------|
| `0x1A` | sendLogin | `[publicKey:32][password:UTF-8]` |
| `0x1C` | hasConnection | `[publicKey:32]` |
| `0x1D` | logout | `[publicKey:32]` |

### Key Management

| Code | Name | Payload |
|------|------|---------|
| `0x17` | exportPrivateKey | - |
| `0x18` | importPrivateKey | `[privateKey:32]` |
| `0x25` | setDevicePin | `[pin:UTF-8]` |

### Message Signing

| Code | Name | Payload |
|------|------|---------|
| `0x21` | signStart | `[messageLen:2]` |
| `0x22` | signData | `[data:variable]` |
| `0x23` | signFinish | - |

### Custom Variables

| Code | Name | Payload |
|------|------|---------|
| `0x28` | getCustomVars | - |
| `0x29` | setCustomVar | `[index:1][value:variable]` |

### Raw Data

| Code | Name | Payload |
|------|------|---------|
| `0x19` | sendRawData | `[publicKey:32][data:variable]` |
| `0x37` | sendControlData | `[controlType:1][data:variable]` |

### Binary Protocol

| Code | Name | Payload |
|------|------|---------|
| `0x32` | sendBinaryRequest | `[publicKey:32][requestType:1][data:variable]` |
| `0x1B` | sendStatusRequest | `[publicKey:32]` |
| `0x27` | sendTelemetryRequest | `[reserved:3][publicKey:32]?` |

**Binary Request Types:**
- `0x01` - status
- `0x02` - keepAlive
- `0x03` - telemetry
- `0x04` - mma (min/max/avg)
- `0x05` - acl
- `0x06` - neighbours

### Path Discovery

| Code | Name | Payload |
|------|------|---------|
| `0x2A` | getAdvertPath | `[reserved:1][publicKey:32]` |
| `0x34` | sendPathDiscoveryRequest | `[reserved:1][publicKey:32]` |

### Diagnostics

| Code | Name | Payload |
|------|------|---------|
| `0x24` | sendTracePath | `[tag:4][authCode:4][flags:1][path:variable]` |
| `0x38` | getStats | - |

---

## Response Codes (Device → App)

### Status Responses

| Code | Name | Description |
|------|------|-------------|
| `0x00` | ok | Success |
| `0x01` | error | Error (see error codes) |
| `0x0F` | disabled | Feature disabled |

### Device Information

| Code | Name | Payload |
|------|------|---------|
| `0x0D` | deviceInfo | `[firmware:1][maxContacts:1][maxChannels:1][blePin:4][buildDate:12][manufacturer:40][firmwareStr:20]` |
| `0x05` | selfInfo | `[nodeType:1][txPower:1][maxTxPower:1][publicKey:32][lat:4][lon:4][flags:4][freq:4][bw:4][sf:1][cr:1][nodeName:variable]` |
| `0x09` | currentTime | `[timestamp:4]` |
| `0x0C` | batteryAndStorage | `[batteryMV:2][usedKB:4][totalKB:4]` |

### Contact Enumeration

| Code | Name | Payload |
|------|------|---------|
| `0x02` | contactsStart | `[count:1]` |
| `0x03` | contact | See ContactFrame format |
| `0x04` | endOfContacts | `[syncTimestamp:4]` |

### Message Responses

| Code | Name | Payload |
|------|------|---------|
| `0x06` | sent | `[isFlood:1][ackCode:4][timeout:4]` |
| `0x07` | contactMessageReceived | Legacy v2 format |
| `0x08` | channelMessageReceived | Legacy v2 format |
| `0x0A` | noMoreMessages | - |
| `0x10` | contactMessageReceivedV3 | `[snr:1][reserved:2][senderPrefix:6][pathLen:1][textType:1][timestamp:4][extraData:4]?[text:variable]` |
| `0x11` | channelMessageReceivedV3 | `[snr:1][reserved:2][channelIndex:1][pathLen:1][textType:1][timestamp:4][text:variable]` |

### Channel

| Code | Name | Payload |
|------|------|---------|
| `0x12` | channelInfo | `[index:1][name:32][secret:16]` |

### Authentication

| Code | Name | Payload |
|------|------|---------|
| `0x19` | hasConnection | `[hasConnection:1]` |

### Contact Export

| Code | Name | Payload |
|------|------|---------|
| `0x0B` | exportContact | See ContactFrame format |

### Key Management

| Code | Name | Payload |
|------|------|---------|
| `0x0E` | privateKey | `[privateKey:32]` |

### Message Signing

| Code | Name | Payload |
|------|------|---------|
| `0x13` | signStart | `[sessionId:1]` |
| `0x14` | signature | `[signature:64]` |

### Custom Variables

| Code | Name | Payload |
|------|------|---------|
| `0x15` | customVars | `[vars:variable]` |

### Path Information

| Code | Name | Payload |
|------|------|---------|
| `0x16` | advertPath | `[timestamp:4][pathLen:1][path:pathLen]` |

### Configuration

| Code | Name | Payload |
|------|------|---------|
| `0x17` | tuningParams | `[params:variable]` |
| `0x18` | stats | `[statsType:1][data:variable]` |

---

## Push Codes (Device → App, Unsolicited)

All push codes have values >= `0x80`.

### Network Events

| Code | Name | Payload |
|------|------|---------|
| `0x80` | advert | `[publicKeyPrefix:6][timestamp:4]` |
| `0x8A` | newAdvert | ContactFrame (147+ bytes) |
| `0x81` | pathUpdated | `[publicKeyPrefix:6][pathLength:1]` |
| `0x83` | messageWaiting | - |
| `0x82` | sendConfirmed | `[ackCode:4][roundTripTime:4]` |
| `0x84` | rawData | `[data:variable]` |
| `0x88` | logRxData | `[data:variable]` |

### Authentication

| Code | Name | Payload |
|------|------|---------|
| `0x85` | loginSuccess | `[isAdmin:1][publicKeyPrefix:6][serverTimestamp:4]?[aclPermissions:1]?[firmwareLevel:1]?` |
| `0x86` | loginFail | `[publicKeyPrefix:6]` |

### Binary Protocol

| Code | Name | Payload |
|------|------|---------|
| `0x87` | statusResponse | See RemoteNodeStatus format |
| `0x8B` | telemetryResponse | `[reserved:1][publicKeyPrefix:6][lppData:variable]` |
| `0x8C` | binaryResponse | `[reserved:1][tag:4][data:variable]` |
| `0x8D` | pathDiscoveryResponse | `[reserved:1][publicKeyPrefix:6][outPathLen:1][outPath:N][inPathLen:1][inPath:M]` |

### Diagnostics

| Code | Name | Payload |
|------|------|---------|
| `0x89` | traceData | `[reserved:1][pathLen:1][flags:1][tag:4][authCode:4][hashBytes:pathLen][snrBytes:pathLen][finalSnr:1]` |
| `0x8E` | controlData | `[snr:1][rssi:1][pathLength:1][payload:variable]` |

---

## Error Codes

| Code | Name | Description |
|------|------|-------------|
| `0x01` | unsupportedCommand | Command not implemented |
| `0x02` | notFound | Resource not found |
| `0x03` | tableFull | Storage limit reached |
| `0x04` | badState | Invalid operation state |
| `0x05` | fileIOError | File system error |
| `0x06` | illegalArgument | Invalid parameter |

---

## Data Structures

### ContactFrame

147 bytes minimum:

```
[publicKey:32][type:1][flags:1][outPathLength:1][outPath:64][name:32][lastAdvertTimestamp:4][latitude:4][longitude:4][lastModified:4]
```

| Field | Bytes | Type | Description |
|-------|-------|------|-------------|
| publicKey | 32 | Data | Ed25519 public key |
| type | 1 | UInt8 | 0x01=chat, 0x02=repeater, 0x03=room |
| flags | 1 | UInt8 | Permission flags |
| outPathLength | 1 | Int8 | -1=flood, 0+=direct routing |
| outPath | 64 | Data | Routing path (repeater hashes) |
| name | 32 | String | Contact name (null-padded) |
| lastAdvertTimestamp | 4 | UInt32 | Last advertisement timestamp |
| latitude | 4 | Int32 | Latitude × 1,000,000 |
| longitude | 4 | Int32 | Longitude × 1,000,000 |
| lastModified | 4 | UInt32 | Last modification timestamp |

### RemoteNodeStatus

52 bytes from binary protocol status request:

| Field | Offset | Type | Description |
|-------|--------|------|-------------|
| batteryMillivolts | 0 | UInt16 | Battery voltage |
| txQueueLength | 2 | UInt16 | TX queue length |
| noiseFloor | 4 | Int16 | Noise floor dBm |
| lastRSSI | 6 | Int16 | Last RSSI dBm |
| packetsReceived | 8 | UInt32 | Total packets received |
| packetsSent | 12 | UInt32 | Total packets sent |
| txAirtimeSeconds | 16 | UInt32 | TX airtime |
| uptimeSeconds | 20 | UInt32 | Uptime |
| floodSent | 24 | UInt32 | Flood packets sent |
| directSent | 28 | UInt32 | Direct packets sent |
| floodReceived | 32 | UInt32 | Flood packets received |
| directReceived | 36 | UInt32 | Direct packets received |
| fullEvents | 40 | UInt16 | Queue full events |
| lastSNR | 42 | Int16 | Last SNR × 4 |
| directDuplicates | 44 | UInt16 | Direct duplicate count |
| floodDuplicates | 46 | UInt16 | Flood duplicate count |
| rxAirtimeSeconds | 48 | UInt32 | RX airtime |

### NeighboursResponse

Variable length:

```
[totalCount:2][resultsCount:2][entries:variable]
```

Each entry:
```
[publicKeyPrefix:N][secondsAgo:4][snr:1]
```

N is specified in request (4-32 bytes, default 6).

---

## Encoding Conventions

### Coordinates

Stored as signed 32-bit integers representing **microdegrees** (degrees × 1,000,000):

```swift
// Encode
let latInt = Int32(latitude * 1_000_000)

// Decode
let latitude = Double(latRaw) / 1_000_000.0
```

### SNR (Signal-to-Noise Ratio)

Stored as signed 8-bit or 16-bit integers representing **quarter-dB** (SNR × 4):

```swift
// Decode
let snr = Float(snrRaw) / 4.0
```

Range: -32 to +31.75 dB with 0.25 dB resolution.

### Strings

- UTF-8 encoded
- Either null-terminated or fixed-width (padded with nulls)
- Decoded with null-trimming: `trimmingCharacters(in: .controlCharacters)`

### Public Keys

- Full key: 32 bytes (Ed25519)
- Prefix: 6 bytes (for addressing in messages)
- Used for contact lookup: `fetchContact(byPrefix:deviceID:)`

### Channel Secrets

- 16 bytes
- Derived from passphrase via SHA-256, taking first 16 bytes
- All zeros for public channel (slot 0)

---

## Protocol Flows

### Device Initialization

```
App                                     Device
 |                                        |
 |--[0x16 deviceQuery]------------------→ |
 |                                        |
 |←--[0x0D deviceInfo]-------------------|
 |                                        |
 |--[0x01 appStart "PocketMesh"]--------→ |
 |                                        |
 |←--[0x05 selfInfo]---------------------|
 |                                        |
```

### Contact Sync

```
App                                     Device
 |                                        |
 |--[0x04 getContacts since=0]----------→ |
 |                                        |
 |←--[0x02 contactsStart count=5]--------|
 |                                        |
 |--[empty]-----------------------------→ |
 |←--[0x03 contact #1]-------------------|
 |                                        |
 |--[empty]-----------------------------→ |
 |←--[0x03 contact #2]-------------------|
 |                                        |
 |  ... (repeat for all contacts)         |
 |                                        |
 |--[empty]-----------------------------→ |
 |←--[0x04 endOfContacts timestamp=123]--|
 |                                        |
```

### Message Send with ACK

```
App                                     Device                                   Recipient
 |                                        |                                        |
 |--[0x02 sendTextMessage]---------------→|                                        |
 |                                        |------[mesh transmission]-------------→ |
 |←--[0x06 sent ackCode=1001 timeout=30]-|                                        |
 |                                        |                                        |
 |   (app tracks pending ACK)             |                                        |
 |                                        |                                        |
 |                                        |←-----[mesh ACK]------------------------|
 |←--[0x82 sendConfirmed ack=1001 rtt=250]|                                        |
 |                                        |                                        |
```

### Room Server Authentication

```
App                                     Device                                   Room Server
 |                                        |                                        |
 |--[0x1A sendLogin pubkey pwd]----------→|                                        |
 |                                        |------[login request]----------------→ |
 |←--[0x06 sent]--------------------------|                                        |
 |                                        |                                        |
 |                                        |←-----[login response]-----------------|
 |←--[0x85 loginSuccess admin=1]---------|                                        |
 |                                        |                                        |
```

---

## Implementation Notes

### BLE Write Chunking

Data exceeding MTU (typically 185-512 bytes) is chunked:

```swift
let mtu = peripheral.maximumWriteValueLength(for: .withResponse)
let chunks = stride(from: 0, to: data.count, by: mtu).map {
    data.subdata(in: $0..<min($0 + mtu, data.count))
}
```

### Response Timeout

- Normal operations: 5 seconds
- Pairing window: 40 seconds
- Remote node login: 5s base + 10s per hop (max 60s)

### Message Retry Logic

```
Attempt 1: Direct routing, 200ms delay
Attempt 2: Direct routing, 400ms delay
Attempt 3+: Flood routing, exponential backoff
```

ACK timeout uses device-reported timeout × 1.2 buffer.
