# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PocketMesh is an early-stage iOS application in development for off-grid messaging using MeshCore BLE (Bluetooth Low Energy) devices. It's a native SwiftUI app that enables communication through mesh networks when cellular service is unavailable.

## Development Commands

### Project Setup
```bash
# Generate Xcode project from configuration
xcodegen generate

# Open project in Xcode
open PocketMesh.xcodeproj
```

### Build and Test
```bash
# Build the project
xcodebuild -project PocketMesh.xcodeproj -scheme PocketMesh build

# Run unit tests
xcodebuild test -project PocketMesh.xcodeproj -scheme PocketMesh

# Run tests with code coverage
xcodebuild test -enableCodeCoverage YES -project PocketMesh.xcodeproj -scheme PocketMesh -destination 'platform=iOS Simulator,name=iPhone 17'

# Build for iOS Simulator
xcodebuild -project PocketMesh.xcodeproj -scheme PocketMesh -destination 'platform=iOS Simulator,name=iPhone 17' build
```

### Development Workflow
- Use Xcode 16.0+ for development
- The project uses XcodeGen for project generation from `project.yml`
- Target iOS 17.0+ with Swift 6.0
- IMPORTANT: Swift 6.0 strict concurrency: Protocol requirements must match implementation's actor isolation
- No third-party dependencies - uses only Apple frameworks
- Always use proper build commands: xcodebuild instead of swiftc -parse for accurate verification
- Project usese Xcodegen. Use Xcodegen after adding new files to the project.
- After finishing an implementation phase, run the following commands before running automated tests:
  - `swiftlint --fix`
- When building, use a destination of "-destination 'platform=iOS Simulator,name=iPhone 17'"

## Architecture Overview

### Project Structure
```
PocketMesh/
├── PocketMesh/                    # Main App Target
│   ├── App/                      # App lifecycle and coordination
│   ├── Views/                    # SwiftUI Views (UI Layer)
│   │   ├── Chats/               # Messaging interfaces
│   │   ├── Contacts/            # Contact management
│   │   ├── Map/                 # Location and mapping
│   │   ├── Onboarding/          # First-time user experience
│   │   └── Settings/            # Device configuration
│   ├── BLE/                     # Bluetooth integration
│   ├── Models/                  # SwiftData models
│   ├── Persistence/             # Database controllers
│   ├── Protocol/                # MeshCore protocol handling
│   └── Services/                # Business logic services
├── PocketMeshKit/               # Framework Target (Shared Code)
│   ├── BLE/                     # BLE management
│   ├── Extensions/              # Swift extensions
│   ├── Models/                  # Core data models
│   ├── Persistence/             # Repository implementations
│   ├── Protocol/                # Protocol implementation
│   └── Services/                # Core business services
└── PocketMeshTests/             # Unit Tests
```

### Key Architecture Patterns

**1. AppCoordinator Pattern**
- Central coordinator managing app state, BLE connections, and service initialization
- Handles onboarding flow completion and device connection restoration
- Manages service lifecycle (MessageService, AdvertisementService, ChannelService, etc.)

**2. Service Layer Architecture**
- **MessageService**: Handles direct messaging and channel communications with retry logic
- **AdvertisementService**: Manages device advertising, discovery, and contact processing
- **ChannelService**: Handles group channel operations
- **MessagePollingService**: Background polling for new messages
- **TelemetryService**: Device telemetry and monitoring
- **NotificationService**: Local notification management

**3. Protocol Implementation**
- **MeshCoreProtocol**: Actor-based protocol handler for MeshCore devices
- **ProtocolFrame**: Binary protocol encoding/decoding
- Supports command/response pattern with async/await
- Handles push notifications and multi-frame responses

**4. Data Models (SwiftData)**
- **Device**: Represents MeshCore radio devices with radio parameters
- **Contact**: User contacts with public keys and approval status
- **Message**: Direct and channel messages with delivery tracking
- **Channel**: Group communication channels
- **ACLEntry**: Access control list entries

### Key Technical Details

**BLE Integration**
- Uses Nordic UART Service (UUID: `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`)
- TX Characteristic: `6E400002-B5A3-F393-E0A9-E50E24DCCA9E` (write)
- RX Characteristic: `6E400003-B5A3-F393-E0A9-E50E24DCCA9E` (notify)
- Implements state preservation/restoration for background operation

**Companion Radio Protocol**
- Single-byte command codes with payloads
- Follows MeshCore Companion Radio Protocol specification
- Commands include device query, messaging, contact sync, radio configuration
- Push notifications for advertisements (PUSH_NEW_ADVERT) and messages

**Data Persistence**
- SwiftData with per-device isolation using public keys
- Repository pattern for clean data access abstraction
- Smart caching mechanisms for performance optimization
- Contact approval workflow with pending/approved states

**Concurrency Model**
- Swift 6.0 with async/await throughout
- Actor-based isolation for protocol handling
- MainActor for UI updates and coordination

## Development Guidelines

### Code Organization
- Follow MVVM pattern with SwiftUI
- Use existing service layers rather than direct BLE/protocol calls
- Maintain per-device data isolation in SwiftData
- Use named constants instead of hardcoded values

### Testing
- Unit tests in PocketMeshTests target
- Hardware testing requires physical MeshCore devices
- Performance testing for protocol operations
- Multi-device testing for mesh network validation
- Comprehensive test coverage for contact discovery and approval workflows
- Mock BLEManager for protocol testing without hardware

### Performance Considerations
- Message encoding throughput optimized for large datasets
- Contact sync speed optimized with timestamp watermarking
- Database query performance tested with 10k+ messages
- Smart caching mechanisms for contact discovery and map integration
- Background loading with user interaction detection

### Error Handling
- Implement specific error types for different failure modes
- Use structured logging with OSLog
- Provide user-friendly error messages
- Handle BLE disconnections gracefully with automatic reconnection

## Important Implementation Notes

- **Adhere to MeshCore protocols/commands**: Example MeshCore radio firmware can be found here: @MeshCore-firmware-examples/companion_radio
- **No third-party dependencies**: Uses only Apple frameworks
- **Background BLE**: Requires `bluetooth-central` background mode
- **Location privacy**: Opt-in only with when-in-use authorization
- **Security**: PIN-based authentication per protocol specification
- **Performance**: Optimized for large message histories (10k+ messages tested)
- **Universal app**: Supports iPhone/iPad/macOS via Catalyst
- **Swift 6.0 Strict Concurrency**: Protocol requirements must match implementation's actor isolation
- **XcodeGen**: Use XcodeGen after adding new files to the project
- **Code Quality**: Run SwiftLint and SwiftFormat before automated tests

### BLE Testing Without Hardware
The project includes comprehensive mock implementations:
- MockBLEManager for protocol testing
- MockCompanionRadio for device simulation
- MockRadioProtocols for testing various device behaviors
- Use these mocks for unit testing when physical hardware is unavailable

## Build Configuration

### iOS Target
- **Minimum iOS**: 17.0
- **Target iOS**: Latest (optimized for iOS 26)
- **Swift Version**: 6.0 with strict concurrency
- **Xcode Version**: 16.0+
- **Architecture**: SwiftData + SwiftUI + CoreBluetooth

### Project Management
- **XcodeGen**: Project generation from `project.yml`
- **Dependencies**: Zero third-party dependencies
- **Testing**: Comprehensive unit and integration tests
- **Code Coverage**: >80% achieved across all modules

# Using OpenCode CLI for Large Codebase Analysis

When analyzing large codebases or multiple files that might exceed context limits, use the OpenCode CLI with its massive context window. Use `opencode run` to leverage OpenCode's large context capacity.

## File and Directory Inclusion Syntax

Use the `@` syntax to include files and directories in your OpenCode prompts. The paths should be relative to WHERE you run the OpenCode command:

### Examples:

**Single file analysis:**

`opencode run` "Explain this file's purpose and structure @src/main.py"

**Multiple files:**

`opencode run` "Analyze the dependencies used in the code @package.json @src/index.js"

**Entire directory:**

`opencode run` "Summarize the architecture of this codebase @src/"

**Multiple directories:**

`opencode run` "Analyze test coverage for the source code @src/ @tests/"

**Current directory and subdirectories:**

`opencode run` "Give me an overview of this entire project @./"

**Entire project**

`opencode run` "Analyze the project structure and dependencies"

## Implementation Verification Examples

Check if a feature is implemented:

`opencode run` "@src/ @lib/ Has dark mode been implemented in this codebase? Show me the relevant files and functions"

Verify authentication implementation:

`opencode run` "@src/ @middleware/ Is JWT authentication implemented? List all auth-related endpoints and middleware"

Check for specific patterns:
`opencode run`"@src/ Are there any React hooks that handle WebSocket connections? List them with file paths"

Verify error handling:
`opencode run` "@src/ @api/ Is proper error handling implemented for all API endpoints? Show examples of try-catch blocks"

Check for rate limiting:
`opencode run` "@backend/ @middleware/ Is rate limiting implemented for the API? Show the implementation details"

Verify caching strategy:
`opencode run` "@src/ @lib/ @services/ Is Redis caching implemented? List all cache-related functions and their usage"

Check for specific security measures:
`opencode run` "@src/ @api/ Are SQL injection protections implemented? Show how user inputs are sanitized"

Verify test coverage for features:
`opencode run` "@src/payment/ @tests/ Is the payment processing module fully tested? List all test cases"

## When to Use OpenCode CLI

Use `opencode run` when:
- Analyzing entire codebases or large directories
- Comparing multiple large files
- Need to understand project-wide patterns or architecture
- Current context window is insufficient for the task
- Working with files totaling more than 100KB
- Verifying if specific features, patterns, or security measures are implemented
- Checking for the presence of certain coding patterns across the entire codebase

## Important Notes

- Paths in `@` syntax are relative to your current working directory when invoking OpenCode
- The CLI will include file contents directly in the context
- No need for `--yolo` flag for read-only analysis
- OpenCode's context window can handle entire codebases that would overflow Claude's context
- When checking implementations, be specific about what you're looking for to get accurate results
