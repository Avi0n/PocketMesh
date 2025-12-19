# PocketMesh App API Reference

The `PocketMesh` app layer manages the user interface, application lifecycle, and coordinates services.

## AppState (MainActor, Observable)

The central state management object for the application.

### Connection & Services

- `connectionManager: ConnectionManager`
  The source of truth for the device connection.
- `connectionState: ConnectionState`
  Convenience accessor for the current connection status.
- `services: ServiceContainer?`
  Provides access to business logic services when connected.

### Navigation State

- `selectedTab: Int`
  The currently active tab (0: Chats, 1: Contacts, 2: Map, 3: Settings).
- `navigateToChat(with contact: ContactDTO)`
  Triggers navigation to a specific chat conversation.
- `navigateToDiscovery()`
  Triggers navigation to the contact discovery screen.

### Lifecycle Methods

- `initialize() async`
  Call on app launch to activate services and attempt auto-reconnect.
- `handleReturnToForeground() async`
  Updates unread counts and checks for expired acknowledgments.

### UI Coordination

- `messageEventBroadcaster: MessageEventBroadcaster`
  An object that triggers UI refreshes based on service-layer events (new messages, ACK updates).
- `shouldShowSyncingPill: Bool`
  Indicates if a background sync operation (contacts, channels, settings) is in progress.

---

## MessageEventBroadcaster (MainActor)

Coordinates real-time UI updates across different views.

- `conversationRefreshTrigger: Int`
  An observable counter used to trigger a refresh of the conversation list.
- `handleMessageSent(messageID: UUID)`
  Notifies the UI that a message has transitioned to the "Sent" state.
- `handleMessageDelivered(messageID: UUID, rtt: UInt32)`
  Notifies the UI that an ACK was received for a message.
- `handleMessageFailed(messageID: UUID)`
  Notifies the UI that a message delivery failed.

---

## Entry Points

### PocketMeshApp (@main)

The main entry point of the application. It initializes `AppState` with a SwiftData `ModelContainer` and injects it into the environment.

### ContentView

The root view that switches between the `OnboardingView` and the main `TabView` based on `appState.hasCompletedOnboarding`.
