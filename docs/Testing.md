# Testing

## Running Tests

### Xcode

Use the Test navigator (Cmd+6) or Cmd+U to run all tests.

### Command Line

```bash
# App-layer tests (PocketMeshTests)
xcodebuild test \
  -project PocketMesh.xcodeproj \
  -scheme PocketMesh \
  -destination "platform=iOS Simulator,name=iPhone 16e" \
  2>&1 | xcsift -f toon

# Services package tests
cd PocketMeshServices && swift test 2>&1 | xcsift -f toon

# MeshCore package tests
cd MeshCore && swift test 2>&1 | xcsift -f toon
```

Use `xcsift` to get structured output. Add `-c` for code coverage or `-w` for a detailed warnings list. See CLAUDE.md for the full flag reference.

## Test Targets

| Target | Package | Framework | Scope |
|--------|---------|-----------|-------|
| `PocketMeshTests` | Xcode project | Swift Testing | ViewModels, AppState, views, models, utilities |
| `PocketMeshServicesTests` | PocketMeshServices (SPM) | Swift Testing | Services, transport, persistence, connection management |
| `MeshCoreTests` | MeshCore (SPM) | Swift Testing + XCTest | Protocol parsing, crypto, transport codecs |

**Framework split**: Swift Testing (`@Suite`, `@Test`, `#expect`) is used throughout, except `MeshCoreTests/Validation/` and `MeshCoreTests/Protocol/` which use XCTest for byte-level protocol compatibility tests.

## Mock Patterns

Mocks are **protocol-based Swift actors** with a consistent structure:

```swift
public actor MockChannelService: ChannelServiceProtocol {
    // MARK: - Stubs
    public var stubbedChannels: [Channel] = []

    // MARK: - Recorded Invocations
    public private(set) var fetchChannelsInvocations: [Void] = []

    // MARK: - Protocol Methods
    public func fetchChannels() async throws -> [Channel] {
        fetchChannelsInvocations.append(())
        return stubbedChannels
    }

    // MARK: - Test Helpers
    public func reset() { ... }
}
```

- **Stubs** (`stubbedXxx`) provide configurable return values
- **Invocation arrays** (`xxxInvocations`) record every call for assertion
- **`reset()`** clears recorded state between tests
- Actor isolation provides thread safety under strict concurrency

Mocks live in `PocketMeshServicesTests/Mocks/` and `PocketMeshTests/Mock/`.

## ServiceContainer.forTesting()

Creates the full service graph backed by in-memory SwiftData storage:

```swift
let transport = SimulatorMockTransport()
let session = MeshCoreSession(transport: transport)
let container = try await ServiceContainer.forTesting(session: session)
```

- Uses `PersistenceStore.createContainer(inMemory: true)` for zero disk I/O
- `wired: true` (default) calls `wireServices()` to establish cross-service callbacks
- `wired: false` is used only in `ServiceContainerWiringTests` to test the wiring step itself
- `SimulatorMockTransport` is a production actor (`Simulator/SimulatorMockTransport.swift`) that satisfies `MeshTransport` with no-op operations

## Test Utilities

| Utility | Location | Purpose |
|---------|----------|---------|
| `MutableBox<T>` | `PocketMeshTests/Helpers/TestHelpers.swift` | Captures mutable values in async closures under strict concurrency |
| `DeviceDTO.testDevice()` | `PocketMeshServicesTests/Helpers/DeviceDTO+Testing.swift` | Factory with sensible defaults for building test fixtures |
| `SimulatorMockTransport` | `PocketMeshServices/.../Simulator/SimulatorMockTransport.swift` | No-op `MeshTransport` for creating sessions without hardware |
| `PythonReferenceBytes` | `MeshCoreTests/Fixtures/PythonReferenceBytes.swift` | Static byte arrays from the Python reference implementation |

## Conventions

- **`@MainActor` on test suites**: Any test interacting with `AppState` or `ConnectionManager` annotates the `@Suite` or `@Test` with `@MainActor`.
- **App-layer tests** instantiate `AppState()` directly without mock injection.
- **Service-layer tests** use `ServiceContainer.forTesting()` or inject individual mock actors.
- **MeshCore tests** are self-contained with no external dependencies.

## File Organization

```
PocketMeshTests/
├── AppState/          # AppState sub-object tests
├── Calculations/      # RF calculator, segment analysis
├── Extensions/        # Data extensions, battery info
├── Formatters/        # Message path formatting
├── Helpers/           # MutableBox and other test utilities
├── Mock/              # App-layer mocks
├── Models/            # Data model tests
├── Protocol/          # CLI response, LPP display
├── Services/          # Elevation, link preview, image detection
├── Utilities/         # Demo mode, mention utilities, scroll policies
├── ViewModels/        # ViewModel unit tests
└── Views/             # View-level logic tests

PocketMeshServicesTests/
├── Helpers/           # Test fixture builders
├── Mocks/             # Protocol-based mock actors
├── Models/            # DTO and connection model tests
├── Services/          # Per-service unit tests
├── Transport/         # BLE phase and state machine tests
└── (root)             # Connection manager, sync coordinator tests

MeshCoreTests/
├── Fixtures/          # Reference byte arrays
├── Protocol/          # PacketBuilder command tests (XCTest)
├── Session/           # Session timeout tests
├── Transport/         # WiFi codec and transport tests
└── Validation/        # Byte-level protocol tests (XCTest)
```
