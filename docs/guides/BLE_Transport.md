# BLE Transport Guide

This guide covers the BLE transport architecture, connection state machine, and auto-reconnection behavior.

## Overview

PocketMesh uses CoreBluetooth to communicate with MeshCore devices over Bluetooth Low Energy. The transport layer is abstracted behind the `MeshTransport` protocol, with `iOSBLETransport` + `BLEStateMachine` providing the production implementation.

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
│              (MeshTransport conformance)            │
│                                                     │
│  • Exposes receivedData: AsyncStream<Data>          │
│  • connect() / disconnect() / send()                │
│  • setReconnectionHandler() for auto-reconnect      │
└─────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────┐
│                    BLEStateMachine                  │
│               (CoreBluetooth wrapper)               │
│                                                     │
│  • Manages CBCentralManager                         │
│  • Handles all delegate callbacks                   │
│  • State machine with explicit phases               │
│  • Write serialization                              │
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
public protocol MeshTransport: Actor, Sendable {
    var receivedData: AsyncStream<Data> { get async }
    func connect() async throws
    func disconnect() async
    func send(_ data: Data) async throws
}
```

All transports are actors for thread-safe state management.

## Connection State Machine

**File:** `PocketMeshServices/Sources/PocketMeshServices/Transport/BLEPhase.swift`

The `BLEStateMachine` uses explicit phases that own their resources:

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

// Inject test data
await mock.injectData(testPacket)

// Verify sent data
let sentData = await mock.sentData
#expect(sentData.count == 1)
```

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

### Service Discovery Failure

If Nordic UART Service is not found:
1. Disconnects the peripheral
2. Transitions to `idle`
3. Throws `BLEError.serviceNotFound`

### Characteristic Not Found

If TX or RX characteristics are missing:
1. Disconnects the peripheral
2. Transitions to `idle`
3. Throws `BLEError.characteristicNotFound`

## See Also

- [MeshCore API Reference](../api/MeshCore.md)
- [Architecture Overview](../Architecture.md)
