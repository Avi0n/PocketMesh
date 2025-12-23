# Development Documentation

This guide provides information for developers who want to contribute to the PocketMesh project.

## Getting Started

### Prerequisites

- **Xcode 16.1+**
- **Swift 6.2+**
- **XcodeGen**: Used for project file generation.
  ```bash
  brew install xcodegen
  ```
- **xcsift** (optional): Transforms verbose Xcode output into concise JSON.
  ```bash
  brew install xcsift
  ```
- **SwiftLint** (optional): Linting for Swift code style.
  ```bash
  brew install swiftlint
  ```
- **SwiftFormat** (optional): Automatic code formatting.
  ```bash
  brew install swiftformat
  ```

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
  -destination "platform=iOS Simulator,name=iPhone 16e" \
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
  -destination "platform=iOS Simulator,name=iPhone 16e"

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

// Inject test data
await mock.injectData(testPacket)

// Verify sent data
let sent = await mock.sentData
#expect(sent.contains(expectedPacket))
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
    @Test("Send message creates pending ACK")
    func sendMessageCreatesAck() async throws {
        let service = MessageService(...)
        let message = try await service.sendDirectMessage(text: "Hello", to: contact)

        #expect(message.status == .sending)
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

See `CLAUDE.md` for complete coding conventions.

### Persistence

- **SwiftData**: All persistence should use SwiftData models defined in `PocketMeshServices`.
- **No Direct Store Access**: Services should interact with data via the `PersistenceStore` actor.

## Linting and Formatting

### SwiftLint

Run SwiftLint to check for style issues:

```bash
swiftlint lint
```

Fix auto-correctable issues:

```bash
swiftlint lint --fix
```

### SwiftFormat

Run SwiftFormat to auto-format code:

```bash
swiftformat .
```

### Pre-Commit Workflow

Before committing:

```bash
# Format code
swiftformat .

# Check for lint issues
swiftlint lint

# Build and test
xcodebuild test 2>&1 | xcsift --Werror
```

## Documentation (DocC)

The project uses DocC for inline documentation. All public APIs should be documented using standard Swift documentation comments.

To generate the documentation site:

```bash
xcodebuild docbuild -scheme MeshCore
```

## Continuous Integration

CI pipelines should run the following on every PR:

1. `xcodegen generate` to ensure project file validity.
2. `swiftlint lint` for code style.
3. `xcodebuild build` for the main scheme.
4. `xcodebuild test` for all test targets.

## Further Reading

- [Architecture Overview](Architecture.md)
- [MeshCore API Reference](api/MeshCore.md)
- [PocketMeshServices API Reference](api/PocketMeshServices.md)
- [BLE Transport Guide](guides/BLE_Transport.md)
