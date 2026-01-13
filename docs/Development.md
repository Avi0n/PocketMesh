# Development Documentation

This guide provides information for developers who want to contribute to the PocketMesh project.

## Getting Started

### Prerequisites

- **Xcode 26.0+** (as specified in `project.yml`)
- **Swift 6.2+**
- **XcodeGen**: Required for project file generation.
  ```bash
  brew install xcodegen
  ```
- **xcsift** (optional): Transforms verbose Xcode output into concise JSON.
  ```bash
  brew install xcsift
  ```

Note: SwiftLint and SwiftFormat are not currently configured for this project but may be added optionally. See the "Linting and Formatting" section below.

### Project Setup

1. **Clone the repository**.
2. **Generate the Xcode project**:
   ```bash
   xcodegen generate
   ```
3. **Open `PocketMesh.xcodeproj`**.

## Building the Project

PocketMesh uses a modular structure with Swift Packages:

- `MeshCore`: The protocol framework.
- `PocketMeshServices`: The business logic framework.
- `PocketMesh`: The main iOS application.

### Command Line Build

```bash
xcodebuild -project PocketMesh.xcodeproj \
  -scheme PocketMesh \
  -destination "platform=iOS Simulator,name=iPhone 16 Pro" \
  build
```

### Using xcsift

xcsift transforms verbose Xcode output into concise, structured JSON:

```bash
# Basic build with JSON output
xcodebuild build 2>&1 | xcsift

# Show detailed warnings
xcodebuild build 2>&1 | xcsift --warnings

# Quiet mode (suppress output on success)
xcodebuild build 2>&1 | xcsift --quiet

# Treat warnings as errors
xcodebuild build 2>&1 | xcsift --Werror

# TOON format (token-efficient for LLMs)
xcodebuild build 2>&1 | xcsift --format toon
```

## Testing Strategy

PocketMesh emphasizes comprehensive testing at all layers.

### Unit Tests

- **MeshCoreTests**: Tests packet building, parsing, LPP decoding, and session state.
- **PocketMeshServicesTests**: Tests business logic services, actor isolation, and persistence.
- **PocketMeshTests**: Tests app state and view models.

### Running Tests

```bash
# Run all tests
xcodebuild test -project PocketMesh.xcodeproj \
  -scheme PocketMesh \
  -destination "platform=iOS Simulator,name=iPhone 16 Pro"

# With xcsift for concise output
xcodebuild test 2>&1 | xcsift

# With code coverage
xcodebuild test -enableCodeCoverage YES 2>&1 | xcsift --coverage
```

### Test Infrastructure

#### MockTransport

For testing without physical hardware:

```swift
let mock = MockTransport()
let session = MeshCoreSession(transport: mock)

// Simulate device response
await mock.simulateReceive(testPacket)

// Helper methods for common responses
await mock.simulateOK()
await mock.simulateError(code: 0x01)

// Verify sent data (sentData is an array)
let sent = await mock.sentData
#expect(sent.count > 0)
#expect(sent.last == expectedPacket)

// Clear sent data history
await mock.clearSentData()
```

#### MockPersistenceStore

For testing services without SwiftData:

```swift
let mockStore = MockPersistenceStore()
let service = MessageService(session: session, dataStore: mockStore)

// Verify persistence calls
#expect(mockStore.savedMessages.count == 1)
```

### Swift Testing Framework

We use the modern **Swift Testing** framework (`@Test`, `@Suite`, `#expect`) for all new tests:

```swift
@Suite("MessageService Tests")
struct MessageServiceTests {
    @Test("Send message creates pending message")
    func sendMessageCreatesAck() async throws {
        let service = MessageService(...)
        let message = try await service.sendDirectMessage(text: "Hello", to: contact)

        #expect(message.status == .pending)
    }
}
```

## Coding Standards & Conventions

### Swift 6 Concurrency

- **Strict Concurrency**: The project is compiled with `SWIFT_STRICT_CONCURRENCY: complete`.
- **Actor Isolation**: Use actors for shared state and services.
- **MainActor**: All UI-related code must be isolated to the `@MainActor`.
- **Sendable**: Ensure all data types passed between actors conform to `Sendable`.

### Naming Conventions

- **Services**: Suffix with `Service` (e.g., `MessageService`).
- **Data Objects**: Suffix with `DTO` when used for cross-boundary data transfer (e.g., `MessageDTO`).
- **Persistence**: Use `PersistenceStore` (alias: `DataStore`) for data access.
- **ViewModels**: Suffix with `ViewModel` (e.g., `ChatViewModel`).

### SwiftUI Conventions

- Use `@Observable` classes, not `ObservableObject`.
- Use `foregroundStyle()` not `foregroundColor()`.
- Use `NavigationStack` not `NavigationView`.
- Use `Tab` API not `tabItem()`.
- Prefer `Button` over `onTapGesture()`.

### Persistence

- **SwiftData**: All persistence should use SwiftData models defined in `PocketMeshServices`.
- **No Direct Store Access**: Services should interact with data via the `PersistenceStore` actor.

## Linting and Formatting

### Optional Tools

The project does not currently have SwiftLint or SwiftFormat configured. If you wish to use these tools:

**SwiftLint** (optional):
```bash
brew install swiftlint
swiftlint lint
```

**SwiftFormat** (optional):
```bash
brew install swiftformat
swiftformat .
```

### Pre-Commit Workflow

Before committing:

```bash
# Build and test
xcodebuild test 2>&1 | xcsift --Werror
```

## Documentation (DocC)

The project uses DocC for inline documentation. All public APIs should be documented using standard Swift documentation comments.

To generate the documentation site:

```bash
xcodebuild docbuild -scheme MeshCore
```

## Project Dependencies

### DataScoutCompanion

The project integrates [DataScoutCompanion](https://github.com/alex566/DataScoutCompanion) for database debugging via the DataScout macOS application. This dependency is configured in `project.yml`:

```yaml
packages:
  DataScoutCompanion:
    url: https://github.com/alex566/DataScoutCompanion.git
    from: "0.3.0"
```

Required Info.plist keys for DataScout integration:

```xml
<key>NSBonjourServices</key>
<array>
    <string>_datascout-sync._tcp</string>
</array>
<key>NSLocalNetworkUsageDescription</key>
<string>PocketMesh uses the local network to enable database debugging with DataScout.</string>
```

### AccessorySetupKit

For iOS 18+ device pairing, the project uses AccessorySetupKit. The `AccessorySetupKitService` in PocketMeshServices handles the pairing flow.

Required Info.plist keys:

```xml
<key>NSAccessorySetupKitSupports</key>
<array>
    <string>Bluetooth</string>
</array>
<key>NSAccessorySetupBluetoothServices</key>
<array>
    <string>6E400001-B5A3-F393-E0A9-E50E24DCCA9E</string>
</array>
<key>NSAccessorySetupBluetoothNames</key>
<array>
    <string>MeshCore-</string>
</array>
```

### Bluetooth Requirements

The app requires Bluetooth permissions and background mode:

```xml
<key>NSBluetoothPeripheralUsageDescription</key>
<string>PocketMesh uses Bluetooth to connect to MeshCore radio devices for mesh messaging.</string>
<key>UIBackgroundModes</key>
<array>
    <string>bluetooth-central</string>
</array>
```

## BLE Transport Architecture

- **MeshCore/Transport/BLETransport.swift**: Base BLE transport protocol implementation
- **PocketMeshServices/Transport/iOSBLETransport.swift**: iOS-specific BLE transport with CoreBluetooth integration
- **PocketMeshServices/Transport/BLEStateMachine.swift**: Connection state management
- **PocketMeshServices/Services/AccessorySetupKitService.swift**: iOS 18+ pairing flow

## Further Reading

- [Architecture Overview](Architecture.md)
- [MeshCore API Reference](api/MeshCore.md)
- [PocketMeshServices API Reference](api/PocketMeshServices.md)
- [BLE Transport Guide](guides/BLE_Transport.md)
