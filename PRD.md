# Product Requirements Document (PRD) for PocketMesh

## 1. Document Overview
### 1.1 Purpose
This PRD documents the requirements and implementation of PocketMesh, a native iOS application that enables seamless messaging and configuration over MeshCore BLE (Bluetooth Low Energy) devices. The app leverages the publicly documented Companion Radio Protocol to connect users to MeshCore companion radios and remote repeaters, facilitating off-grid, mesh-based communication. The primary goal is to provide a user-friendly experience for casual end users, making it as simple as possible to start messaging, similar to popular apps like iMessage and Signal.

**Implementation Status**: PocketMesh is a **planned iOS application** that will include MapKit integration for contact locations, BLE connection management with state restoration, and an iMessage-style chat interface. All core features and implementation phases described in this document are planned for implementation.

### 1.2 Scope
- **In Scope**: Core messaging (text and emojis in direct messages and channels), MeshCore device configuration for companion radios and remote repeaters, onboarding, notifications, location integration, on-device data storage.
- **Out of Scope**: Advanced features like trace paths or custom variables (planned for future iterations), monetization, third-party cloud syncing (except potential future iCloud for keys), multi-language support beyond English/US, encryption (MeshCore BLE device firmware handles encryption)
- **Future Enhancements**: iPad/macOS optimization (app is universal from launch), additional protocol commands, iCloud key backups, internationalization.

### 1.3 Version History
- Version 1.0: Initial PRD drafted on December 5, 2025.

### 1.4 Assumptions and Dependencies
- Users have access to MeshCore BLE companion radios and repeaters.
- The Companion Radio firmware (@MeshCore-firmware-example) is the source of truth; no customizations or enhancements to the MeshCore protocol.
- Development relies on Apple's frameworks (e.g., SwiftUI, CoreBluetooth, SwiftData, MapKit, UserNotifications, CoreLocation).
- No third-party libraries; free and open-source only if absolutely necessary (but avoided per requirements).
- Hardware testing via physical devices and Xcode debugging.
- App assumes good-faith use; no enforcement of disallowed activities per safety guidelines.

## 2. Target Audience and User Personas
### 2.1 Target Audience
- Casual end users interested in off-grid messaging, such as emergency preppers, or communities in remote areas.
- Age: 18+, tech-savvy but not developers; familiar with apps like iMessage or Signal.
- Platform: iPhone users on iOS 18.0+; optimized for iOS 26.1; universal app for iPhone/iPad/macOS via Catalyst.
- Region: Primarily US/English, with design for easy future localization.

### 2.2 User Personas
- **Casual Messenger (Primary)**: Alex, 28, Search and Rescue personnel. Wants to create a MeshCore network at SAR sites to enable off-grid communication between him and his team.
- Pain Points: No "KISS" apps.
- **Tech Tinkerer (Secondary)**: Jordan, 35, hobbyist. Enjoys configuring repeaters for extended range but appreciates a clean UI to avoid complexity.
- Pain Points: Complicated setups in existing tools; lack of intuitive messaging interfaces for MeshCore.

## 3. Product Features
Features are prioritized: MVP focuses on messaging and basic config; extensible for advanced additions.

### 3.1 Onboarding and Setup
- Simple, guided flow explaining MeshCore basics, BLE connection, contact discovery via adverts, and default radio params (US-focused).
- Permissions prompts: BLE, notifications, location.
- PIN entry for device pairing (default 123456 or random for screen-equipped devices).
- User can set public info (name, public key retrieval, location toggle).

### 3.2 Messaging
- **Direct Messaging**: Text/emojis to contacts (max 160 bytes); history, delivery tracking via ACK codes, replies (long-press to reply, no threading). Retry logic: 3 direct attempts with exponential backoff, then flood mode fallback.
- **Channels**: Support up to 8 slots (0 public, 1-7 custom). Create by entering slot index, name, and 16-byte secret (explicitly configured); join via shared name/secret; leave by clearing slot. Broadcast messages (no ACKs for channels); no discovery/limits/admin features.
- **UI**: iMessage-like chat bubbles, timestamps, status indicators (queued, sending, sent, acknowledged, failed). Input field with send button.
- **Offline Handling**: Up to 10 message queuing; user-visible indicators; long-press to delete queued messages. MeshCore BLE firmware will use push notifications to notify the app of incoming messages (no app polling). Auto-message fetching when notifications received via MeshCore firmware push notification.
- No attachments or binary data.

### 3.3 Contact Management
- **Discovery**: Manual advert send (Zero Hop for nearby, Flood for network-wide); auto-scan and add incoming adverts (toggle for confirmation). Advertisements contain public key (32 bytes), name, location (optional), and path information. Path discovery with multi-hop routing and trace routing.
- **Sync**: Contact synchronization with timestamp watermarking to reduce payload on repeated syncs (only fetch contacts modified since last sync).
- **List**: Searchable, editable (delete); store name, public key (32 bytes), contact type (CHAT/REPEATER/ROOM), location (if shared), path length/data, last advertisement timestamp.
- Public keys retrieved from device/protocol; no app-generated keys.

### 3.4 Device Configuration
- **Companion Radio**:
  - Radio params: Frequency, Bandwidth, Spreading Factor, Coding Rate, Transmit Power (pickers/sliders).
  - Public info: Name, public key, location (toggle sharing in adverts).
- **Remote Repeater**:
  - Telemetry: Battery, stats (RSS, SNR, Noise Floor, Packets Sent/Received).
  - Edit: Name, position (via map pin), public key copy, radio params, auto-clock set from iPhone.
  - Controls: Advert settings/send, guest/admin passwords, reboot. Access Control List (ACL) permission management for repeaters.
- UI: Dedicated settings tab; changes sent via protocol commands.

### 3.8 Firmware-Specific Capabilities
- **Telemetry Modes**: Base, location, and environmental telemetry configuration
- **Custom Variables**: Key-value storage and retrieval on devices
- **Trace Packets**: Route testing and SNR mapping
- **Binary Protocol**: Extended binary commands for device interaction

### 3.5 Integrations
- **Notifications**: Incoming messages, low battery warnings, new contacts. Actionable (e.g., quick reply); toggles in settings.
- **Location Services & Map Integration**:
   - **Map Tab**: Dedicated tab with MapKit integration for contact location display
   - **Contact Discovery**: Real-time display of contacts on map with location sharing information
   - **Type-Based Markers**: Different visual indicators for CHAT, REPEATER, and ROOM contact types
   - **Caching**: 30-second cache validity with periodic updates
   - **User Interaction Handling**: Background data loading with foreground interaction detection
   - **Auto-Centering**: Automatic map centering on contact locations with viewport management
   - **Performance**: Optimized annotation updates, loading states, and coordinate handling. Attribute-based event filtering for subscriptions.
   - **Location Privacy**: Opt-in only; explicit permission request. Location sharing toggle in settings.

### 3.6 Settings and Data Management
- **Toggles**: Auto-add contacts, notification types (message notifications, low battery warnings).
- **Data Storage**: On-device only via SwiftData; no cloud sync. Per-device database isolation using public key as identifier.
- **SwiftData Models**:
  - `Device`: Public key (unique), name, firmware version, radio parameters, location, relationships to contacts/messages/channels
  - `Contact`: Public key (unique), name, type (CHAT/REPEATER/ROOM), location, path info, last advertisement timestamp
  - `Message`: ID, text (max 160 bytes), timestamps, delivery status, ACK code, retry tracking, SNR/path metadata, relationships to device/contact/channel
  - `Channel`: Slot index (0-7), name, secret (16 bytes for non-public), creation/last message dates
- **Error Handling**: In-app alerts for protocol errors with specific error codes and recovery strategies, connection failures, low battery warnings. Connection auto-reconnect with exponential backoff and configurable limits.

### 3.7 UI/UX Guidelines
- **Overall Design**: Signal-inspired clean, privacy-focused design with iOS-native elements (e.g., Liquid Glass for translucent UI effects).
- **Messaging Interface**:
  - iMessage-style bubbles with different colors for sent (blue) vs. received (gray)
  - Real-time delivery status text under messages (like iMessage)
  - Message timestamps and metadata (SNR for received messages, RTT for acknowledged) available in a long-press "Details" menu
  - Reply indicator UI (long-press to bring up context menu, tap reply. Replies show quoted text)
  - Context menu for actions (reply, details, delete queued messages)
- **Navigation**: TabView with 4 tabs (Chats, Contacts, Map, Settings) - Map tab provides contact discovery and location visualization
- **Adaptive Layout**: Universal app for iPhone/iPad/macOS (use size classes for layouts)
- **Accessibility**: Standard iOS support (VoiceOver, dynamic type, sufficient contrast ratios)
- **Notifications**: Banner-style with quick reply action, visible even in foreground

## 4. User Flows
### 4.1 Onboarding Flow
1. **Welcome Screen**: App icon, feature highlights (off-grid messaging, BLE mesh, contact discovery, location sharing)
2. **Permissions Screen**: Request Bluetooth (auto by triggering a bluetooth scan), Notifications (alert/sound/badge), Location (when-in-use). Must grant all to continue.
3. **Device Scanning**: Auto-scan for MeshCore devices advertising Nordic UART Service. Display list with device name and RSSI.
4. **Device Pairing**: Select device, enter PIN, connect. Perform protocol handshake (`send_device_query()`, `send_appstart()`).
5. **Complete**: Save device to database, mark as active, initialize services (MessageService, AdvertisementService, ChannelService, MessagePollingService).
6. **Home**: Navigate to main interface with 4 tabs (Chats, Contacts, Map, Settings).

### 4.2 Messaging Flow
**Sending a Direct Message**:
1. Navigate to Chats tab > Select chat > Chat view opens
1a. Or navigat to Contacts tab > Select contact > Select Message > Chat view opens
2. Type message (max 160 bytes) in input field > Tap send button
3. Message status updates: Queued → Sending (retry up to 3x with exponential backoff) → Sent (ACK code received) → Acknowledged (confirmation from recipient)
4. If all direct attempts fail, automatic fallback to flood mode
5. Long-press message for context menu (Reply, Delete if queued)

**Receiving a Message**:
1. BLE RX notification received (PUSH_CODE_MSG_WAITING) or sync on BLE reconnection
2. CMD_SYNC_NEXT_MESSAGE retrieves queued messages from device
3. Parse incoming message (sender public key prefix, timestamp, text, SNR, path length)
4. Match sender to contact (or create "Unknown" entry)
5. Insert message into database, update UI
6. Trigger local notification if app is backgrounded
7. User taps notification > Opens chat view scrolled to the message

### 4.3 Configuration Flow
**Radio Configuration**:
1. Settings tab > Tap connected device > Radio Configuration
2. Adjust parameters using sliders/pickers:
   - Frequency: 902-928 MHz (US ISM band), 0.125 MHz steps
   - Bandwidth: 125/250/500 kHz
   - Spreading Factor: SF7-SF12 (higher = longer range, slower speed)
   - Coding Rate: 4/5, 4/6, 4/7, 4/8
   - TX Power: 2-20 dBm (higher = better range, more battery drain)
3. Save button enabled when changes detected
4. Tap Save > Send CMD_SET_RADIO_PARAMS and CMD_SET_RADIO_TX_POWER
5. Await RESP_CODE_OK or display error alert
6. Update local device model in database on success

**Advertisement Configuration**:
1. Contacts tab > Tap advertisement button (antenna icon)
2. Choose range: Zero Hop (nearby only) or Flood (network-wide)
3. Tap Send > CMD_SEND_SELF_ADVERT with flood flag
4. Success feedback, then automatic contact sync triggered by receiving devices

## 5. Technical Requirements
### 5.1 Platform and Compatibility
- **Minimum Deployment**: iOS 18.0
- **Target**: iOS 26.1 with modern APIs
- **Swift Version**: 6.1 with strict concurrency checking (async/await, actors, Sendable, @MainActor isolation)
- **Universal binary** for iPhone/iPad/macOS Catalyst
- **Frameworks**:
   - SwiftUI (UI layer)
   - CoreBluetooth (BLE transport with notifications)
   - SwiftData (persistence layer with relationships)
   - MapKit/CoreLocation (location services and mapping)
   - UserNotifications (local notifications with actions)
   - CryptoKit (SHA-256 hashing for channel secrets)
   - OSLog (structured logging)
- **Project Management**: XcodeGen for reproducible project generation from `project.yml`; set up with SwiftData and Swift Testing; `.xcodeproj` excluded from version control
- **Zero third-party dependencies** (100% native Apple frameworks)

### 5.2 Architecture
- **Project Structure**:
  - `PocketMesh` (app target)
  - `PocketMeshKit` (framework target for business logic)
   - `PocketMeshTests` (unit test target with mock MeshCore BLE device)
- **Architecture Layers**:
   1. BLE Transport Layer: CoreBluetooth wrapper with characteristic notifications and state restoration
   2. Protocol Layer: Command/response encoding per Companion Radio Protocol with error handling
   3. Data Layer: SwiftData models with relationships and per-device isolation
   4. Repository Layer: Additional data access abstraction for separation of concerns
   5. Service Layer: Business logic for messaging, contacts, channels with caching
   6. UI Layer: SwiftUI views with optimizations and loading states
- **Key Design Principles**:
   - BLE notifications over polling (use `setNotifyValue` for efficiency)
   - Per-device isolation: Database scoped by device public key
   - Strict Swift 6.1 concurrency: All code concurrency-safe with Sendable types, actor isolation for shared state, @MainActor for UI updates
   - Async/await throughout with structured concurrency (TaskGroups, cancellation)
   - Background BLE with state preservation/restoration
   - Caching mechanisms
   - Repository pattern for data access abstraction
   - User interaction detection for responsive UI updates
   - Error handling with user-friendly messages

### 5.3 Protocol Integration
- **Follow Companion Radio Protocol doc strictly**
- **BLE Service**: Nordic UART Service (UUID: `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`)
  - TX Characteristic: `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` (write)
  - RX Characteristic: `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` (notify)
- **Frame Structure**: Single-byte command code + payload (BLE transport uses characteristic values as complete frames)
- **Supported Commands**: Device Query, App Start, Send Text Message, Send Channel Message, Get Contacts, Sync Next Message, Set Radio Params, Send Advertisement, and more
- **Extensibility**: Modular handlers for commands to add features easily

### 5.4 Performance
- Responsive BLE connections; handle poor signals with retries and exponential backoff
- Efficient SwiftData queries for large message histories (10k+ messages tested)
- Background modes: `bluetooth-central` for persistent connection
- State restoration for reconnection after app termination
- Caching strategies
- Connection management with `setNotifyValue` for RX characteristic notifications
- Notification-based message reception without polling

## 6. Non-Functional Requirements
### 6.1 Security and Privacy
- **Authentication**: PIN-based BLE device pairing per protocol. Default PIN: 123456, configurable on device. PIN sent during initial handshake for PUSH_CODE_LOGIN_SUCCESS/FAIL validation.
- **Data Storage**: On-device only via SwiftData; no cloud sync. User data never shared externally. Per-device database isolation prevents data leakage between devices.
- **Location Privacy**: Opt-in only; explicit permission request. Location sharing toggle in settings. No background location tracking (only when-in-use authorization).
- **Communication Security**: Protocol-level encryption per MeshCore specification. No additional app-level encryption (to avoid duplication).
- **Background Modes**: `bluetooth-central` enabled for persistent BLE connection. State preservation/restoration for reconnection after termination.
- **Compliance**: US-focused initially; defer GDPR/CCPA to later phases.

### 6.2 Reliability
- **Offline Handling**:
  - Messages queue indefinitely when device disconnected
  - User-visible queue status with count
  - Automatic send on reconnection
  - BLE connection monitoring with automatic reconnection attempts
- **Error Recovery**:
  - User-friendly alerts for protocol errors with specific error codes
  - Automatic reconnection with exponential backoff on BLE disconnection
  - Message retry: 3 direct attempts with exponential backoff (1s, 2s, 4s), then flood mode
  - State restoration after app termination via CoreBluetooth state preservation
- **Graceful Degradation**:
  - Display degraded mode indicators when connection quality poor
  - Show SNR/path length metadata for received messages to indicate signal quality
  - Timeout handling for commands (default: 30 seconds for ACK)

### 6.3 Usability
- Intuitive for casual users; minimal steps to message.
- **Testing Strategy**: Comprehensive Test Suite Plan with Mock BLE Device
   - **Mock MeshCore BLE Device**: Swift-based mock peripheral emulating real MeshCore firmware (based on MeshCore-firmware-example), implementing Nordic UART Service with TX/RX characteristics, command/response handling per Companion Radio Protocol
   - **Protocol Compliance Tests**: 100% protocol compliance verification using mock device for all commands (Device Query, App Start, Send Text Message, Get Contacts, Set Radio Params, etc.), response codes, push notifications, and error handling
   - **Unit Tests**: Coverage for protocol frame encoding/decoding, channel secret hashing, message retry logic, coordinate encoding, device info parsing
   - **Integration Tests**: Full BLE connection flows using mock device, message send/receive cycles, contact sync, state restoration, offline queuing
   - **Performance Tests**: Message encoding throughput, contact sync speed, database query performance with large datasets
   - **Hardware Testing**: Checklist for physical device testing with 2-3 MeshCore radios in various network configurations (direct, multi-hop, degraded signal)
   - **Test Coverage**: Target >80% code coverage with comprehensive edge case testing (disconnections, offline queueing, multiple devices, protocol errors)
   - **Test Infrastructure**: Automated test suites with mock BLE device, performance benchmarks, and hardware validation procedures

## 7. Implementation Plan

The implementation will be divided into 10 phases across two parts:

### Part 1: Foundation & Core Features (Phases 1-5)
1. **Project Setup & BLE Foundation**: XcodeGen configuration, advanced BLE manager, device discovery/connection, PIN authentication
2. **Data Models & Persistence**: SwiftData models (Device, Contact, Message, Channel), relationships, per-device isolation
3. **Core Messaging**: Send/receive direct messages, ACK tracking, retry logic with exponential backoff, delivery status
4. **Contact Management**: Advertisement service, contact discovery/sync with timestamp watermarking, location sharing
5. **Channel Support**: Channel creation with SHA-256 secret hashing, broadcast messaging, slot management (0-7)

### Part 2: UI, Configuration & Polish (Phases 6-10)
6. **UI - Onboarding & Settings**: Welcome flow, permissions, device scanning/pairing, settings screens
7. **UI - Messaging & Contacts**: iMessage-style chat interface, contact list with search, delivery status indicators
8. **Device Configuration**: Radio parameter configuration UI, battery/storage telemetry, companion and repeater settings
9. **Notifications & Background BLE**: Notifications for messages, background BLE modes, state preservation/restoration
10. **Testing & Refinement**: Mock MeshCore BLE device creation, protocol compliance tests, performance optimization, hardware validation checklist

**Target Status**: Production-ready iOS application with test coverage and App Store submission readiness.

### 7.7 Technical Considerations
- **Protocol Documentation**: Reference official MeshCore GitHub wiki as source of truth for all command implementations
- **Version Dependencies**: Specify minimum MeshCore firmware and library version requirements for compatibility
- **Hardware Testing**: Add specific device models and firmware versions for testing
- **Connection Management**: BLE uses `setNotifyValue` for RX characteristic notifications to eliminate polling

## 8. Current Implementation Status

### **Current Development Status**
PocketMesh is in **early development** with planning completed for implementation:

#### **Planned Implementation**
- **Target: 5,000+ lines of Swift code** across multiple Swift files
- **XcodeGen configuration** with proper entitlements
- **iOS 18.0+ targeting** with iOS 26.1 optimization
- **Universal binary** for iPhone/iPad/macOS Catalyst

#### **Feature Implementation Plan**
- **Core messaging system** with retry logic and delivery tracking
- **Map tab** with contact discovery and caching
- **BLE integration** with state restoration
- **Device configuration** for radios and repeaters
- **UI** with 4-tab architecture

#### **Quality Assurance Goals**
- **Comprehensive test suite** with mock BLE device targeting >80% code coverage
- **Protocol compliance** verification for 100% MeshCore protocol adherence
- **Optimizations** including caching and user interaction detection
- **Hardware testing checklist** for validation
- **App Store submission readiness** with proper entitlements and configurations

#### **Technical Architecture**
- **Modern Swift 6.1** with strict concurrency checking and structured concurrency patterns
- **Architecture** with separation of concerns
- **Mock BLE Device** for protocol compliance testing
- **Error Handling** with user-friendly messages
- **Optimizations** throughout the application
- **Documentation** and code comments

## 9. Success Metrics and Launch Plan
- **Metrics**: User retention (e.g., repeat messaging sessions), crash-free rate, App Store ratings.
- **Launch**: Test via TestFlight; submit to App Store. No monetization; free app.
- **Risks**: Protocol changes (monitor MeshCore GitHub wiki); BLE compatibility issues (test with physical hardware).

## 10. Build and Development Commands
- **Generate Project**: `xcodegen generate`
- **Build**: `xcodebuild -project PocketMesh.xcodeproj -scheme PocketMesh build`
- **Test**: `xcodebuild test -project PocketMesh.xcodeproj -scheme PocketMesh`
- **Coverage**: `xcodebuild test -enableCodeCoverage YES`

The application is in early development.
