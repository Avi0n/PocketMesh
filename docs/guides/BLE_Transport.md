# BLE Transport Guide

This guide covers the BLE transport architecture, connection state machine, and auto-reconnection behavior.

## Overview

PocketMesh uses CoreBluetooth to communicate with MeshCore devices over Bluetooth Low Energy. The transport layer is abstracted behind the `MeshTransport` protocol, with `iOSBLETransport` (actor) + `BLEStateMachine` (actor) providing the production implementation.

**Important:** Both `iOSBLETransport` and `BLEStateMachine` are Swift actors, not classes. This means all property access and method calls require `await`, providing automatic thread-safety and isolation guarantees under Swift's concurrency model.

**Note:** MeshCore contains a separate, simpler `BLETransport` implementation that uses a delegate-based pattern. This is distinct from the more complex `iOSBLETransport + BLEStateMachine` implementation in PocketMeshServices, which provides full state machine management, auto-reconnection, and production features.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                     MeshCoreSession                 │
│                  (uses MeshTransport)               │
└─────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────┐
│                   iOSBLETransport                   │
│              (actor: MeshTransport)                 │
│                                                     │
│  • Exposes receivedData: AsyncStream<Data>          │
│  • connect() / disconnect() / send()                │
│  • setReconnectionHandler() for auto-reconnect      │
│  • All access requires await                        │
└─────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────┐
│                    BLEStateMachine                  │
│          (actor: CoreBluetooth wrapper)             │
│                                                     │
│  • Manages CBCentralManager                         │
│  • Handles all delegate callbacks                   │
│  • State machine with explicit phases               │
│  • Write serialization                              │
│  • All access requires await                        │
└─────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────┐
│                    CoreBluetooth                    │
│                                                     │
│  • CBCentralManager                                 │
│  • CBPeripheral                                     │
│  • Nordic UART Service (NUS)                        │
└─────────────────────────────────────────────────────┘
```

## MeshTransport Protocol

**File:** `MeshCore/Sources/MeshCore/Transport/MeshTransport.swift`

```swift
public protocol MeshTransport: Sendable {
    var receivedData: AsyncStream<Data> { get async }
    var isConnected: Bool { get async }
    func connect() async throws
    func disconnect() async
    func send(_ data: Data) async throws
}
```

All transports conform to the `MeshTransport` protocol, which requires `Sendable` conformance. While not strictly required to be actors, implementations typically use actors (like `iOSBLETransport`) to provide thread-safety and isolation for transport state.

## Nordic UART Service (NUS)

PocketMesh uses the Nordic UART Service for BLE communication with the following standard UUIDs:

- **Service UUID:** `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`
- **TX Characteristic UUID:** `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` (write to device)
- **RX Characteristic UUID:** `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` (receive from device)

The TX characteristic is used to send data to the device, and the RX characteristic is used to receive notifications from the device.

## Connection State Machine

**File:** `PocketMeshServices/Sources/PocketMeshServices/Transport/BLEPhase.swift`

The `BLEStateMachine` actor uses explicit phases that own their resources:

```swift
public enum BLEPhase {
    case idle
    case waitingForBluetooth(continuation: CheckedContinuation<Void, Error>)
    case connecting(peripheral, continuation, timeoutTask)
    case discoveringServices(peripheral, continuation)
    case discoveringCharacteristics(peripheral, service, continuation)
    case subscribingToNotifications(peripheral, tx, rx, continuation)
    case connected(peripheral, tx, rx, dataContinuation)
    case autoReconnecting(peripheral, tx?, rx?)
    case disconnecting(peripheral)
}
```

### Connection Flow

```
idle
  │
  ▼ connect() called
waitingForBluetooth ──── Bluetooth powered on ────┐
  │                                                │
  ▼                                                │
connecting ───────── Connection established ──────┤
  │                                                │
  ▼                                                │
discoveringServices ─── Services found ───────────┤
  │                                                │
  ▼                                                │
discoveringCharacteristics ─ TX/RX found ─────────┤
  │                                                │
  ▼                                                │
subscribingToNotifications ─ Subscribed ──────────┤
  │                                                │
  ▼                                                │
connected ◄────────────────────────────────────────┘
```

### Phase Transitions

Each phase transition:
1. Cleans up resources from the previous phase
2. Sets up resources for the new phase
3. Resumes or fails any waiting continuations

## Auto-Reconnection (iOS 17+)

iOS 17 introduced automatic BLE reconnection. When enabled, iOS maintains the connection in the background and automatically reconnects if disconnected.

### Enabling Auto-Reconnect

```swift
let options: [String: Any] = [
    CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
    CBConnectPeripheralOptionNotifyOnNotificationKey: true,
    CBConnectPeripheralOptionEnableAutoReconnect: true  // iOS 17+
]
centralManager.connect(peripheral, options: options)
```

### Auto-Reconnect Flow

```
connected
    │
    ▼ Disconnection detected (isReconnecting: true)
autoReconnecting
    │
    │ iOS reconnects automatically
    │
    ▼ Connection restored
discoveringServices (re-discover)
    │
    ▼
discoveringCharacteristics
    │
    ▼
subscribingToNotifications
    │
    ▼ onReconnection callback
connected
```

### Handling Reconnection

**File:** `PocketMeshServices/Sources/PocketMeshServices/Transport/iOSBLETransport.swift`

```swift
public func setReconnectionHandler(_ handler: @escaping @Sendable (UUID) -> Void) async {
    await stateMachine.setReconnectionHandler { [weak self] deviceID, stream in
        Task {
            // First capture the new data stream
            await self?.setDataStream(stream)
            // Then notify handler (stream is ready)
            handler(deviceID)
        }
    }
}
```

The `ConnectionManager` uses this to re-wire services after reconnection:

```swift
await transport.setReconnectionHandler { [weak self] deviceID in
    Task {
        await self?.handleReconnection(deviceID: deviceID)
    }
}
```

## Bluetooth Power Cycle Handling

When Bluetooth is powered off/on, the state machine handles it gracefully:

1. **Power Off:** Transitions to `idle`, cleans up resources
2. **Power On:** If a device was connected, attempts reconnection

### State Restoration

For background relaunch, state restoration is configured:

```swift
let options: [String: Any] = [
    CBCentralManagerOptionRestoreIdentifierKey: "com.pocketmesh.ble.central",
    CBCentralManagerOptionShowPowerAlertKey: true
]
```

When iOS relaunches the app:
1. `centralManager(_:willRestoreState:)` is called
2. Previously connected peripherals are restored
3. The state machine reconnects or continues from current state

## Write Serialization

BLE writes must be serialized to avoid data corruption. The state machine uses a queue:

```swift
// Wait for any pending write
if pendingWriteContinuation != nil {
    await withCheckedContinuation { waiter in
        writeWaiters.append(waiter)
    }
}

// Perform write with timeout
try await withCheckedThrowingContinuation { continuation in
    pendingWriteContinuation = continuation
    peripheral.writeValue(data, for: tx, type: .withResponse)
}
```

## MockTransport for Testing

**File:** `MeshCore/Sources/MeshCore/Transport/MockTransport.swift`

For unit testing without physical hardware:

```swift
let mock = MockTransport()
let session = MeshCoreSession(transport: mock)
try await session.start()

// Simulate receiving data from device
await mock.simulateReceive(testPacket)

// Verify sent data (sentData is an array [Data])
let sentData = await mock.sentData
#expect(sentData.count == 1)
#expect(!sentData.isEmpty)

// Helper methods
await mock.simulateOK()              // Simulate successful OK response
await mock.simulateOK(value: 42)     // Simulate OK with 32-bit value
await mock.simulateError(code: 0x01) // Simulate error response with code
await mock.clearSentData()           // Clear sent data history
```

The `MockTransport` maintains:
- `sentData: [Data]` - Array of all data packets sent through the transport
- `receivedData: AsyncStream<Data>` - Stream of simulated responses
- `isConnected: Bool` - Connection state

## Connection States in UI

The `ConnectionManager` exposes connection state for UI:

| State | Description | UI Indicator |
|-------|-------------|--------------|
| `.disconnected` | No connection | Red dot |
| `.connecting` | Connection in progress | Yellow dot, spinner |
| `.connected` | BLE connected, services loading | Yellow dot |
| `.ready` | Fully operational | Green dot |

## Troubleshooting

### Connection Timeout

If connection takes too long (default: 10 seconds), the state machine:
1. Cancels the connection attempt
2. Transitions to `idle`
3. Throws `BLEError.connectionTimeout`

### Service Discovery Timeout

If service discovery takes too long (default: 40 seconds to allow for pairing dialog), the state machine:
1. Cancels the discovery attempt
2. Disconnects the peripheral
3. Transitions to `idle`
4. Throws `BLEError.connectionTimeout`

**Note:** The extended 40-second timeout accommodates iOS pairing dialogs, which can take time for user interaction.

### Write Timeout

If a write operation takes too long (default: 5 seconds), the state machine:
1. Cancels the write operation
2. Throws `BLEError.operationTimeout`
3. Connection remains active for retry

### Service Discovery Failure

If Nordic UART Service is not found during discovery:
1. Disconnects the peripheral
2. Transitions to `idle`
3. Throws `BLEError.characteristicNotFound`

**Source:** `BLEStateMachine.swift:630-633`

### Characteristic Not Found

If TX or RX characteristics are missing:
1. Disconnects the peripheral
2. Transitions to `idle`
3. Throws `BLEError.characteristicNotFound`

### Pairing Errors

BLE devices may require pairing for secure communication. The state machine detects pairing failures through CBATTError codes:

**Pairing-related error codes:**
- `5` - insufficientAuthentication (pairing required but not completed)
- `8` - insufficientAuthorization (authorization failed)
- `14` - unlikelyError (peer removed pairing information)
- `15` - insufficientEncryption (encryption failed)

When a pairing failure is detected:
1. The error is wrapped as `BLEError.pairingFailed(reason)`
2. Connection may be closed
3. User should be prompted to pair in iOS Settings

**Source:** `BLEError.swift:77-96`

## Event Handlers

The `BLEStateMachine` actor provides several event handlers for managing connection lifecycle. All handler registration methods require `await` since they access actor-isolated state:

### Disconnection Handler

Called when a device disconnects unexpectedly:

```swift
await stateMachine.setDisconnectionHandler { deviceID, error in
    logger.warning("Device \(deviceID) disconnected: \(error?.localizedDescription ?? "unknown")")
    // Update UI, clean up session
}
```

### Reconnection Handler

Called when iOS successfully auto-reconnects to a device:

```swift
await stateMachine.setReconnectionHandler { deviceID, dataStream in
    logger.info("Device \(deviceID) reconnected")
    // Re-initialize session with new data stream
}
```

### Auto-Reconnecting Handler

Called when device disconnects but iOS is attempting automatic reconnection:

```swift
await stateMachine.setAutoReconnectingHandler { deviceID in
    logger.info("Device \(deviceID) entering auto-reconnect")
    // Show "Connecting..." in UI
    // Note: MeshCore session is invalid at this point
}
```

### Bluetooth State Handlers

Monitor Bluetooth hardware state changes:

```swift
// Called on any state change
await stateMachine.setBluetoothStateChangeHandler { state in
    switch state {
    case .poweredOn:
        logger.info("Bluetooth powered on")
    case .poweredOff:
        logger.warning("Bluetooth powered off")
    case .unauthorized:
        logger.error("Bluetooth unauthorized")
    default:
        break
    }
}

// Called specifically when Bluetooth powers on
await stateMachine.setBluetoothPoweredOnHandler {
    logger.info("Bluetooth ready")
    // Trigger device scan, reconnection attempts, etc.
}
```

**Source:** `BLEStateMachine.swift:122-149`

## Timeouts and Configuration

The `BLEStateMachine` actor uses configurable timeouts:

| Operation | Default | Purpose |
|-----------|---------|---------|
| Connection | 10s | Initial peripheral connection |
| Service Discovery | 40s | Service/characteristic discovery (allows for pairing dialog) |
| Write | 5s | Individual write operations |

These can be customized during initialization:

```swift
let stateMachine = BLEStateMachine(
    connectionTimeout: 15.0,
    serviceDiscoveryTimeout: 60.0,
    writeTimeout: 10.0
)
```

**Source:** `BLEStateMachine.swift:66-78`

## See Also

- [MeshCore API Reference](../api/MeshCore.md)
- [Architecture Overview](../Architecture.md)
