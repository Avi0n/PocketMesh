# PocketMesh App API Reference

The `PocketMesh` app layer manages the user interface, application lifecycle, and coordinates services.

## Target Information

- **Location:** `PocketMesh/`
- **Type:** iOS Application
- **Dependencies:** PocketMeshServices, MeshCore

---

## AppState (public, @MainActor, @Observable class)

**File:** `PocketMesh/AppState.swift`

The central state management object for the application.

### Connection Properties

| Property | Type | Description |
|----------|------|-------------|
| `connectionManager` | `ConnectionManager` | Source of truth for device connection |
| `connectionState` | `ConnectionState` | Convenience accessor for connection status |
| `services` | `ServiceContainer?` | Business logic services (when connected) |
| `syncCoordinator` | `SyncCoordinator?` | Coordinates background sync operations |
| `connectedDevice` | `DeviceDTO?` | Currently connected device information |
| `deviceBatteryMillivolts` | `UInt16?` | Device battery voltage in millivolts |

### Navigation State

| Property | Type | Description |
|----------|------|-------------|
| `selectedTab` | `Int` | Active tab: 0=Chats, 1=Contacts, 2=Map, 3=Settings |
| `hasCompletedOnboarding` | `Bool` | Whether onboarding flow is complete |
| `tabBarVisibility` | `Visibility` | Controls tab bar visibility (e.g., hidden in chat) |
| `pendingChatContact` | `ContactDTO?` | Contact to navigate to after connection |
| `pendingRoomSession` | `RemoteNodeSessionDTO?` | Room session to navigate to after connection |
| `onboardingStep` | `OnboardingStep` | Current step in onboarding flow |

### Navigation Methods

| Method | Description |
|--------|-------------|
| `navigateToChat(with:)` | Triggers navigation to a specific chat conversation |
| `navigateToDiscovery()` | Triggers navigation to contact discovery screen |
| `navigateToRoom(with:)` | Triggers navigation to a room server session |
| `navigateToContacts()` | Switches to Contacts tab |
| `clearPendingNavigation()` | Clears pending navigation state |

### Lifecycle Methods

| Method | Description |
|--------|-------------|
| `initialize() async` | Call on launch to activate services and auto-reconnect |
| `handleReturnToForeground() async` | Updates unread counts and checks expired ACKs |
| `handleEnterBackground()` | Handles app entering background state |
| `startDeviceScan()` | Initiates Bluetooth device scanning |
| `disconnect()` | Disconnects from current device |
| `fetchDeviceBattery()` | Fetches current device battery level |
| `completeOnboarding()` | Marks onboarding as complete |
| `resetOnboarding()` | Resets onboarding state to welcome screen |

### UI Coordination

| Property | Type | Description |
|----------|------|-------------|
| `messageEventBroadcaster` | `MessageEventBroadcaster` | Triggers UI refreshes for service events |
| `shouldShowSyncingPill` | `Bool` | Indicates background sync in progress |
| `servicesVersion` | `Int` | Incremented to trigger view reloads when services change |
| `contactsVersion` | `Int` | Incremented to trigger contact list updates |
| `conversationsVersion` | `Int` | Incremented to trigger conversation list updates |

### Sync Coordination

| Method | Description |
|--------|-------------|
| `withSyncActivity(_:)` | Executes an async operation with sync UI state management |

---

## MessageEventBroadcaster (public, @MainActor, @Observable class)

**File:** `PocketMesh/Services/MessageEventBroadcaster.swift`

Bridges service layer callbacks to SwiftUI's `@MainActor` context for real-time UI updates.

### Event Types

```swift
public enum MessageEvent: Sendable, Equatable {
    case directMessageReceived(message: MessageDTO, contact: ContactDTO)
    case channelMessageReceived(message: MessageDTO, channelIndex: UInt8)
    case roomMessageReceived(message: RoomMessageDTO, sessionID: UUID)
    case messageStatusUpdated(ackCode: UInt32)
    case messageFailed(messageID: UUID)
    case messageRetrying(messageID: UUID, attempt: Int, maxAttempts: Int)
    case routingChanged(contactID: UUID, isFlood: Bool)
    case unknownSender(keyPrefix: Data)
    case error(String)
}
```

### Observable Properties

| Property | Type | Description |
|----------|------|-------------|
| `latestMessage` | `MessageDTO?` | Latest received message |
| `latestEvent` | `MessageEvent?` | Latest event for reactive updates |
| `newMessageCount` | `Int` | Incremented to trigger view updates |

### Event Handlers

| Method | Description |
|--------|-------------|
| `handleDirectMessage(_:from:)` | Handles incoming direct message |
| `handleChannelMessage(_:channelIndex:)` | Handles incoming channel message |
| `handleRoomMessage(_:contact:)` | Handles incoming room message |
| `handleAcknowledgement(ackCode:)` | Handles ACK receipt |
| `handleMessageFailed(messageID:)` | Handles delivery failure |
| `handleMessageRetrying(messageID:attempt:maxAttempts:)` | Handles retry progress |
| `handleRoutingChanged(contactID:isFlood:)` | Handles routing mode change |
| `handleUnknownSender(keyPrefix:)` | Handles message from unknown sender |
| `handleError(_:)` | Handles error events |

---

## ViewModels

### ChatViewModel (internal, @MainActor, @Observable class)

**File:** `PocketMesh/Views/Chats/ChatViewModel.swift`

Manages state for the chat conversation view.

| Property | Type | Description |
|----------|------|-------------|
| `messages` | `[MessageDTO]` | Conversation messages |
| `currentContact` | `ContactDTO?` | Current chat contact |
| `currentChannel` | `ChannelDTO?` | Current channel being viewed |
| `conversations` | `[ContactDTO]` | Current conversations (contacts with messages) |
| `channels` | `[ChannelDTO]` | Current channels with messages |
| `roomSessions` | `[RemoteNodeSessionDTO]` | Current room sessions |
| `isLoading` | `Bool` | Loading state |
| `isSending` | `Bool` | Whether a message is being sent |
| `composingText` | `String` | Message text being composed |

**Key Methods:**

| Method | Description |
|--------|-------------|
| `loadMessages(for:)` | Load messages for a contact |
| `sendMessage()` | Send message to current contact |
| `retryMessage(_:)` | Retry failed message with flood routing |
| `loadChannelMessages(for:)` | Load messages for a channel |
| `sendChannelMessage()` | Send message to current channel |

### ContactsViewModel (internal, @MainActor, @Observable class)

**File:** `PocketMesh/Views/Contacts/ContactsViewModel.swift`

Manages state for the contacts list view.

| Property | Type | Description |
|----------|------|-------------|
| `contacts` | `[ContactDTO]` | All contacts |
| `isLoading` | `Bool` | Loading state |
| `isSyncing` | `Bool` | Syncing state |
| `syncProgress` | `(Int, Int)?` | Sync progress (current, total) |

**Key Methods:**

| Method | Description |
|--------|-------------|
| `loadContacts(deviceID:)` | Load contacts from local database |
| `syncContacts(deviceID:)` | Sync contacts from device |
| `filteredContacts(searchText:showFavoritesOnly:)` | Returns filtered and sorted contacts |
| `toggleFavorite(contact:)` | Toggle favorite status |
| `toggleBlocked(contact:)` | Toggle blocked status |

### MapViewModel (internal, @MainActor, @Observable class)

**File:** `PocketMesh/Views/Map/MapViewModel.swift`

Manages state for the map view showing contact locations.

| Property | Type | Description |
|----------|------|-------------|
| `contactsWithLocation` | `[ContactDTO]` | Contacts with valid coordinates |
| `selectedContact` | `ContactDTO?` | Currently selected marker |
| `cameraPosition` | `MapCameraPosition` | Map viewport position |
| `isLoading` | `Bool` | Loading state |

**Key Methods:**

| Method | Description |
|--------|-------------|
| `loadContactsWithLocation()` | Load contacts with valid locations |
| `centerOnContact(_:)` | Center map on a specific contact |
| `centerOnAllContacts()` | Center map to show all contacts |

### RepeaterStatusViewModel (internal, @MainActor, @Observable class)

**File:** `PocketMesh/Views/RemoteNodes/RepeaterStatusViewModel.swift`

Manages state for repeater status display, including neighbors and telemetry.

| Property | Type | Description |
|----------|------|-------------|
| `session` | `RemoteNodeSessionDTO?` | Current repeater session |
| `status` | `RemoteNodeStatus?` | Last received status from repeater |
| `neighbors` | `[NeighbourInfo]` | Neighboring nodes visible to repeater |
| `telemetry` | `TelemetryResponse?` | Last received telemetry data |
| `isLoadingStatus` | `Bool` | Status loading state |
| `isLoadingNeighbors` | `Bool` | Neighbors loading state |
| `isLoadingTelemetry` | `Bool` | Telemetry loading state |
| `neighborsExpanded` | `Bool` | Neighbors disclosure group expansion state |
| `telemetryExpanded` | `Bool` | Telemetry disclosure group expansion state |
| `clockTime` | `String?` | Clock time from repeater |
| `errorMessage` | `String?` | Error message if any |

**Key Methods:**

| Method | Description |
|--------|-------------|
| `configure(appState:)` | Configure with services from AppState |
| `registerHandlers(appState:)` | Register for push notification handlers |
| `requestStatus(for:)` | Request status from the repeater |
| `requestNeighbors(for:)` | Request neighbors from the repeater |
| `requestTelemetry(for:)` | Request telemetry from the repeater |
| `handleStatusResponse(_:)` | Handle status response from push notification |
| `handleNeighboursResponse(_:)` | Handle neighbours response from push notification |
| `handleTelemetryResponse(_:)` | Handle telemetry response from push notification |
| `handleCLIResponse(_:from:)` | Handle CLI response (for clock time) |

**Computed Properties:**

| Property | Description |
|----------|-------------|
| `uptimeDisplay` | Formatted uptime string (e.g., "2 days 5h 30m") |
| `batteryDisplay` | Formatted battery voltage and percentage |
| `lastRSSIDisplay` | Formatted RSSI value (dBm) |
| `lastSNRDisplay` | Formatted SNR value (dB) |
| `noiseFloorDisplay` | Formatted noise floor (dBm) |
| `packetsSentDisplay` | Formatted packets sent count |
| `packetsReceivedDisplay` | Formatted packets received count |
| `clockDisplay` | Formatted clock time |

### RepeaterSettingsViewModel (internal, @MainActor, @Observable class)

**File:** `PocketMesh/Views/RemoteNodes/RepeaterSettingsViewModel.swift`

Manages state for repeater configuration including identity, radio settings, and behavior.

| Property | Type | Description |
|----------|------|-------------|
| `session` | `RemoteNodeSessionDTO?` | Current repeater session |
| `firmwareVersion` | `String?` | Device firmware version |
| `deviceTime` | `String?` | Device clock time |
| `name` | `String` | Repeater name |
| `latitude` | `Double` | Repeater latitude |
| `longitude` | `Double` | Repeater longitude |
| `frequency` | `Double` | Radio frequency (MHz) |
| `bandwidth` | `Double` | Radio bandwidth (kHz) |
| `spreadingFactor` | `Int` | LoRa spreading factor |
| `codingRate` | `Int` | LoRa coding rate |
| `txPower` | `Int` | Transmit power (dBm) |
| `advertIntervalMinutes` | `Int` | Advertisement interval (minutes) |
| `floodAdvertIntervalHours` | `Int` | Flood advertisement interval (hours) |
| `floodMaxHops` | `Int` | Maximum flood hops |
| `repeaterEnabled` | `Bool` | Whether repeater mode is enabled |
| `isLoadingDeviceInfo` | `Bool` | Device info loading state |
| `isLoadingIdentity` | `Bool` | Identity loading state |
| `isLoadingRadio` | `Bool` | Radio settings loading state |
| `isLoadingBehavior` | `Bool` | Behavior settings loading state |
| `isApplying` | `Bool` | Settings apply state |
| `isRebooting` | `Bool` | Reboot in progress |
| `errorMessage` | `String?` | Error message if any |
| `successMessage` | `String?` | Success message if any |
| `radioSettingsModified` | `Bool` | Whether radio settings need restart |

**Key Methods:**

| Method | Description |
|--------|-------------|
| `configure(appState:session:)` | Configure with services and session |
| `registerHandlers(appState:)` | Register for CLI responses |
| `fetchDeviceInfo()` | Fetch firmware version and time |
| `fetchIdentity()` | Fetch name, latitude, longitude |
| `fetchRadioSettings()` | Fetch radio parameters |
| `fetchBehaviorSettings()` | Fetch repeater behavior settings |
| `handleCLIResponse(_:from:)` | Handle CLI response from push notification |
| `applyRadioSettings()` | Apply all radio settings (requires restart) |
| `applyNameImmediately()` | Apply name with debouncing |
| `applyLatitudeImmediately()` | Apply latitude with debouncing |
| `applyLongitudeImmediately()` | Apply longitude with debouncing |
| `applyLocation(latitude:longitude:)` | Apply location coordinates together |
| `applyRepeaterModeImmediately()` | Apply repeater enabled state |
| `applyAdvertIntervalImmediately()` | Apply advertisement interval |
| `applyFloodAdvertIntervalImmediately()` | Apply flood advertisement interval |
| `applyFloodMaxImmediately()` | Apply flood max hops |
| `changePassword()` | Change admin password |
| `reboot()` | Reboot the repeater |
| `forceAdvert()` | Force immediate advertisement |
| `cleanup()` | Cancel all pending tasks on view disappear |

### RoomConversationViewModel (internal, @MainActor, @Observable class)

**File:** `PocketMesh/Views/RemoteNodes/RoomConversationViewModel.swift`

Manages state for room server chat functionality.

| Property | Type | Description |
|----------|------|-------------|
| `session` | `RemoteNodeSessionDTO?` | Current room session |
| `messages` | `[RoomMessageDTO]` | Room conversation messages |
| `isLoading` | `Bool` | Loading state |
| `errorMessage` | `String?` | Error message if any |
| `composingText` | `String` | Message text being composed |
| `isSending` | `Bool` | Whether a message is being sent |

**Key Methods:**

| Method | Description |
|--------|-------------|
| `configure(appState:)` | Configure with services from AppState |
| `loadMessages(for:)` | Load messages for a room session |
| `sendMessage()` | Send message to room server |
| `refreshMessages()` | Refresh messages for current session |

**Static Helpers:**

| Method | Description |
|--------|-------------|
| `shouldShowTimestamp(at:in:)` | Determines if timestamp should be shown (>5 min gap) |

### PathManagementViewModel (internal, @MainActor, @Observable class)

**File:** `PocketMesh/Views/Contacts/PathManagementViewModel.swift`

Manages state for routing path discovery and editing.

| Property | Type | Description |
|----------|------|-------------|
| `isDiscovering` | `Bool` | Whether path discovery is active |
| `isSettingPath` | `Bool` | Whether path update is in progress |
| `discoveryResult` | `PathDiscoveryResult?` | Result of path discovery operation |
| `showDiscoveryResult` | `Bool` | Whether to show discovery result alert |
| `errorMessage` | `String?` | Error message if any |
| `showError` | `Bool` | Whether to show error alert |
| `showingPathEditor` | `Bool` | Whether path editor sheet is shown |
| `editablePath` | `[PathHop]` | Current path being edited |
| `availableRepeaters` | `[ContactDTO]` | Known repeaters available to add |
| `allContacts` | `[ContactDTO]` | All contacts for name resolution |
| `filteredAvailableRepeaters` | `[ContactDTO]` | Repeaters not already in path |
| `onContactNeedsRefresh` | `(() -> Void)?` | Callback when contact needs refresh |

**Key Methods:**

| Method | Description |
|--------|-------------|
| `configure(appState:onContactNeedsRefresh:)` | Configure with services and callback |
| `loadContacts(deviceID:)` | Load contacts for name resolution |
| `initializeEditablePath(from:)` | Initialize editable path from contact |
| `resolveHashToName(_:)` | Resolve path hash byte to contact name |
| `createPathHop(from:)` | Create PathHop with name resolution |
| `addRepeater(_:)` | Add repeater to path |
| `removeRepeater(at:)` | Remove repeater from path |
| `moveRepeater(from:to:)` | Reorder repeaters in path |
| `saveEditedPath(for:)` | Save edited path to contact |
| `discoverPath(for:)` | Initiate path discovery with timeout |
| `cancelDiscovery()` | Cancel in-progress discovery |
| `handleDiscoveryResponse(hopCount:)` | Handle discovery response from push |
| `resetPath(for:)` | Reset path (force flood routing) |
| `setPath(for:path:pathLength:)` | Set specific path for contact |

---

## Data Models

### Conversation (enum)

**File:** `PocketMesh/Models/Conversation.swift`

Represents different types of conversations in the app. Provides a unified interface for displaying direct chats, channels, and room sessions in the conversation list.

```swift
enum Conversation: Identifiable, Hashable {
    case direct(ContactDTO)
    case channel(ChannelDTO)
    case room(RemoteNodeSessionDTO)

    var id: UUID {
        switch self {
        case .direct(let contact): contact.id
        case .channel(let channel): channel.id
        case .room(let session): session.id
        }
    }
}
```

**Cases:**

| Case | Description |
|------|-------------|
| `direct(ContactDTO)` | One-on-one conversation with a contact |
| `channel(ChannelDTO)` | Group conversation on a mesh channel |
| `room(RemoteNodeSessionDTO)` | Multi-user room server session |

**Computed Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `id` | `UUID` | Unique identifier for the conversation |
| `displayName` | `String` | Display name for the conversation |
| `lastMessageDate` | `Date?` | Timestamp of last message or activity |
| `unreadCount` | `Int` | Number of unread messages |
| `isChannel` | `Bool` | Whether this is a channel conversation |
| `isRoom` | `Bool` | Whether this is a room conversation |
| `channelIndex` | `UInt8?` | Channel index if channel, nil otherwise |
| `contact` | `ContactDTO?` | Contact if direct chat, nil otherwise |
| `channel` | `ChannelDTO?` | Channel if channel chat, nil otherwise |
| `roomSession` | `RemoteNodeSessionDTO?` | Room session if room chat, nil otherwise |

### OnboardingStep (enum)

**File:** `PocketMesh/AppState.swift`

Represents the steps in the onboarding flow.

```swift
enum OnboardingStep: Int, CaseIterable {
    case welcome
    case permissions
    case deviceScan
}
```

**Cases:**

| Case | Description |
|------|-------------|
| `welcome` | Initial welcome screen |
| `permissions` | Bluetooth and notification permissions request |
| `deviceScan` | Device scanning and connection |

**Computed Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `next` | `OnboardingStep?` | Next step in flow (nil if last) |
| `previous` | `OnboardingStep?` | Previous step in flow (nil if first) |

### PathHop (struct)

**File:** `PocketMesh/Views/Contacts/PathManagementViewModel.swift`

Represents a single hop in a routing path with stable identity for SwiftUI.

```swift
struct PathHop: Identifiable, Equatable {
    let id: UUID
    var hashByte: UInt8
    var resolvedName: String?
}
```

**Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `id` | `UUID` | Unique identifier for SwiftUI list management |
| `hashByte` | `UInt8` | First byte of repeater's public key |
| `resolvedName` | `String?` | Contact name if resolved, nil if unknown |
| `displayText` | `String` | Formatted display text (name + hash or just hash) |

### PathDiscoveryResult (enum)

**File:** `PocketMesh/Views/Contacts/PathManagementViewModel.swift`

Result of a path discovery operation.

```swift
enum PathDiscoveryResult: Equatable {
    case success(hopCount: Int, fromCache: Bool = false)
    case noPathFound
    case failed(String)
}
```

**Cases:**

| Case | Description |
|------|-------------|
| `success(hopCount:fromCache:)` | Path discovered successfully with hop count |
| `noPathFound` | Remote node did not respond to discovery |
| `failed(String)` | Discovery failed with error message |

**Computed Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `description` | `String` | Human-readable description of result |

---

## Entry Points

### PocketMeshApp (@main)

The main entry point. Initializes `AppState` with a SwiftData `ModelContainer` and injects it into the environment.

### ContentView

**File:** `PocketMesh/ContentView.swift`

Root view that switches between `OnboardingView()` and `MainTabView()` (separate struct at line 45) based on `appState.hasCompletedOnboarding`. Manages the overall app navigation structure and coordinates with `AppState` for navigation events.

---

## See Also

- [Architecture Overview](../Architecture.md)
- [User Guide](../User_Guide.md)
