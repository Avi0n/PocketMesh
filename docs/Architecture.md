# PocketMesh Architecture

PocketMesh is built using a modern, three-tier modular architecture designed for high performance, reliability, and maintainability. It leverages Swift 6's strict concurrency model, actor isolation, and modern iOS frameworks.

## Platform Requirements

- **Minimum Deployment:** iOS 18.0
- **Feature Target:** iOS 26.0 (uses `#available` checks for newer APIs)
- **Swift:** 6.2+
- **Xcode:** 26.0+

## High-Level Architecture

The project is divided into three main layers:

1. **MeshCore (Protocol Layer)**: A pure Swift implementation of the MeshCore mesh networking protocol.
2. **PocketMeshServices (Business Logic Layer)**: Manages higher-level business logic, actor isolation, and shared persistence.
3. **PocketMesh (UI Layer)**: The SwiftUI-based user interface and application state management.

```mermaid
graph TD
    subgraph PocketMesh [UI Layer]
        AppState[AppState @Observable @MainActor]
        Views[SwiftUI Views]
        MEB[MessageEventBroadcaster]
    end

    subgraph PocketMeshServices [Business Logic Layer]
        ServiceContainer[ServiceContainer DI]
        CM[ConnectionManager @MainActor @Observable]
        SC[SyncCoordinator actor]

        subgraph CoreServices [Core Services]
            MS[MessageService actor]
            CS[ContactService actor]
            CH[ChannelService actor]
            SS[SettingsService actor]
            AS[AdvertisementService actor]
            MPS[MessagePollingService actor]
            BPS[BinaryProtocolService actor]
            DS[DeviceService actor]
            HRS[HeardRepeatsService actor]
        end

        subgraph RemoteServices [Remote Node Services]
            RNS[RemoteNodeService actor]
            RAS[RepeaterAdminService actor]
            RSS[RoomServerService actor]
        end

        subgraph IndependentServices [Independent Services]
            KS[KeychainService actor]
            NS[NotificationService @MainActor @Observable class]
            LPS[LinkPreviewService final class]
            RXS[RxLogService actor]
            PL[PersistentLogger actor]
            DLB[DebugLogBuffer actor]
            CAL[CommandAuditLogger actor]
            ES[ElevationService actor]
            LS[LocationService final class NSObject]
        end

        PS[PersistenceStore @ModelActor actor]
    end

    subgraph MeshCore [Protocol Layer]
        MCS[MeshCoreSession actor]
        ED[EventDispatcher]
        PB[PacketBuilder enum]
        PP[PacketParser enum]
    end

    subgraph Transport [Transport Layer - in PocketMeshServices]
        BT[iOSBLETransport]
        BSM[BLEStateMachine]
        WT[WiFiTransport]
        WSM[WiFiStateMachine]
    end

    Views --> AppState
    AppState --> CM
    AppState --> MEB
    CM --> ServiceContainer
    CM --> SC
    CM --> MCS
    ServiceContainer --> MS
    ServiceContainer --> CS
    ServiceContainer --> CH
    ServiceContainer --> SS
    ServiceContainer --> AS
    ServiceContainer --> MPS
    ServiceContainer --> BPS
    ServiceContainer --> RNS
    ServiceContainer --> RAS
    ServiceContainer --> RSS
    ServiceContainer --> KS
    ServiceContainer --> NS
    ServiceContainer --> LPS
    ServiceContainer --> RXS
    ServiceContainer --> PL
    ServiceContainer --> DLB
    ServiceContainer --> CAL
    ServiceContainer --> ES
    ServiceContainer --> LS
    ServiceContainer --> DS
    ServiceContainer --> HRS
    SC --> MS
    SC --> CS
    SC --> CH
    SC --> MPS
    MEB --> MS
    MS --> MCS
    CS --> MCS
    CH --> MCS
    SS --> MCS
    AS --> MCS
    MPS --> MCS
    BPS --> MCS
    RNS --> MCS
    RAS --> RNS
    RSS --> RNS
    RNS --> KS
    MCS --> ED
    CM --> BT
    BT --> MCS
    MCS --> PB
    MCS --> PP
    BT --> BSM
    CM --> WT
    WT --> MCS
    WT --> WSM
    MS --> PS
    CS --> PS
    CH --> PS
    MPS --> PS
    AS --> PS
    BPS --> PS
    RNS --> PS
    RAS --> PS
    RSS --> PS
    DS --> PS
    HRS --> PS
```

---

## 1. MeshCore (Protocol Layer)

The foundation of the project, responsible for low-level communication with MeshCore devices.

- **Actor-Based**: `MeshCoreSession` is an actor that serializes all device communication, ensuring thread safety.
- **Event-Driven**: Uses an `EventDispatcher` to broadcast `MeshEvent`s via `AsyncStream`.
- **Stateless Protocol Handlers**: `PacketBuilder` and `PacketParser` are stateless enums that handle the binary encoding/decoding of the Companion Radio Protocol.
- **Transport Abstraction**: The `MeshTransport` protocol allows for different underlying transports. `MockTransport` (for unit testing) is in MeshCore, while `iOSBLETransport` (using CoreBluetooth with `BLEStateMachine`) and `WiFiTransport` (for MeshCore firmware devices) are in PocketMeshServices.
- **Dual Transport Support**: Supports both Bluetooth Low Energy (BLE) and WiFi transports simultaneously. Each transport has its own state machine for managing connection lifecycle.
- **Auto-Reconnection**: Both transports automatically reconnect when connection is lost, with configurable retry logic and backoff strategies.
- **LPP Telemetry**: Includes a full implementation of the Cayenne Low Power Payload (LPP) for efficient sensor data transmission.

See: [MeshCore API Reference](api/MeshCore.md) | [BLE Transport Guide](guides/BLE_Transport.md)

---

## 2. PocketMeshServices (Business Logic Layer)

Bridges the protocol layer and the UI, handling complex business rules and data persistence.

- **Service-Oriented**: Business logic is divided into specialized actors (`MessageService`, `ContactService`, `ChannelService`, `RemoteNodeService`, etc.).
- **Dependency Injection**: `ServiceContainer` manages the creation and wiring of all services, providing a single point of initialization for the service layer.
- **Sync Coordination**: `SyncCoordinator` orchestrates the connection lifecycle and data synchronization through contacts, channels, and messages phases.
- **Actor Isolation**: Every service is an actor, protecting internal state and coordinating asynchronous operations safely.
- **Persistence**: Uses **SwiftData** for local storage. Data is isolated per device using the `deviceID: UUID` field (the device's BLE peripheral UUID) as a namespace, ensuring each device has its own isolated data.
- **DTO Pattern**: Sendable Data Transfer Objects (`MessageDTO`, `ContactDTO`, `DeviceDTO`, etc.) enable safe cross-actor data transfer while maintaining strict concurrency compliance.
- **Connection Management**: `ConnectionManager` (a `@MainActor` observable class) manages the lifecycle of the connection, including pairing via **AccessorySetupKit**, auto-reconnection, and service wiring.
- **Message Polling**: `MessagePollingService` pulls messages from the device queue and routes them to appropriate handlers.

### ServiceContainer & Dependency Injection

The `ServiceContainer` is the central dependency injection container for PocketMeshServices. It creates and manages all services, handling the dependency graph and lifecycle:

**Independent Services** (no service dependencies):
- `KeychainService`: Secure credential storage using system keychain
- `NotificationService`: Local notification management for message alerts
- `LinkPreviewService`: URL metadata extraction for rich link previews in messages
- `RxLogService`: RF packet capture and logging for network diagnostics
- `PersistentLogger`: In-memory buffering and SwiftData-based persistent debug logging
- `DebugLogBuffer`: Efficient in-memory circular buffer for recent debug logs
- `CommandAuditLogger`: Auditing of CLI commands sent to devices for security and debugging
- `ElevationService`: Terrain elevation data fetching from Open-Meteo API for Line of Sight analysis

**Core Services** (depend on session/dataStore):
- `ContactService`: Contact management and synchronization
- `MessageService`: Message sending, receiving, and retry logic
- `ChannelService`: Channel (group) configuration and messaging
- `SettingsService`: Device settings and configuration management
- `AdvertisementService`: Advertisement broadcasting and path discovery
- `MessagePollingService`: Automatic message fetching from device queue
- `BinaryProtocolService`: Binary protocol operations (telemetry, status, etc.)
- `DeviceService`: Device information and management
- `HeardRepeatsService`: Tracking message repeat counts for channel propagation analysis

**Remote Node Services** (depend on other services):
- `RemoteNodeService`: Remote node session management and authentication
- `RepeaterAdminService`: Repeater administration and configuration
- `RoomServerService`: Room server operations and message routing

**Lifecycle Management**:
```swift
// Create container
let container = ServiceContainer(session: meshCoreSession, modelContainer: modelContainer)

// Wire inter-service dependencies
await container.wireServices()

// Start event monitoring when device connects
await container.startEventMonitoring(deviceID: deviceUUID)

// Perform initial sync
await container.performInitialSync(deviceID: deviceUUID)
```

### DTO (Data Transfer Object) Pattern

To comply with Swift 6's strict concurrency model, all SwiftData models have corresponding `Sendable` DTO types for cross-actor communication:

**Model-to-DTO Conversion**:
- `MessageDTO`: Sendable snapshot of `Message` for passing between actors
- `ContactDTO`: Sendable snapshot of `Contact` for UI and service communication
- `DeviceDTO`: Sendable snapshot of `Device` for device information
- `ChannelDTO`: Sendable snapshot of `Channel` for channel configuration
- `RemoteNodeSessionDTO`: Sendable snapshot of `RemoteNodeSession` for session state
- `RoomMessageDTO`: Sendable snapshot of `RoomMessage` for room communications

**Usage Pattern**:
```swift
// In actor-isolated service
func fetchMessages(deviceID: UUID) async -> [MessageDTO] {
    let messages = await dataStore.fetchMessages(deviceID: deviceID)
    return messages.map { MessageDTO(from: $0) }
}

// In @MainActor UI code
let messageDTOs = await messageService.fetchMessages(deviceID: deviceID)
// DTOs are Sendable, safe to use across actor boundaries
```

**Benefits**:
- **Concurrency Safety**: DTOs are `Sendable`, enabling safe cross-actor transfers
- **Immutability**: Snapshot semantics prevent unintended mutations
- **Actor Isolation**: Services work with SwiftData models; UI and callbacks receive DTOs
- **Clean Boundaries**: Clear separation between persistence and business logic layers

See: [PocketMeshServices API Reference](api/PocketMeshServices.md) | [Sync Guide](guides/Sync.md) | [Messaging Guide](guides/Messaging.md)

---

## 3. PocketMesh (UI Layer)

A modern SwiftUI application that provides a user-friendly experience for mesh messaging.

- **AppState**: A central `@Observable` class that manages app-wide state, navigation, and coordination between the UI and services.
- **MessageEventBroadcaster**: Bridges service layer callbacks to SwiftUI's `@MainActor` context for real-time UI updates.
- **SwiftUI & Modern APIs**: Built with the latest SwiftUI features, utilizing `@Observable`, environment injection, and modern navigation.
- **Onboarding Flow**: A guided experience for permissions, discovery, and device pairing.
- **iMessage-Style Chat**: Rich messaging interface with delivery status, timestamps, and metadata (SNR, path length).
- **MapKit Integration**: Displays contact locations on a map with real-time updates and type-based markers.

See: [PocketMesh API Reference](api/PocketMesh.md) | [User Guide](User_Guide.md)

---

## Concurrency & Data Flow

### Concurrency Model

PocketMesh strictly adheres to the **Swift 6 concurrency model**:

- **Actors**: Used for all services and session management to prevent data races.
- **MainActor**: UI updates, `ConnectionManager`, and `MessageEventBroadcaster` are isolated to the main thread.
- **AsyncStream**: Used for all event-driven communication (BLE data -> Protocol events -> Business events -> UI updates).
- **Structured Concurrency**: Utilizes `TaskGroups` for complex asynchronous flows like message retries and contact synchronization.

### Data Flow (Receiving a Message)

1. **BLE Transport**: `BLEStateMachine` receives a notification from CoreBluetooth and yields the data to `iOSBLETransport`'s `receivedData` stream.
2. **Session Parser**: `MeshCoreSession` receives the data, uses `PacketParser` to create a `MeshEvent`, and dispatches it via `EventDispatcher`.
3. **Service Processing**: `MessagePollingService` receives the event, routes it to the appropriate handler based on message type.
4. **Persistence**: The handler creates a `MessageDTO` and saves it to `PersistenceStore`.
5. **UI Update**: `MessageEventBroadcaster` receives the callback, updates observable state, triggering SwiftUI view updates.

### Data Flow (Sending a Message)

1. **User Action**: User types message in `ChatView` and taps send.
2. **Service Call**: `MessageService.sendMessageWithRetry()` is called.
3. **Queue**: Message is saved to `PersistenceStore` with status `.pending`.
4. **Retry Loop**: `MeshCoreSession.sendMessageWithRetry()` attempts delivery (up to 4 times by default, switching to flood after 2 failed direct attempts).
5. **ACK Tracking**: Each send attempt waits inline for ACK using `waitForEvent()` with configurable timeout.
6. **Completion**: ACK received -> `.delivered`, or all attempts exhausted -> `.failed`.

---

## Persistence Layer

- **Technology**: SwiftData
- **Isolation**: Each MeshCore device has its own isolated data store using `deviceID: UUID` (the BLE peripheral UUID) as the namespace, ensuring privacy and preventing data mixing.
- **Models**:
  - `Device`: Metadata, radio parameters, and capabilities. The `id` field is derived from the BLE peripheral identifier.
  - `Contact`: Public keys, names, types (Chat, Repeater, Room), and location data. Contains `deviceID` for isolation.
  - `Message`: Content, timestamps, delivery status, and mesh metadata (SNR, Path). Contains `deviceID` for isolation.
  - `Channel`: Slot-based configuration for group messaging. Contains `deviceID` for isolation.
  - `RemoteNodeSession`: Tracks authenticated sessions with remote repeater/room nodes.
  - `RoomMessage`: Messages exchanged in room server conversations.
- **DTOs**: Each model has a corresponding `Sendable` DTO for safe cross-actor transfers.

---

## Debug Logging Infrastructure

PocketMesh includes a comprehensive debug logging system designed to help diagnose issues in the field without requiring a developer machine.

### Architecture

The debug logging system is implemented as a two-layer architecture:

1. **In-Memory Buffer (`DebugLogBuffer`)**:
   - Circular buffer with configurable maximum size (default: 10,000 entries)
   - Efficient memory usage with automatic overflow handling
   - Fast append and recent-entry queries for UI display

2. **Persistent Storage (`PersistentLogger`)**:
   - SwiftData-backed persistent storage for long-term log retention
   - Background writes to prevent blocking main thread
   - Configurable retention period (default: 24 hours)
   - Automatic cleanup of old logs

### Usage Pattern

```swift
// Log from any context (automatically includes timestamp, file, line, function)
logger.info("Connected to device")
logger.warning("High packet loss detected", metadata: ["loss_rate": "15%"])
logger.error("Failed to parse packet", error: error)

// Retrieve recent logs for display
let recentLogs = await debugLogBuffer.getRecentLogs(limit: 100)

// Export logs for analysis
let logs = await persistentLogger.getLogs(timeRange: last24Hours)
let exportData = logExportService.exportLogs(logs: logs)
```

### Log Categories

Logs are categorized for easy filtering:

- **Connection**: BLE/WiFi connection lifecycle, pairing, reconnection
- **Messaging**: Message sending, delivery, retries, ACK tracking
- **Sync**: Contact/channel synchronization, data updates
- **Transport**: Protocol events, packet parsing, transport errors
- **UI**: Navigation, user actions, state changes
- **Diagnostics**: Line of Sight, Trace Path, RX Log operations

### Redaction

Sensitive data is automatically redacted from logs to protect privacy:

- Full public keys are truncated (first 8 characters only)
- Passwords are never logged
- Personal identifying information is masked
- User message content is sanitized

### Export & Analysis

Debug logs can be exported for analysis:

- **Log Export Service**: Exports logs to structured format (JSON)
- **Time Range**: Configurable export window (1-24 hours)
- **Email Integration**: Share logs via email with app version and device info
- **Command Audit**: Separate log of all CLI commands sent to devices for security auditing

---

## iPad Split-View Architecture

On iPad, PocketMesh uses a split-view layout that provides a more efficient workflow and better use of available screen real estate.

### Navigation Pattern

The split-view implementation follows Apple's iPad interface guidelines:

- **Two-Panel Layout**: List panel (left) and detail panel (right)
- **Independent Navigation Stacks**: Each panel maintains its own navigation state
- **Tab Coordination**: All tabs (Chats, Contacts, Map, Tools, Settings) support split-view
- **Responsive Design**: Automatically adjusts layout based on orientation and window size

### Implementation Details

```swift
// AppState manages split-view state
@Observable class AppState {
    var splitViewSelection: TabSelection? = nil
    var selectedConversation: Conversation? = nil
    var selectedContact: Contact? = nil

    // Methods to update right panel based on left panel selection
    func selectConversation(_ conversation: Conversation) {
        selectedConversation = conversation
        // Right panel updates independently
    }
}
```

### Panel Independence

- **List Panel**: Shows master list (chats, contacts, map annotations)
- **Detail Panel**: Shows selected item (conversation, contact details, map location)
- **State Separation**: Changes in right panel don't affect left panel state
- **Concurrent Updates**: Both panels can update independently as data changes

### Adaptive Behavior

- **Portrait**: Stacked panels (list on top, detail below)
- **Landscape**: Side-by-side panels (list on left, detail on right)
- **Regular Size Class**: Always shows both panels
- **Compact Size Class**: Shows single panel with full-screen navigation

---

## Diagnostic Tools Architecture

PocketMesh includes several diagnostic tools built on a shared infrastructure for RF analysis and network troubleshooting.

### Shared Services

- **Elevation Service**: Fetches terrain elevation data from Open-Meteo API
- **RF Calculator**: Core calculations for signal propagation, Fresnel zones, and link budget
- **Location Service**: Manages location permissions and current position for analysis

### Line of Sight Tool

**Components**:
- `LineOfSightView`: Main SwiftUI view for analysis interface
- `LineOfSightViewModel`: State management and business logic
- `RFCalculator`: RF propagation calculations (path loss, Fresnel zone clearance)
- `SegmentAnalysis`: Terrain segment analysis for obstruction detection
- `FresnelZoneRenderer`: Canvas-based visualization of Fresnel zones
- `TerrainProfileCanvas`: Custom canvas for terrain profile visualization

**Workflow**:
1. User selects target contact or enters coordinates
2. Elevation data is fetched along path (Open-Meteo API)
3. Terrain profile is generated from elevation samples
4. Fresnel zones are calculated for given frequency
5. Clearance analysis determines signal quality (green/yellow/red)
6. Visual results are rendered with clearance status

### Trace Path Tool

**Components**:
- `TracePathView`: Main view for path discovery
- `TracePathViewModel`: Path discovery and management logic
- `SavedPathsViewModel`: Management of saved routing paths
- `PathEditingSheet`: Interactive path editor with repeater selection

**Workflow**:
1. User initiates trace path from contact detail
2. App discovers available repeaters and routes to target
3. Path results are displayed with signal quality per hop
4. User can edit path by selecting different repeaters
5. Saved paths are persisted for future use and can be visualized on map

### RX Log Viewer

**Components**:
- `RxLogView`: Live packet capture viewer
- `RxLogViewModel`: Packet capture and filtering logic
- `RxLogService`: Service for packet capture and persistence

**Workflow**:
1. User opens RX Log viewer
2. Service starts capturing RF packets from transport layer
3. Packets are displayed in real-time with metadata
4. User can filter by packet type, source, or destination
5. Logs can be exported for offline analysis

---

## Further Reading

- [Development Guide](Development.md)
- [User Guide](User_Guide.md)

### API References
- [MeshCore API](api/MeshCore.md)
- [PocketMeshServices API](api/PocketMeshServices.md)
- [PocketMesh API](api/PocketMesh.md)

### Topic Guides
- [BLE Transport](guides/BLE_Transport.md)
- [WiFi Transport](guides/WiFi_Transport.md)
- [Messaging](guides/Messaging.md)
- [Sync](guides/Sync.md)
- [Diagnostics](guides/Diagnostics.md)
- [iPad Layout](guides/iPad_Layout.md)
