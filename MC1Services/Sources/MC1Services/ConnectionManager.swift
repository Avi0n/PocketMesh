@preconcurrency import CoreBluetooth
import Foundation
import SwiftData
import MeshCore
import OSLog

/// Connection state for the mesh device
public enum ConnectionState: Sendable {
    case disconnected
    case connecting
    case connected
    case ready
}

/// Transport type for the mesh connection
public enum TransportType: Sendable {
    case bluetooth
    case wifi
}

/// Errors that can occur during connection operations
public enum ConnectionError: LocalizedError {
    case connectionFailed(String)
    case deviceNotFound
    case notConnected
    case initializationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .deviceNotFound:
            return "Device not found"
        case .notConnected:
            return "Not connected to device"
        case .initializationFailed(let reason):
            return "Device initialization failed: \(reason)"
        }
    }
}

/// Errors that can occur during device pairing
public enum PairingError: LocalizedError {
    /// ASK pairing succeeded but BLE connection failed (e.g., wrong PIN)
    case connectionFailed(deviceID: UUID, underlying: Error)
    /// ASK pairing succeeded but device is connected to another app
    case deviceConnectedToOtherApp(deviceID: UUID)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(_, let underlying):
            return "Connection failed: \(underlying.localizedDescription)"
        case .deviceConnectedToOtherApp:
            return "Device is connected to another app."
        }
    }

    /// The device ID that failed to connect (for recovery UI)
    public var deviceID: UUID? {
        switch self {
        case .connectionFailed(let deviceID, _):
            return deviceID
        case .deviceConnectedToOtherApp(let deviceID):
            return deviceID
        }
    }
}

/// Reasons for disconnecting from a device (for debugging)
public enum DisconnectReason: String, Sendable {
    case userInitiated = "user initiated disconnect"
    case statusMenuDisconnectTap = "status menu disconnect tapped"
    case switchingDevice = "switching to new device"
    case factoryReset = "device factory reset"
    case wifiAddressChange = "WiFi address changed"
    case resyncFailed = "resync failed after 3 attempts"
    case forgetDevice = "user forgot device"
    case deviceRemovedFromSettings = "device removed from iOS Settings"
    case pairingFailed = "device pairing failed"
    case wifiReconnectPrep = "preparing for WiFi reconnect"
}

/// Device platform type for BLE write pacing configuration
public enum DevicePlatform: Sendable {
    case esp32
    case nrf52
    case unknown

    /// Recommended write pacing delay for this platform
    var recommendedWritePacing: TimeInterval {
        switch self {
        case .esp32: return 0.060  // 60ms required by ESP32 BLE stack
        case .nrf52: return 0.025  // Light pacing to avoid RX queue pressure
        case .unknown: return 0.060  // Conservative ESP32-safe default for unrecognized devices
        }
    }

    /// Detects the device platform from the model string for BLE write pacing.
    ///
    /// Uses specific model substrings rather than vendor prefixes, because vendors like
    /// Heltec, RAK, Seeed, and Elecrow ship devices on multiple chip families.
    /// Unrecognized devices fall to `.unknown` (conservative 60ms pacing).
    public static func detect(from model: String) -> DevicePlatform {
        for rule in platformRules {
            if model.localizedStandardContains(rule.substring) {
                return rule.platform
            }
        }
        return .unknown
    }

    // Ordering matters: first match wins in detect(from:). More specific patterns must precede general ones within each platform group.
    private static let platformRules: [(substring: String, platform: DevicePlatform)] = [
        // ESP32 — Heltec
        ("Heltec V2", .esp32),
        ("Heltec V3", .esp32),
        ("Heltec V4", .esp32),
        ("Heltec Tracker", .esp32),
        ("Heltec E290", .esp32),
        ("Heltec E213", .esp32),
        ("Heltec T190", .esp32),
        ("Heltec CT62", .esp32),
        // ESP32 — LilyGo
        ("T-Beam", .esp32),
        ("T-Deck", .esp32),
        ("T-LoRa", .esp32),
        ("TLora", .esp32),
        // ESP32 — Seeed
        ("Xiao S3 WIO", .esp32),
        ("Xiao C3", .esp32),
        ("Xiao C6", .esp32),
        // ESP32 — RAK
        ("RAK 3112", .esp32),
        // ESP32 — Other
        ("Station G2", .esp32),
        ("Meshadventurer", .esp32),
        ("Generic ESP32", .esp32),
        ("ThinkNode M2", .esp32),
        // nRF52 — Heltec
        ("MeshPocket", .nrf52),
        ("Mesh Pocket", .nrf52),
        ("T114", .nrf52),
        ("Mesh Solar", .nrf52),
        // nRF52 — Seeed
        ("Xiao-nrf52", .nrf52),
        ("Xiao_nrf52", .nrf52),
        ("WM1110", .nrf52),
        ("Wio Tracker", .nrf52),
        ("T1000-E", .nrf52),
        ("SenseCap Solar", .nrf52),
        // nRF52 — RAK
        ("WisMesh Tag", .nrf52),
        ("RAK 4631", .nrf52),
        ("RAK 3401", .nrf52),
        // nRF52 — LilyGo
        ("T-Echo", .nrf52),
        // nRF52 — Elecrow
        ("ThinkNode-M1", .nrf52),
        ("ThinkNode M3", .nrf52),
        ("ThinkNode-M6", .nrf52),
        // nRF52 — Other
        ("Ikoka", .nrf52),
        ("ProMicro", .nrf52),
        ("Minewsemi", .nrf52),
        ("Meshtiny", .nrf52),
        ("Keepteen", .nrf52),
        ("Nano G2 Ultra", .nrf52),
    ]
}

/// Result of removing unfavorited nodes from the device
public struct RemoveUnfavoritedResult: Sendable {
    public let removed: Int
    public let total: Int
}

/// Manages the connection lifecycle for mesh devices.
///
/// `ConnectionManager` owns the transport, session, and services. It handles:
/// - Device pairing via AccessorySetupKit
/// - Connection and disconnection
/// - Auto-reconnect on connection loss
/// - Last-device persistence for app restoration
@MainActor
@Observable
public final class ConnectionManager {

    // MARK: - Logging

    let logger = PersistentLogger(subsystem: "com.mc1.services", category: "ConnectionManager")

    // MARK: - Observable State

    /// Current connection state
    public internal(set) var connectionState: ConnectionState = .disconnected {
        didSet {
            #if DEBUG
            assertStateInvariants()
            #endif
        }
    }

    /// Connected device info (nil when disconnected)
    public internal(set) var connectedDevice: DeviceDTO?

    /// Allowed repeat frequency ranges from connected device (empty when disconnected or unsupported)
    public var allowedRepeatFreqRanges: [MeshCore.FrequencyRange] = []

    /// Services container (nil when disconnected)
    public internal(set) var services: ServiceContainer?

    /// Current transport type (bluetooth or wifi)
    public internal(set) var currentTransportType: TransportType?

    /// The user's connection intent. Replaces shouldBeConnected, userExplicitlyDisconnected, and pendingForceFullSync.
    var connectionIntent: ConnectionIntent = .none

    /// The device being actively connected via connect(to:).
    /// Nil during auto-reconnect (tracked by reconnectionCoordinator.reconnectingDeviceID instead).
    var connectingDeviceID: UUID?

    // MARK: - Callbacks

    /// Called when connection is ready and services are available.
    /// Use this to wire up UI observation of services.
    public var onConnectionReady: (() async -> Void)?

    /// Called when connection is lost (disconnection, BLE power off, etc).
    /// Use this to update UI state when services become unavailable.
    public var onConnectionLost: (() async -> Void)?

    /// Called after initial sync completes and connectionState becomes `.ready`.
    /// Use this for work that depends on up-to-date synced data (e.g. stale node cleanup).
    public var onDeviceSynced: (() async -> Void)?

    /// Provider for app foreground/background state detection
    public var appStateProvider: AppStateProvider?

    /// Number of paired accessories (for troubleshooting UI)
    public var pairedAccessoriesCount: Int {
        accessorySetupKit.pairedAccessories.count
    }

    /// Creates a standalone persistence store for operations that don't require services
    public func createStandalonePersistenceStore() -> PersistenceStore {
        PersistenceStore(modelContainer: modelContainer)
    }

    // MARK: - Internal Components

    let modelContainer: ModelContainer
    private let defaults: UserDefaults
    let transport: iOSBLETransport
    var wifiTransport: WiFiTransport?
    var session: MeshCoreSession?
    let accessorySetupKit = AccessorySetupKitService()

    /// Shared BLE state machine to manage connection lifecycle.
    /// This prevents state restoration race conditions that cause "API MISUSE" errors.
    let stateMachine: any BLEStateMachineProtocol

    /// Coordinates iOS auto-reconnect lifecycle (timeouts, teardown, rebuild).
    let reconnectionCoordinator = BLEReconnectionCoordinator()

    // MARK: - WiFi Reconnection

    /// Task handling WiFi reconnection attempts
    var wifiReconnectTask: Task<Void, Never>?

    /// Current reconnection attempt number
    var wifiReconnectAttempt = 0

    /// Maximum duration for WiFi reconnection attempts (30 seconds)
    static let wifiMaxReconnectDuration: Duration = .seconds(30)

    /// Last reconnection start time (for rate limiting rapid disconnects)
    var lastWiFiReconnectStartTime: Date?

    /// Minimum interval between reconnection attempts (prevents flapping)
    static let wifiReconnectCooldown: TimeInterval = 35

    // MARK: - WiFi Heartbeat

    /// Task for periodic WiFi connection health checks
    var wifiHeartbeatTask: Task<Void, Never>?

    /// Interval between WiFi heartbeat probes (seconds)
    static let wifiHeartbeatInterval: Duration = .seconds(30)

    /// Task coordinating BLE scan startup to avoid start/stop races with stream termination.
    var bleScanTask: Task<Void, Never>?

    /// Monotonic token used to invalidate stale BLE scan requests.
    var bleScanRequestID: UInt64 = 0

    // MARK: - Resync State

    /// Current resync attempt count (reset on success or disconnect)
    private var resyncAttemptCount = 0

    /// Maximum resync attempts before giving up
    private static let maxResyncAttempts = 3

    /// Interval between resync attempts
    private static let resyncInterval: Duration = .seconds(2)

    /// Task managing the resync retry loop
    var resyncTask: Task<Void, Never>?

    /// Callback when resync fails after all attempts (triggers "Sync Failed" pill)
    /// Note: @Sendable @MainActor ensures safe cross-isolation callback
    public var onResyncFailed: (@Sendable @MainActor () -> Void)?

    // MARK: - Circuit Breaker

    /// Prevents rapid reconnection loops after repeated failures.
    /// Closed → Open (30s cooldown) → Half-Open (single probe).
    private enum CircuitBreakerState {
        case closed
        case open(since: Date)
        case halfOpen
    }

    private var circuitBreaker: CircuitBreakerState = .closed
    private static let circuitBreakerCooldown: TimeInterval = 30

    /// Checks whether a connection attempt should proceed.
    /// Returns `true` if the circuit breaker allows it.
    /// - Parameter force: When `true`, bypasses the circuit breaker (user-initiated reconnect)
    func shouldAllowConnection(force: Bool) -> Bool {
        if force { return true }

        switch circuitBreaker {
        case .closed:
            return true
        case .open(let since):
            if Date().timeIntervalSince(since) >= Self.circuitBreakerCooldown {
                circuitBreaker = .halfOpen
                logger.info("[BLE] Circuit breaker: open → halfOpen (cooldown elapsed)")
                return true
            }
            return false
        case .halfOpen:
            // Half-open: allow a single probe attempt to determine if the connection can be restored.
            return true
        }
    }

    /// Records a connection failure for circuit breaker tracking.
    /// Trips the breaker to `.open` when called after all retries are exhausted.
    func recordConnectionFailure() {
        switch circuitBreaker {
        case .closed:
            circuitBreaker = .open(since: Date())
            logger.warning("[BLE] Circuit breaker: closed → open (retries exhausted)")
        case .halfOpen:
            circuitBreaker = .open(since: Date())
            logger.warning("[BLE] Circuit breaker: halfOpen → open (probe failed)")
        case .open:
            break
        }
    }

    /// Records a successful connection, resetting the circuit breaker.
    func recordConnectionSuccess() {
        if case .closed = circuitBreaker { return }
        circuitBreaker = .closed
        logger.info("[BLE] Circuit breaker: → closed (connection succeeded)")
    }

    // MARK: - Reconnection Watchdog

    /// Task managing the reconnection watchdog (retries when stuck disconnected)
    var reconnectionWatchdogTask: Task<Void, Never>?

    /// Session IDs that need re-authentication after BLE reconnect.
    /// Populated by `handleBLEDisconnection()`, consumed by `rebuildSession()`.
    /// Empty after app restart, so rooms show "Tap to reconnect" instead of auto-connecting.
    var sessionsAwaitingReauth: Set<UUID> = []

    // MARK: - Persistence Keys

    private let lastDeviceIDKey = "com.pocketmesh.lastConnectedDeviceID"
    private let lastDeviceNameKey = "com.pocketmesh.lastConnectedDeviceName"
    private let lastDisconnectDiagnosticKey = "com.pocketmesh.lastDisconnectDiagnostic"

    // MARK: - Simulator Support

    /// Simulator connection mode (used for demo mode on device)
    let simulatorMode = SimulatorConnectionMode()

    /// Whether running in simulator mode
    #if targetEnvironment(simulator)
    public var isSimulatorMode: Bool { true }
    #else
    public var isSimulatorMode: Bool { false }
    #endif

    // MARK: - Last Device Persistence

    #if DEBUG
    /// Test override for lastConnectedDeviceID
    internal var testLastConnectedDeviceID: UUID?

    /// True when the BLE reconnection watchdog task is active.
    internal var isReconnectionWatchdogRunning: Bool {
        reconnectionWatchdogTask != nil
    }
    #endif

    /// The last connected device ID (for auto-reconnect)
    public var lastConnectedDeviceID: UUID? {
        #if DEBUG
        if let testID = testLastConnectedDeviceID {
            return testID
        }
        #endif
        guard let uuidString = defaults.string(forKey: lastDeviceIDKey) else {
            return nil
        }
        return UUID(uuidString: uuidString)
    }

    /// Records a successful connection for future restoration
    func persistConnection(deviceID: UUID, deviceName: String) {
        defaults.set(deviceID.uuidString, forKey: lastDeviceIDKey)
        defaults.set(deviceName, forKey: lastDeviceNameKey)
    }

    /// Clears the persisted connection
    func clearPersistedConnection() {
        defaults.removeObject(forKey: lastDeviceIDKey)
        defaults.removeObject(forKey: lastDeviceNameKey)
    }

    /// Whether the disconnected pill should be suppressed (user explicitly disconnected)
    public var shouldSuppressDisconnectedPill: Bool {
        connectionIntent.isUserDisconnected
    }

    /// Most recent disconnect diagnostic summary persisted across app launches.
    public var lastDisconnectDiagnostic: String? {
        defaults.string(forKey: lastDisconnectDiagnosticKey)
    }

    /// Current high-level connection intent, exported for diagnostics.
    public var connectionIntentSummary: String {
        switch connectionIntent {
        case .none:
            return "none"
        case .userDisconnected:
            return "userDisconnected"
        case .wantsConnection(let forceFullSync):
            return forceFullSync ? "wantsConnection(forceFullSync: true)" : "wantsConnection"
        }
    }

    /// Whether the last connection was a simulator connection
    public var wasSimulatorConnection: Bool {
        lastConnectedDeviceID == MockDataProvider.simulatorDeviceID
    }

    /// Whether a WiFi disconnection is currently being handled (prevents interleaving
    /// across await suspension points before wifiReconnectTask is set).
    var isHandlingWiFiDisconnection = false

    // MARK: - Cancellation Helpers

    /// Cancels any in-progress WiFi reconnection attempts
    func cancelWiFiReconnection() {
        wifiReconnectTask?.cancel()
        wifiReconnectTask = nil
        wifiReconnectAttempt = 0
    }

    /// Cancels any resync retry loop in progress
    func cancelResyncLoop() {
        resyncTask?.cancel()
        resyncTask = nil
        resyncAttemptCount = 0
    }

    // MARK: - Initial Sync

    /// Performs initial sync with automatic resync loop on failure.
    /// - Parameters:
    ///   - deviceID: The device ID to sync
    ///   - services: The service container
    ///   - context: Optional context string for logging (e.g., "WiFi reconnect")
    ///   - forceFullSync: When true, forces complete data exchange regardless of sync state
    func performInitialSync(
        deviceID: UUID,
        services: ServiceContainer,
        context: String = "",
        forceFullSync: Bool = false
    ) async {
        do {
            try await withTimeout(.seconds(120), operationName: "performInitialSync") {
                try await services.syncCoordinator.onConnectionEstablished(
                    deviceID: deviceID,
                    services: services,
                    forceFullSync: forceFullSync
                )
            }
        } catch {
            // Don't start resync if user disconnected while sync was in progress
            guard connectionIntent.wantsConnection else { return }
            let prefix = context.isEmpty ? "" : "\(context): "
            logger.warning("\(prefix)Initial sync failed, starting resync loop: \(error.localizedDescription)")
            startResyncLoop(deviceID: deviceID, services: services, forceFullSync: forceFullSync)
        }
    }

    /// Starts a retry loop to resync after initial sync failure.
    /// Retries every 2 seconds, shows "Sync Failed" pill and disconnects after 3 failures.
    /// - Parameters:
    ///   - deviceID: The connected device UUID
    ///   - services: The ServiceContainer with all services
    ///   - forceFullSync: When true, forces complete data exchange regardless of sync state
    func startResyncLoop(deviceID: UUID, services: ServiceContainer, forceFullSync: Bool = false) {
        resyncTask?.cancel()
        resyncAttemptCount = 0

        // Note: No [weak self] needed - Task is stored property, self is @MainActor class.
        // Task inherits MainActor isolation, no retain cycle risk.
        resyncTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.resyncInterval)
                guard !Task.isCancelled else { break }

                guard connectionIntent.wantsConnection,
                      connectionState == .ready else { break }

                resyncAttemptCount += 1
                logger.info("Resync attempt \(resyncAttemptCount)/\(Self.maxResyncAttempts)")

                let success: Bool
                do {
                    success = try await withTimeout(.seconds(60), operationName: "performResync") {
                        await services.syncCoordinator.performResync(
                            deviceID: deviceID,
                            services: services,
                            forceFullSync: forceFullSync
                        )
                    }
                } catch {
                    logger.warning("Resync timed out: \(error.localizedDescription)")
                    success = false
                }

                if success {
                    logger.info("Resync succeeded")
                    resyncAttemptCount = 0
                    break
                }

                if resyncAttemptCount >= Self.maxResyncAttempts {
                    logger.warning("Resync failed \(Self.maxResyncAttempts) times, disconnecting")
                    onResyncFailed?()
                    await disconnect(reason: .resyncFailed)
                    break
                }
            }

            resyncTask = nil
        }
    }

    // MARK: - Initialization

    /// Creates a new connection manager.
    /// - Parameters:
    ///   - modelContainer: The SwiftData model container for persistence
    ///   - stateMachine: Optional BLE state machine for testing. If nil, creates a real BLEStateMachine.
    public init(modelContainer: ModelContainer, defaults: UserDefaults = .standard, stateMachine: (any BLEStateMachineProtocol)? = nil) {
        self.modelContainer = modelContainer
        self.defaults = defaults
        self.connectionIntent = .restored(from: defaults)

        // Use provided state machine or create default
        let bleStateMachine = stateMachine ?? BLEStateMachine()
        self.stateMachine = bleStateMachine

        // Transport requires concrete BLEStateMachine
        if let concrete = bleStateMachine as? BLEStateMachine {
            self.transport = iOSBLETransport(stateMachine: concrete)
        } else {
            // Test mode: create a dummy transport (won't be used when mocking BLE)
            self.transport = iOSBLETransport(stateMachine: BLEStateMachine())
        }

        accessorySetupKit.delegate = self
        reconnectionCoordinator.delegate = self

        // Wire up transport handlers
        Task { [stateMachine = self.stateMachine] in
            // Handle disconnection events
            await transport.setDisconnectionHandler { [weak self] deviceID, error in
                Task { @MainActor in
                    guard let self else { return }
                    await self.handleConnectionLoss(deviceID: deviceID, error: error)
                }
            }

            // Handle entering auto-reconnecting phase
            await stateMachine.setAutoReconnectingHandler { [weak self] (deviceID: UUID, errorInfo: String) in
                Task { @MainActor in
                    guard let self else { return }
                    let initialState = String(describing: self.connectionState)
                    let transportName = switch self.currentTransportType {
                    case .bluetooth: "bluetooth"
                    case .wifi: "wifi"
                    case nil: "none"
                    }
                    let bleState = await self.stateMachine.centralManagerStateName
                    let blePhase = await self.stateMachine.currentPhaseName
                    let blePeripheralState = await self.stateMachine.currentPeripheralState ?? "none"

                    self.persistDisconnectDiagnostic(
                        "source=bleStateMachine.autoReconnectingHandler, " +
                        "device=\(deviceID.uuidString.prefix(8)), " +
                        "transport=\(transportName), " +
                        "initialState=\(initialState), " +
                        "bleState=\(bleState), " +
                        "blePhase=\(blePhase), " +
                        "blePeripheralState=\(blePeripheralState), " +
                        "error=\(errorInfo), " +
                        "intent=\(self.connectionIntent)"
                    )
                    await self.reconnectionCoordinator.handleEnteringAutoReconnect(deviceID: deviceID)
                }
            }

            // Handle iOS auto-reconnect completion
            // Using transport.setReconnectionHandler ensures the transport captures
            // the data stream internally before calling our handler
            await transport.setReconnectionHandler { [weak self] deviceID in
                Task { @MainActor in
                    guard let self else { return }
                    await self.reconnectionCoordinator.handleReconnectionComplete(deviceID: deviceID)
                }
            }

            // Handle Bluetooth power-cycle recovery
            await stateMachine.setBluetoothPoweredOnHandler { [weak self] in
                Task { @MainActor in
                    guard let self,
                          self.connectionIntent.wantsConnection,
                          self.connectionState == .disconnected,
                          let deviceID = self.lastConnectedDeviceID else { return }

                    self.logger.info("[BLE] Bluetooth powered on: attempting reconnection to \(deviceID.uuidString.prefix(8))")
                    try? await self.connect(to: deviceID)
                }
            }

            // Handle Bluetooth state changes for diagnostics
            await stateMachine.setBluetoothStateChangeHandler { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    self.handleBluetoothStateChange(state)
                }
            }
        }
    }

    // MARK: - Session Helpers

    /// Starts a session and queries device capabilities.
    func initializeSession(
        _ session: MeshCoreSession
    ) async throws -> (SelfInfo, DeviceCapabilities) {
        do {
            try await withTimeout(.seconds(10), operationName: "session.start") {
                try await session.start()
            }
        } catch {
            logger.warning("[BLE] session.start() timed out or failed: \(error.localizedDescription)")
            throw error
        }

        guard let selfInfo = await session.currentSelfInfo else {
            logger.warning("[BLE] selfInfo is nil after session.start()")
            throw ConnectionError.initializationFailed("Failed to get device self info")
        }
        do {
            let capabilities = try await withTimeout(.seconds(10), operationName: "queryDevice") {
                try await session.queryDevice()
            }
            return (selfInfo, capabilities)
        } catch {
            logger.warning("[BLE] queryDevice() timed out or failed: \(error.localizedDescription)")
            throw error
        }
    }

    /// Syncs the device clock if it drifts more than 60 seconds from the phone.
    /// Safe to call after sync — only affects future device-originated timestamps.
    func syncDeviceTimeIfNeeded() async {
        guard let session else { return }
        do {
            let deviceTime = try await withTimeout(.seconds(5), operationName: "getTime") {
                try await session.getTime()
            }
            let timeDifference = abs(deviceTime.timeIntervalSinceNow)
            if timeDifference > 60 {
                try await withTimeout(.seconds(5), operationName: "setTime") {
                    try await session.setTime(Date())
                }
                logger.info("Synced device time (was off by \(Int(timeDifference))s)")
            } else {
                logger.info("Device time in sync (drift: \(Int(timeDifference))s)")
            }
        } catch {
            logger.warning("Failed to sync device time: \(error.localizedDescription)")
        }
    }

    /// Creates a Device from MeshCore types
    func createDevice(
        deviceID: UUID,
        selfInfo: MeshCore.SelfInfo,
        capabilities: MeshCore.DeviceCapabilities,
        autoAddConfig: MeshCore.AutoAddConfig,
        existingDevice: DeviceDTO? = nil,
        connectionMethods: [ConnectionMethod] = []
    ) -> Device {
        // Merge new connection methods with existing ones, replacing by transport type
        var mergedMethods = existingDevice?.connectionMethods ?? []
        for method in connectionMethods {
            if method.isWiFi {
                mergedMethods.removeAll { $0.isWiFi }
            } else if method.isBluetooth {
                mergedMethods.removeAll { $0.isBluetooth }
            }
            mergedMethods.append(method)
        }

        let device = Device(
            id: deviceID,
            publicKey: selfInfo.publicKey,
            nodeName: selfInfo.name,
            firmwareVersion: capabilities.firmwareVersion,
            firmwareVersionString: capabilities.version,
            manufacturerName: capabilities.model,
            buildDate: capabilities.firmwareBuild,
            maxContacts: UInt16(capabilities.maxContacts),
            maxChannels: UInt8(min(capabilities.maxChannels, 255)),
            frequency: UInt32(selfInfo.radioFrequency * 1000),  // Convert MHz to kHz
            bandwidth: UInt32(selfInfo.radioBandwidth * 1000),  // Convert kHz to Hz
            spreadingFactor: selfInfo.radioSpreadingFactor,
            codingRate: selfInfo.radioCodingRate,
            txPower: selfInfo.txPower,
            maxTxPower: selfInfo.maxTxPower,
            latitude: selfInfo.latitude,
            longitude: selfInfo.longitude,
            blePin: capabilities.blePin,
            clientRepeat: capabilities.clientRepeat,
            pathHashMode: capabilities.pathHashMode,
            preRepeatFrequency: existingDevice?.preRepeatFrequency,
            preRepeatBandwidth: existingDevice?.preRepeatBandwidth,
            preRepeatSpreadingFactor: existingDevice?.preRepeatSpreadingFactor,
            preRepeatCodingRate: existingDevice?.preRepeatCodingRate,
            manualAddContacts: selfInfo.manualAddContacts,
            autoAddConfig: autoAddConfig.bitmask,
            autoAddMaxHops: autoAddConfig.maxHops,
            multiAcks: selfInfo.multiAcks,
            telemetryModeBase: selfInfo.telemetryModeBase,
            telemetryModeLoc: selfInfo.telemetryModeLocation,
            telemetryModeEnv: selfInfo.telemetryModeEnvironment,
            advertLocationPolicy: selfInfo.advertisementLocationPolicy,
            lastConnected: Date(),
            lastContactSync: existingDevice?.lastContactSync ?? 0,
            isActive: true,
            ocvPreset: existingDevice?.ocvPreset
                ?? OCVPreset.preset(forManufacturer: capabilities.model)?.rawValue,
            customOCVArrayString: existingDevice?.customOCVArrayString,
            connectionMethods: mergedMethods
        )

        // If repeat mode was disabled externally, clear orphaned pre-repeat settings
        if !capabilities.clientRepeat && existingDevice?.preRepeatFrequency != nil {
            device.preRepeatFrequency = nil
            device.preRepeatBandwidth = nil
            device.preRepeatSpreadingFactor = nil
            device.preRepeatCodingRate = nil
        }

        return device
    }

    /// Configures BLE write pacing based on detected device platform.
    /// - Parameter capabilities: The device capabilities from queryDevice()
    func configureBLEPacing(for capabilities: MeshCore.DeviceCapabilities) async {
        let platform = DevicePlatform.detect(from: capabilities.model)
        let pacing = platform.recommendedWritePacing
        await stateMachine.setWritePacingDelay(pacing)
        if pacing > 0 {
            logger.info("[BLE] Platform detected: \(capabilities.model) -> \(platform), write pacing: \(pacing)s")
        }
    }

    // MARK: - Cleanup

    /// Cleans up session and services without changing connection state (used during retries)
    func cleanupResources() async {
        await session?.stop()
        session = nil
        services = nil
    }

    /// Full cleanup including state reset (used on explicit disconnect)
    func cleanupConnection() async {
        logger.info("[BLE] cleanupConnection: state → .disconnected")
        connectionState = .disconnected
        connectingDeviceID = nil
        connectedDevice = nil
        allowedRepeatFreqRanges = []
        await cleanupResources()
    }

    func persistDisconnectDiagnostic(_ summary: String) {
        let timestamp = Date().ISO8601Format()
        defaults.set("\(timestamp) \(summary)", forKey: lastDisconnectDiagnosticKey)
    }

    func persistIntent() {
        connectionIntent.persist(to: defaults)
    }

    // MARK: - State Invariants

    #if DEBUG
    private var suppressInvariantChecks = false

    private func assertStateInvariants() {
        guard !suppressInvariantChecks else { return }
        switch connectionState {
        case .ready:
            assert(services != nil, "Invariant: .ready requires services")
            assert(session != nil, "Invariant: .ready requires session")
            assert(connectedDevice != nil, "Invariant: .ready requires connectedDevice")
        case .connected, .disconnected, .connecting:
            break
        }
        if connectionIntent.isUserDisconnected {
            assert(connectionState == .disconnected, "Invariant: .userDisconnected requires .disconnected state")
        }
    }
    #endif

    // MARK: - Test Helpers

    #if DEBUG
    /// Sets internal state for testing. Only available in DEBUG builds.
    internal func setTestState(
        connectionState: ConnectionState? = nil,
        currentTransportType: TransportType?? = nil,
        connectionIntent: ConnectionIntent? = nil,
        connectingDeviceID: UUID?? = nil
    ) {
        suppressInvariantChecks = true
        defer { suppressInvariantChecks = false }

        if let state = connectionState {
            self.connectionState = state
        }
        if let transport = currentTransportType {
            self.currentTransportType = transport
        }
        if let intent = connectionIntent {
            self.connectionIntent = intent
        }
        if let deviceID = connectingDeviceID {
            self.connectingDeviceID = deviceID
        }
    }
    #endif
}
