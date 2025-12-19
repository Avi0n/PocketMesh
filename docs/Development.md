# Development Documentation

This guide provides information for developers who want to contribute to the PocketMesh project.

## Getting Started

### Prerequisites

- **Xcode 16.1+**
- **Swift 6.0+**
- **XcodeGen**: Used for project file generation.
  ```bash
  brew install xcodegen
  ```

### Project Setup

1.  **Clone the repository**.
2.  **Generate the Xcode project**:
    ```bash
    xcodegen generate
    ```
3.  **Open `PocketMesh.xcodeproj`**.

## Building the Project

PocketMesh uses a modular structure with Swift Packages:
-   `MeshCore`: The protocol framework.
-   `PocketMeshServices`: The business logic framework.
-   `PocketMesh`: The main iOS application.

To build from the command line:
```bash
xcodebuild -project PocketMesh.xcodeproj -scheme PocketMesh build
```

## Testing Strategy

PocketMesh emphasizes comprehensive testing at all layers.

### Unit Tests

-   **MeshCoreTests**: Tests packet building, parsing, LPP decoding, and session state.
-   **PocketMeshServicesTests**: Tests business logic services, actor isolation, and persistence.
-   **PocketMeshTests**: Tests app state and view models.

Run all tests:
```bash
xcodebuild test -project PocketMesh.xcodeproj -scheme PocketMesh
```

### Mocking

The project uses a `MockTransport` in the protocol layer and `MockPersistenceStore` in the service layer to enable deterministic testing without physical hardware.

### Swift Testing Framework

We use the modern **Swift Testing** framework (`@Test`, `@Suite`, `#expect`) for all new tests.

## Coding Standards & Conventions

### Concurrency (Swift 6)

-   **Strict Concurrency**: The project is compiled with `SWIFT_STRICT_CONCURRENCY: complete`.
-   **Actor Isolation**: Use actors for shared state and services.
-   **MainActor**: All UI-related code must be isolated to the `@MainActor`.
-   **Sendable**: Ensure all data types passed between actors conform to `Sendable`.

### Naming Conventions

-   **Services**: Suffix with `Service` (e.g., `MessageService`).
-   **Data Objects**: Suffix with `DTO` when used for cross-boundary data transfer (e.g., `MessageDTO`).
-   **Persistence**: Use `PersistenceStore` for data access.

### Persistence

-   **SwiftData**: All persistence should use SwiftData models defined in `PocketMeshServices`.
-   **No Direct Store Access**: Services should interact with data via the `PersistenceStore` actor.

## Documentation (DocC)

The project uses DocC for inline documentation. All public APIs should be documented using standard Swift documentation comments.

To generate the documentation site:
```bash
xcodebuild docbuild -scheme MeshCore
```

## Continuous Integration

CI pipelines should run the following on every PR:
1.  `xcodegen generate` to ensure project file validity.
2.  `xcodebuild build` for the main scheme.
3.  `xcodebuild test` for all test targets.
