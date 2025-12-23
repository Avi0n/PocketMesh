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

### Navigation State

| Property | Type | Description |
|----------|------|-------------|
| `selectedTab` | `Int` | Active tab: 0=Chats, 1=Contacts, 2=Map, 3=Settings |
| `hasCompletedOnboarding` | `Bool` | Whether onboarding flow is complete |

### Navigation Methods

| Method | Description |
|--------|-------------|
| `navigateToChat(with:)` | Triggers navigation to a specific chat conversation |
| `navigateToDiscovery()` | Triggers navigation to contact discovery screen |

### Lifecycle Methods

| Method | Description |
|--------|-------------|
| `initialize() async` | Call on launch to activate services and auto-reconnect |
| `handleReturnToForeground() async` | Updates unread counts and checks expired ACKs |

### UI Coordination

| Property | Type | Description |
|----------|------|-------------|
| `messageEventBroadcaster` | `MessageEventBroadcaster` | Triggers UI refreshes for service events |
| `shouldShowSyncingPill` | `Bool` | Indicates background sync in progress |

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
| `handleAcknowledgement(ackCode:)` | Handles ACK receipt |
| `handleMessageFailed(messageID:)` | Handles delivery failure |
| `handleMessageRetrying(messageID:attempt:maxAttempts:)` | Handles retry progress |
| `handleRoutingChanged(contactID:isFlood:)` | Handles routing mode change |

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

---

## Entry Points

### PocketMeshApp (@main)

The main entry point. Initializes `AppState` with a SwiftData `ModelContainer` and injects it into the environment.

### ContentView

Root view that switches between `OnboardingView` and main `TabView` based on `appState.hasCompletedOnboarding`.

---

## See Also

- [Architecture Overview](../Architecture.md)
- [User Guide](../User_Guide.md)
