# WiFi Transport Guide

This guide explains PocketMesh's WiFi transport implementation for connecting to MeshCore devices over WiFi networks.

## Overview

PocketMesh supports **dual transport** for MeshCore devices:

- **BLE (Bluetooth Low Energy)**: Default for mobile devices, battery-powered equipment
- **WiFi**: For MeshCore firmware devices with WiFi capability, fixed installations, and repeaters

WiFi transport provides:

- **Longer Range**: ~100-300m vs ~10-50m for BLE
- **Higher Throughput**: ~1KB/sec vs ~250 bytes/sec for BLE
- **Lower Power Draw**: For devices with constant power supply
- **Better for Infrastructure**: Repeaters and fixed installations

---

## WiFi Transport Architecture

### Components

**MeshCore Layer**:
- `WiFiTransport.swift`: Base WiFi transport protocol implementation

**PocketMeshServices Layer**:
- `WiFiTransport.swift`: iOS-specific WiFi transport with Network framework
- `WiFiStateMachine.swift`: WiFi connection state management

### Connection Flow

```
┌─────────────┐    ┌──────────────────┐    ┌──────────────┐
│   iOS App   │───>│ WiFiStateMachine  │───>│ MeshCore     │
│              │    │                  │    │ Device       │
└─────────────┘    └──────────────────┘    └──────────────┘
                           │
                           ▼
                     ┌──────────────────┐
                     │  Network Layer  │
                     │   (TCP/UDP)    │
                     └──────────────────┘
```

### WiFi vs BLE Transport

| Aspect | BLE | WiFi |
|---------|------|-------|
| **Range** | Short (~10-50m) | Long (~100-300m) |
| **Throughput** | Lower (~250 bytes/sec) | Higher (~1KB/sec) |
| **Power Consumption** | Low | Medium (but device has constant power) |
| **Setup** | AccessorySetupKit (iOS 18+) | Manual hotspot connection |
| **Pairing** | Automatic via AccessorySetupKit | Manual: Connect to device WiFi hotspot |
| **Use Case** | Mobile devices, battery-powered | Fixed installations, repeaters |
| **Device Discovery** | Automatic scan | Manual IP entry or mDNS discovery |
| **Latency** | Lower (~50-100ms) | Higher (~100-200ms) |

---

## Device Detection

### Device Type Detection

PocketMesh automatically detects device transport capability:

1. **During Onboarding**: User selects device from discovery list
2. **Device Information**: Device advertises transport capability (BLE or WiFi)
3. **Connection Manager**: Routes to appropriate transport:
   - BLE device → `iOSBLETransport`
   - WiFi device → `WiFiTransport`

### MeshCore WiFi Devices

MeshCore devices with WiFi support include:

- **Repeaters**: Often WiFi-only for network backbone
- **Room Servers**: Typically WiFi for higher bandwidth
- **Fixed Nodes**: Stations with constant power supply

### Device Identification

WiFi devices are identified by:

- **Device Name**: `MeshCore-XXXXXX` (last 6 digits of serial)
- **Network Name (SSID)**: Device's WiFi hotspot name
- **IP Address**: Local network IP (e.g., `192.168.1.100`)
- **Port**: MeshCore service port (default: 4242)

---

## Connection Process

### Manual WiFi Connection

Unlike BLE's automatic pairing, WiFi requires manual connection:

#### Step 1: Connect to Device Hotspot

1. Open iOS **Settings**
2. Tap **WiFi**
3. Find device's hotspot (named `MeshCore-XXXXXX`)
4. Tap to connect
5. Enter password (device-specific, printed on label or default)

**Default Password**: Typically `12345678` or device serial

#### Step 2: PocketMesh Auto-Detects

1. Open PocketMesh
2. App scans local network for MeshCore devices
3. If device is found, it appears in discovery list
4. Tap device to connect

**Discovery Methods**:
- **mDNS**: Automatic discovery on local network
- **Manual IP**: User can enter device IP directly
- **Saved Devices**: Previously connected devices appear in list

### WiFi State Machine

`WiFiStateMachine` manages connection lifecycle:

**States**:
- **Disconnected**: Not connected to any device
- **Connecting**: Attempting to establish connection
- **Connected**: Successfully connected and authenticated
- **Reconnecting**: Attempting to reconnect after disconnect

**Transitions**:
```
Disconnected ──(connect)──> Connecting ──(success)──> Connected
                   │                              │
                   │                              │
                   └─(failure)──────────────────┘
                                              │
                                              (disconnect)
                                              ▼
                                         Disconnected

Connected ──(disconnect)──> Disconnected ──(auto-reconnect)──> Connecting
```

### Auto-Reconnection

WiFi transport supports automatic reconnection:

- **Trigger**: Disconnection detected
- **Backoff Strategy**: Exponential backoff (1s, 2s, 4s, 8s, max 60s)
- **Max Attempts**: Unlimited (keeps retrying)
- **User Cancel**: User can cancel reconnection attempt
- **Manual Reconnect**: User can tap "Connect" to force reconnection

---

## Communication Protocol

### Transport Layer

WiFi transport uses TCP/IP for reliable communication:

- **Protocol**: TCP over WiFi
- **Port**: 4242 (MeshCore service port)
- **Keep-Alive**: Periodic keep-alive packets to detect connection loss
- **Timeout**: Connection timeout after 10 seconds of inactivity

### Packet Format

WiFi uses the same packet format as BLE:

- **Binary Protocol**: MeshCore Binary Protocol (MBP)
- **Maximum Size**: 256 bytes per packet
- **Framing**: Length-prefixed binary packets
- **Checksum**: CRC16 for packet integrity

### Data Flow

**Sending Data**:
1. User triggers action (send message, request status, etc.)
2. `WiFiTransport` serializes data to MBP packet
3. Packet is sent over TCP socket
4. ACK/NACK response is awaited
5. Result is returned to caller

**Receiving Data**:
1. TCP socket receives data
2. `WiFiTransport` parses packet header and body
3. Packet is dispatched to `MeshCoreSession`
4. Session routes to appropriate handler
5. Result is broadcast as `MeshEvent`

---

## Configuration

### WiFi Settings

Device WiFi configuration is managed through:

**Device Settings**:
- **SSID**: Network name (auto-generated from serial)
- **Password**: WiFi hotspot password
- **Channel**: WiFi channel (auto or 1-13)
- **Security**: WPA2-PSK (default)

**PocketMesh Settings**:
- **Device IP**: Manual IP entry (if mDNS fails)
- **Connection Timeout**: Seconds before connection attempt fails
- **Keep-Alive Interval**: Seconds between keep-alive packets

### Accessing WiFi Settings

1. Go to **Settings** tab
2. Find **WiFi** section
3. Tap to configure:
   - **Device IP**: Enter manual IP (e.g., `192.168.1.100`)
   - **Auto-Discovery**: Enable/disable mDNS discovery
   - **Timeout**: Adjust connection timeout (default: 10s)

---

## Troubleshooting

### Connection Issues

**Symptom**: Cannot connect to device

**Causes**:
- Not connected to device's WiFi hotspot
- Device not on same network
- Wrong IP address
- Device powered off
- Firewall blocking port 4242

**Solutions**:
1. Verify iOS WiFi shows connected to `MeshCore-XXXXXX`
2. Check device is powered on (LED indicators)
3. Try manual IP entry instead of mDNS
4. Disable firewall or open port 4242
5. Restart device and iOS WiFi

**Testing Connection**:
```bash
# Test if device is reachable
ping 192.168.1.100

# Test if MeshCore port is open
nc -zv 192.168.1.100 4242
```

### Intermittent Disconnections

**Symptom**: Device connects then disconnects repeatedly

**Causes**:
- Weak WiFi signal
- WiFi interference
- Power management (device going to sleep)
- Router dropping connection

**Solutions**:
- Move device closer to router
- Change WiFi channel to avoid interference
- Disable device power management
- Check router logs for connection drops
- Increase keep-alive interval in settings

### Slow Throughput

**Symptom**: Messages take long time to send/receive

**Causes**:
- Poor WiFi signal quality
- Network congestion
- Device processing bottleneck
- High packet loss

**Solutions**:
- Check WiFi signal strength (RSSI in device settings)
- Reduce network traffic on same WiFi
- Restart device to clear processing queue
- Check for interference (microwave, other WiFi networks)

### Discovery Issues

**Symptom**: Device doesn't appear in discovery list

**Causes**:
- mDNS disabled in settings
- Device not advertising via mDNS
- Different subnet (VLAN, guest network)
- mDNS blocked by network

**Solutions**:
- Enable mDNS discovery in PocketMesh settings
- Enter device IP manually
- Ensure device and iPhone are on same subnet
- Disable guest network or VLAN
- Check if network blocks mDNS (some corporate networks)

### Advanced Debugging

**Enable Debug Logging**:
1. Go to **Settings** > **Diagnostics**
2. Tap **Export Debug Logs**
3. Include time range covering issue
4. Share with development team

**Log Categories for WiFi**:
- **Connection**: WiFi connection lifecycle
- **Transport**: Packet send/receive errors
- **Protocol**: Packet parsing and framing issues
- **Timeout**: Connection timeout events

---

## Security

### WiFi Security

**Device Security**:
- **WPA2-PSK**: Strong encryption for WiFi hotspot
- **Unique SSID**: Network name includes device serial
- **Default Password**: Change from default on first use
- **MAC Filtering**: Optional MAC address whitelist (device-configured)

**App Security**:
- **Local Network Only**: No internet communication
- **Encrypted Transport**: Binary protocol with checksums
- **Authentication**: Device authentication for sensitive operations

### Best Practices

**Password Management**:
- Change default password on first use
- Use strong, unique passwords (16+ characters)
- Store passwords securely (not written down)
- Rotate passwords periodically (every 3-6 months)

**Network Security**:
- Isolate mesh network from internet (VLAN or separate router)
- Disable UPnP on mesh router
- Use firewall to block external access to port 4242
- Monitor for unauthorized connections

---

## Performance Optimization

### Network Topology

**Optimal WiFi Setup**:

- **Star Topology**: All devices connect to central access point
- **Mesh Topology**: Devices connect to multiple neighbors (redundancy)
- **Repeaters**: Place repeaters to extend range and provide alternate paths

### Signal Quality

**Improve WiFi Signal**:
- **Line of Sight**: Ensure clear path between device and router
- **Antenna Placement**: Use high-gain antennas, mount in optimal location
- **Interference Avoidance**: Choose less congested WiFi channels
- **Distance**: Keep within 100-150m of router for best performance

**Signal Metrics**:
- **RSSI**: Received Signal Strength Indicator (closer to 0 is better)
  - Excellent: > -50 dBm
  - Good: -50 to -70 dBm
  - Fair: -70 to -85 dBm
  - Poor: < -85 dBm
- **SNR**: Signal-to-Noise Ratio (higher is better)
  - Excellent: > 25 dB
  - Good: 15-25 dB
  - Fair: 10-15 dB
  - Poor: < 10 dB

### Throughput Optimization

**Maximize Throughput**:
- **Reduce Packet Overhead**: Batch messages when possible
- **Use WiFi for Bulk**: Prefer WiFi for large data transfers (sync, backups)
- **Minimize Retransmissions**: Ensure good signal quality
- **Buffer Management**: Configure appropriate buffer sizes

---

## Development

### Testing WiFi Transport

**Simulated Testing**:
```swift
// Use MockTransport for unit tests
let mock = MockTransport()
let session = MeshCoreSession(transport: mock)

// Simulate WiFi device responses
await mock.simulateReceive(testPacket)
await mock.simulateWiFiConnect()
```

**Real Device Testing**:
1. Connect iPhone to MeshCore device's WiFi hotspot
2. Build and run PocketMesh on device
3. Test connection and message flow
4. Monitor debug logs for issues

### WiFi Transport API

**Connect**:
```swift
let transport = WiFiTransport(deviceIP: "192.168.1.100", port: 4242)

try await transport.connect()

// Connection state changes are monitored
transport.statePublisher
    .sink { state in
        print("WiFi state: \(state)")
    }
```

**Send Data**:
```swift
let packet = MeshPacket(type: .message, payload: data)

try await transport.send(packet)

// Returns when ACK received or timeout
```

**Receive Data**:
```swift
// Subscribe to received data stream
for await data in transport.receivedData {
    // Parse packet
    let packet = try PacketParser.parse(data)

    // Handle packet
    await session.handlePacket(packet)
}
```

---

## Further Reading

- [Architecture Overview](../Architecture.md)
- [BLE Transport Guide](BLE_Transport.md)
- [Development Guide](../Development.md)
- [User Guide](../User_Guide.md)
