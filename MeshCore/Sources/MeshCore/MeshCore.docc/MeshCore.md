# ``MeshCore``

A Swift library for communicating with MeshCore mesh networking devices.

## Overview

MeshCore provides a modern Swift API for interacting with MeshCore devices over Bluetooth Low Energy. It handles protocol encoding/decoding, session management, contact discovery, and event streaming.

MeshCore devices form a peer-to-peer mesh network using LoRa radio, enabling off-grid communication. This library provides the BLE interface for controlling these devices from iOS and macOS applications.

### Features

- **Modern Swift Concurrency**: Built with async/await and actors for safe, ergonomic code
- **Event Streaming**: Subscribe to device events using AsyncStream
- **Contact Management**: Discover, store, and message contacts in the mesh
- **Telemetry**: Request sensor data using Cayenne LPP format
- **Full Protocol Support**: Access to all MeshCore device commands

### Quick Start

```swift
import MeshCore

// Create a transport and session
let transport = BLETransport(peripheral: peripheral)
let session = MeshCoreSession(transport: transport)

// Connect and start
try await session.start()

// Get contacts and send a message
let contacts = try await session.getContacts()
if let contact = contacts.first {
    try await session.sendMessage(to: contact.publicKey, text: "Hello!")
}

// Subscribe to events
Task {
    for await event in await session.events() {
        switch event {
        case .contactMessageReceived(let message):
            print("Message: \(message.text)")
        default:
            break
        }
    }
}
```

## Topics

### Essentials

- ``MeshCoreSession``
- ``MeshTransport``
- ``SessionConfiguration``

### Events

- ``MeshEvent``
- ``EventDispatcher``
- ``ConnectionState``

### Models

- ``MeshContact``
- ``SelfInfo``
- ``DeviceCapabilities``

### Messages

- ``ContactMessage``
- ``ChannelMessage``
- ``MessageSentInfo``
- ``MessageResult``

### Protocol

- ``PacketBuilder``
- ``PacketParser``
- ``ResponseCode``
- ``CommandCode``

### Telemetry

- ``LPPDecoder``
- ``LPPSensorType``
- ``LPPDataPoint``
- ``LPPValue``
- ``TelemetryResponse``

### Statistics

- ``StatusResponse``
- ``CoreStats``
- ``RadioStats``
- ``PacketStats``

### Network

- ``TraceInfo``
- ``PathInfo``
- ``NeighboursResponse``

### Errors

- ``MeshCoreError``
- ``MeshTransportError``
