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

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(_, let underlying):
            return "Connection failed: \(underlying.localizedDescription)"
        }
    }

    /// The device ID that failed to connect (for recovery UI)
    public var deviceID: UUID? {
        switch self {
        case .connectionFailed(let deviceID, _):
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

    private let logger = PersistentLogger(subsystem: "com.pocketmesh.services", category: "ConnectionManager")

    // MARK: - Observable State

    /// Current connection state
    public private(set) var connectionState: ConnectionState = .disconnected {
        didSet {
            #if DEBUG
            assertStateInvariants()
            #endif
        }
    }

    /// Connected device info (nil when disconnected)
    public private(set) var connectedDevice: DeviceDTO?

    /// Services container (nil when disconnected)
    public private(set) var services: ServiceContainer?

    /// Current transport type (bluetooth or wifi)
    public private(set) var currentTransportType: TransportType?

    /// The user's connection intent. Replaces shouldBeConnected, userExplicitlyDisconnected, and pendingForceFullSync.
    private(set) var connectionIntent: ConnectionIntent = .restored()

    // MARK: - Callbacks

    /// Called when connection is ready and services are available.
    /// Use this to wire up UI observation of services.
    public var onConnectionReady: (() async -> Void)?

    /// Called when connection is lost (disconnection, BLE power off, etc).
    /// Use this to update UI state when services become unavailable.
    public var onConnectionLost: (() async -> Void)?

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

    private let modelContainer: ModelContainer
    private let transport: iOSBLETransport
    private var wifiTransport: WiFiTransport?
    private var session: MeshCoreSession?
    private let accessorySetupKit = AccessorySetupKitService()

    /// Shared BLE state machine to manage connection lifecycle.
    /// This prevents state restoration race conditions that cause "API MISUSE" errors.
    private let stateMachine: any BLEStateMachineProtocol

    /// Coordinates iOS auto-reconnect lifecycle (timeouts, teardown, rebuild).
    private let reconnectionCoordinator = BLEReconnectionCoordinator()

    // MARK: - WiFi Reconnection

    /// Task handling WiFi reconnection attempts
    private var wifiReconnectTask: Task<Void, Never>?

    /// Current reconnection attempt number
    private var wifiReconnectAttempt = 0

    /// Maximum duration for WiFi reconnection attempts (30 seconds)
    private static let wifiMaxReconnectDuration: Duration = .seconds(30)

    /// Last reconnection start time (for rate limiting rapid disconnects)
    private var lastWiFiReconnectStartTime: Date?

    /// Minimum interval between reconnection attempts (prevents flapping)
    private static let wifiReconnectCooldown: TimeInterval = 35

    // MARK: - WiFi Heartbeat

    /// Task for periodic WiFi connection health checks
    private var wifiHeartbeatTask: Task<Void, Never>?

    /// Interval between WiFi heartbeat probes (seconds)
    private static let wifiHeartbeatInterval: Duration = .seconds(30)

    /// Task coordinating BLE scan startup to avoid start/stop races with stream termination.
    private var bleScanTask: Task<Void, Never>?

    /// Monotonic token used to invalidate stale BLE scan requests.
    private var bleScanRequestID: UInt64 = 0

    // MARK: - Resync State

    /// Current resync attempt count (reset on success or disconnect)
    private var resyncAttemptCount = 0

    /// Maximum resync attempts before giving up
    private static let maxResyncAttempts = 3

    /// Interval between resync attempts
    private static let resyncInterval: Duration = .seconds(2)

    /// Task managing the resync retry loop
    private var resyncTask: Task<Void, Never>?

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
    private func shouldAllowConnection(force: Bool) -> Bool {
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
            return true
        }
    }

    /// Records a connection failure for circuit breaker tracking.
    /// Trips the breaker to `.open` when called after all retries are exhausted.
    private func recordConnectionFailure() {
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
    private func recordConnectionSuccess() {
        if case .closed = circuitBreaker { return }
        circuitBreaker = .closed
        logger.info("[BLE] Circuit breaker: → closed (connection succeeded)")
    }

    // MARK: - Reconnection Watchdog

    /// Task managing the reconnection watchdog (retries when stuck disconnected)
    private var reconnectionWatchdogTask: Task<Void, Never>?

    /// Session IDs that need re-authentication after BLE reconnect.
    /// Populated by `handleBLEDisconnection()`, consumed by `rebuildSession()`.
    /// Empty after app restart, so rooms show "Tap to reconnect" instead of auto-connecting.
    private var sessionsAwaitingReauth: Set<UUID> = []

    // MARK: - Persistence Keys

    private let lastDeviceIDKey = "com.pocketmesh.lastConnectedDeviceID"
    private let lastDeviceNameKey = "com.pocketmesh.lastConnectedDeviceName"
    private let lastDisconnectDiagnosticKey = "com.pocketmesh.lastDisconnectDiagnostic"

    // MARK: - Simulator Support

    /// Simulator connection mode (used for demo mode on device)
    private let simulatorMode = SimulatorConnectionMode()

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
        guard let uuidString = UserDefaults.standard.string(forKey: lastDeviceIDKey) else {
            return nil
        }
        return UUID(uuidString: uuidString)
    }

    /// Records a successful connection for future restoration
    private func persistConnection(deviceID: UUID, deviceName: String) {
        UserDefaults.standard.set(deviceID.uuidString, forKey: lastDeviceIDKey)
        UserDefaults.standard.set(deviceName, forKey: lastDeviceNameKey)
    }

    /// Clears the persisted connection
    private func clearPersistedConnection() {
        UserDefaults.standard.removeObject(forKey: lastDeviceIDKey)
        UserDefaults.standard.removeObject(forKey: lastDeviceNameKey)
    }

    /// Whether the disconnected pill should be suppressed (user explicitly disconnected)
    public var shouldSuppressDisconnectedPill: Bool {
        connectionIntent.isUserDisconnected
    }

    /// Most recent disconnect diagnostic summary persisted across app launches.
    public var lastDisconnectDiagnostic: String? {
        UserDefaults.standard.string(forKey: lastDisconnectDiagnosticKey)
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

    /// Returns a best-effort snapshot of the BLE state machine for debug exports.
    public func currentBLEDiagnosticsSummary() async -> String {
        let bleState = await stateMachine.centralManagerStateName
        let blePhase = await stateMachine.currentPhaseName
        let blePeripheralState = await stateMachine.currentPeripheralState ?? "none"
        let isConnected = await stateMachine.isConnected
        let isAutoReconnecting = await stateMachine.isAutoReconnecting
        let connectedDeviceShort = await stateMachine.connectedDeviceID?.uuidString.prefix(8) ?? "none"
        return
            "BLE: state=\(bleState), " +
            "phase=\(blePhase), " +
            "peripheralState=\(blePeripheralState), " +
            "isConnected=\(isConnected), " +
            "isAutoReconnecting=\(isAutoReconnecting), " +
            "connectedDevice=\(connectedDeviceShort)"
    }

    /// Checks if a device is connected to the system by another app.
    /// Returns false during auto-reconnect or when the device is already connected by us.
    /// - Parameter deviceID: The UUID of the device to check
    /// - Returns: `true` if device appears connected to another app
    public func isDeviceConnectedToOtherApp(_ deviceID: UUID) async -> Bool {
        // Don't check during auto-reconnect - that's our own connection
        let isAutoReconnecting = await stateMachine.isAutoReconnecting
        guard !isAutoReconnecting else { return false }

        // Don't check if we're already connected (switching devices)
        guard connectionState == .disconnected else { return false }

        // Don't report our own connection as "another app" (state restoration may have completed)
        if await stateMachine.isConnected, await stateMachine.connectedDeviceID == deviceID {
            return false
        }

        return await stateMachine.isDeviceConnectedToSystem(deviceID)
    }


    // MARK: - BLE Scanning

    /// Starts scanning for nearby BLE devices and returns an AsyncStream of (deviceID, rssi) discoveries.
    /// Scanning is orthogonal to the connection lifecycle — works while connected.
    /// Cancel the consuming task to stop scanning automatically.
    public func startBLEScanning() -> AsyncStream<(UUID, Int)> {
        let (stream, continuation) = AsyncStream.makeStream(of: (UUID, Int).self)
        bleScanTask?.cancel()
        bleScanRequestID &+= 1
        let requestID = bleScanRequestID

        bleScanTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard !Task.isCancelled, requestID == self.bleScanRequestID else { return }

            await self.stateMachine.setDeviceDiscoveredHandler { @Sendable deviceID, rssi in
                _ = continuation.yield((deviceID, rssi))
            }

            guard !Task.isCancelled, requestID == self.bleScanRequestID else { return }
            await self.stateMachine.startScanning()
        }

        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.bleScanRequestID == requestID else { return }
                self.bleScanRequestID &+= 1
                self.bleScanTask?.cancel()
                self.bleScanTask = nil
                await self.stateMachine.setDeviceDiscoveredHandler { _, _ in }
                await self.stateMachine.stopScanning()
            }
        }

        return stream
    }

    /// Manually stops BLE scanning.
    public func stopBLEScanning() async {
        bleScanRequestID &+= 1
        bleScanTask?.cancel()
        bleScanTask = nil
        await stateMachine.setDeviceDiscoveredHandler { _, _ in }
        await stateMachine.stopScanning()
    }

    /// Cancels any in-progress WiFi reconnection attempts
    private func cancelWiFiReconnection() {
        wifiReconnectTask?.cancel()
        wifiReconnectTask = nil
        wifiReconnectAttempt = 0
    }

    /// Cancels any resync retry loop in progress
    private func cancelResyncLoop() {
        resyncTask?.cancel()
        resyncTask = nil
        resyncAttemptCount = 0
    }

    /// Starts a watchdog that periodically retries connection when the user wants to be
    /// connected but the device is stuck in disconnected state (e.g., after auto-reconnect failure).
    /// Uses exponential backoff: 30s → 60s → 120s (capped).
    private func startReconnectionWatchdog() {
        stopReconnectionWatchdog()

        reconnectionWatchdogTask = Task {
            var delay: Duration = .seconds(30)
            let maxDelay: Duration = .seconds(120)

            while !Task.isCancelled {
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }

                guard connectionIntent.wantsConnection,
                      connectionState == .disconnected else {
                    logger.info("[BLE] Watchdog exiting: intent or state changed")
                    return
                }

                if await stateMachine.isBluetoothPoweredOff {
                    logger.info("[BLE] Watchdog skipping: Bluetooth powered off")
                    delay = min(delay * 2, maxDelay)
                    continue
                }

                if await stateMachine.isAutoReconnecting {
                    logger.info("[BLE] Watchdog skipping: iOS auto-reconnect in progress")
                    delay = min(delay * 2, maxDelay)
                    continue
                }

                logger.info("[BLE] Watchdog attempting reconnection (delay was \(delay))")
                await checkBLEConnectionHealth()

                delay = min(delay * 2, maxDelay)
            }
        }
    }

    /// Stops the reconnection watchdog
    private func stopReconnectionWatchdog() {
        reconnectionWatchdogTask?.cancel()
        reconnectionWatchdogTask = nil
    }

    /// Starts periodic heartbeat to detect dead WiFi connections.
    /// ESP32's TCP stack doesn't respond to TCP keepalives, so we use application-level probes.
    private func startWiFiHeartbeat() {
        stopWiFiHeartbeat()

        wifiHeartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: Self.wifiHeartbeatInterval)
                } catch {
                    break
                }

                guard let self,
                      self.currentTransportType == .wifi,
                      self.connectionState == .ready,
                      let session = self.session else { break }

                // Probe connection with lightweight command
                do {
                    _ = try await session.getTime()
                } catch {
                    self.logger.warning("WiFi heartbeat failed: \(error.localizedDescription)")
                    await self.handleWiFiDisconnection(error: error)
                    break
                }
            }
        }
    }

    /// Stops the WiFi heartbeat loop
    private func stopWiFiHeartbeat() {
        wifiHeartbeatTask?.cancel()
        wifiHeartbeatTask = nil
    }

    /// Whether a WiFi disconnection is currently being handled (prevents interleaving
    /// across await suspension points before wifiReconnectTask is set).
    private var isHandlingWiFiDisconnection = false

    /// Handles unexpected WiFi connection loss
    private func handleWiFiDisconnection(error: Error?) async {
        // User-initiated disconnect - don't reconnect
        guard connectionIntent.wantsConnection else { return }

        // Only handle WiFi disconnections
        guard currentTransportType == .wifi else { return }

        // Prevent re-entrant calls: multiple disconnection callbacks can fire
        // simultaneously from the transport handler and heartbeat. The flag
        // covers the window between entry and startWiFiReconnection() where
        // await suspension points could allow interleaving on @MainActor.
        guard !isHandlingWiFiDisconnection, wifiReconnectTask == nil else {
            logger.info("WiFi disconnection already being handled, ignoring duplicate")
            return
        }
        isHandlingWiFiDisconnection = true
        defer { isHandlingWiFiDisconnection = false }

        logger.warning("WiFi connection lost: \(error?.localizedDescription ?? "unknown")")

        // Stop heartbeat before teardown
        stopWiFiHeartbeat()

        cancelResyncLoop()

        // Mark room sessions disconnected before tearing down services
        let remoteNodeService = services?.remoteNodeService
        if let remoteNodeService {
            _ = await remoteNodeService.handleBLEDisconnection()
        }

        // Reset sync state before destroying services to prevent stuck "Syncing" pill
        if let services {
            await services.syncCoordinator.onDisconnected(services: services)
        }

        // Tear down session (invalid now)
        await services?.stopEventMonitoring()
        services = nil
        session = nil

        // Show connecting state (pulsing indicator)
        logger.info("[WiFi] State → .connecting (WiFi disconnection, starting reconnection)")
        connectionState = .connecting

        // Start reconnection attempts
        startWiFiReconnection()
    }

    /// Starts the WiFi reconnection retry loop
    private func startWiFiReconnection() {
        // If a reconnect task is already running, don't start another
        if wifiReconnectTask != nil {
            logger.info("WiFi reconnection already in progress, skipping")
            return
        }

        // Rate limiting: prevent rapid reconnection attempts
        if let lastStart = lastWiFiReconnectStartTime,
           Date().timeIntervalSince(lastStart) < Self.wifiReconnectCooldown {
            logger.warning("Suppressing WiFi reconnection: too soon after last attempt")
            Task { await cleanupConnection() }
            return
        }
        lastWiFiReconnectStartTime = Date()

        wifiReconnectAttempt = 0
        wifiReconnectTask?.cancel()

        wifiReconnectTask = Task {
            defer {
                wifiReconnectTask = nil
                wifiReconnectAttempt = 0
            }

            let startTime = ContinuousClock.now

            while !Task.isCancelled && connectionIntent.wantsConnection {
                // Check if we've exceeded 30 second window
                let elapsed = ContinuousClock.now - startTime
                if elapsed > Self.wifiMaxReconnectDuration {
                    logger.info("WiFi reconnection timeout after 30s")
                    await cleanupConnection()
                    return
                }

                wifiReconnectAttempt += 1
                logger.info("WiFi reconnect attempt \(self.wifiReconnectAttempt)")

                do {
                    try await reconnectWiFi()
                    logger.info("WiFi reconnection succeeded")
                    return
                } catch {
                    logger.warning("WiFi reconnect failed: \(error.localizedDescription)")
                }

                // Exponential backoff: 0.5s, 1s, 2s, 4s (capped)
                let delay = min(0.5 * pow(2.0, Double(wifiReconnectAttempt - 1)), 4.0)
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    /// Attempts to reconnect to the WiFi device using stored connection info
    private func reconnectWiFi() async throws {
        guard let wifiTransport,
              let (host, port) = await wifiTransport.connectionInfo else {
            throw ConnectionError.connectionFailed("No WiFi connection info")
        }

        // Stop any existing session to prevent receive loops racing for transport data
        await session?.stop()
        session = nil

        // Disconnect old transport cleanly
        await wifiTransport.disconnect()

        // Create fresh transport with same connection info
        let newTransport = WiFiTransport()
        await newTransport.setConnectionInfo(host: host, port: port)
        self.wifiTransport = newTransport

        // Connect
        try await newTransport.connect()
        connectionState = .connected

        // Re-establish session
        let newSession = MeshCoreSession(transport: newTransport)
        self.session = newSession
        try await newSession.start()

        guard let selfInfo = await newSession.currentSelfInfo else {
            throw ConnectionError.initializationFailed("No self info")
        }

        let deviceID = DeviceIdentity.deriveUUID(from: selfInfo.publicKey)
        try await completeWiFiReconnection(
            session: newSession,
            transport: newTransport,
            deviceID: deviceID
        )
    }

    /// Completes WiFi reconnection by re-establishing services
    private func completeWiFiReconnection(
        session: MeshCoreSession,
        transport: WiFiTransport,
        deviceID: UUID
    ) async throws {
        let capabilities = try await session.queryDevice()
        guard let selfInfo = await session.currentSelfInfo else {
            throw ConnectionError.initializationFailed("No self info")
        }

        let newServices = ServiceContainer(
            session: session,
            modelContainer: modelContainer,
            appStateProvider: appStateProvider
        )
        await newServices.wireServices()
        self.services = newServices

        // Fetch existing device and auto-add config concurrently (independent operations)
        async let existingDeviceResult = newServices.dataStore.fetchDevice(id: deviceID)
        async let autoAddConfigResult = session.getAutoAddConfig()
        let existingDevice = try? await existingDeviceResult
        let autoAddConfig = (try? await autoAddConfigResult) ?? 0

        let device = createDevice(
            deviceID: deviceID,
            selfInfo: selfInfo,
            capabilities: capabilities,
            autoAddConfig: autoAddConfig,
            existingDevice: existingDevice
        )

        try await newServices.dataStore.saveDevice(DeviceDTO(from: device))
        self.connectedDevice = DeviceDTO(from: device)

        // Wire disconnection handler on new transport
        await transport.setDisconnectionHandler { [weak self] error in
            Task { @MainActor in
                await self?.handleWiFiDisconnection(error: error)
            }
        }

        await onConnectionReady?()
        await performInitialSync(deviceID: deviceID, services: newServices, context: "WiFi reconnect")

        // User may have disconnected while sync was in progress
        guard connectionIntent.wantsConnection else { return }

        await syncDeviceTimeIfNeeded()
        guard connectionIntent.wantsConnection else { return }

        currentTransportType = .wifi
        connectionState = .ready
        stopReconnectionWatchdog()
        startWiFiHeartbeat()
    }

    /// Checks if the WiFi connection is still alive (call on app foreground)
    public func checkWiFiConnectionHealth() async {
        // If a reconnect task is already running, let it finish
        if wifiReconnectTask != nil {
            logger.info("WiFi reconnection already in progress on foreground")
            return
        }

        // Case 1: We think we're connected but the transport died while backgrounded
        if currentTransportType == .wifi,
           connectionState == .ready,
           let wifiTransport {
            let isConnected = await wifiTransport.isConnected
            if !isConnected {
                logger.info("WiFi connection died while backgrounded")
                await handleWiFiDisconnection(error: nil)
                return
            }
        }

        // Case 2: Connection was lost and cleanup already ran while backgrounded,
        // but user still wants to be connected — attempt fresh reconnection
        if connectionState == .disconnected,
           connectionIntent.wantsConnection,
           let lastDeviceID = lastConnectedDeviceID {
            let dataStore = PersistenceStore(modelContainer: modelContainer)
            if let device = try? await dataStore.fetchDevice(id: lastDeviceID),
               let wifiMethod = device.connectionMethods.first(where: { $0.isWiFi }) {
                if case .wifi(let host, let port, _) = wifiMethod {
                    logger.info("WiFi foreground reconnect to \(host):\(port)")
                    do {
                        try await connectViaWiFi(host: host, port: port)
                    } catch {
                        logger.warning("WiFi foreground reconnect failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Called when the app enters background. Pauses foreground-only BLE operations.
    public func appDidEnterBackground() async {
        let transportName = switch currentTransportType {
        case .bluetooth: "bluetooth"
        case .wifi: "wifi"
        case nil: "none"
        }
        logger.info(
            "[BLE] Lifecycle transition: entering background, " +
            "transport: \(transportName), " +
            "connectionIntent: \(connectionIntent), " +
            "connectionState: \(String(describing: connectionState))"
        )
        await stateMachine.appDidEnterBackground()
        stopReconnectionWatchdog()
        let bleState = await stateMachine.centralManagerStateName
        let blePhase = await stateMachine.currentPhaseName
        logger.info(
            "[BLE] Lifecycle transition complete: backgrounded, " +
            "bleState: \(bleState), " +
            "blePhase: \(blePhase)"
        )
    }

    /// Called when the app becomes active. Reconciles BLE state and restarts
    /// foreground operations.
    public func appDidBecomeActive() async {
        let transportName = switch currentTransportType {
        case .bluetooth: "bluetooth"
        case .wifi: "wifi"
        case nil: "none"
        }
        logger.info(
            "[BLE] Lifecycle transition: becoming active, " +
            "transport: \(transportName), " +
            "connectionIntent: \(connectionIntent), " +
            "connectionState: \(String(describing: connectionState))"
        )
        await stateMachine.appDidBecomeActive()
        await checkBLEConnectionHealth()
        let bleState = await stateMachine.centralManagerStateName
        let blePhase = await stateMachine.currentPhaseName
        logger.info(
            "[BLE] Lifecycle transition complete: active health check finished, " +
            "connectionState: \(String(describing: connectionState)), " +
            "bleState: \(bleState), " +
            "blePhase: \(blePhase)"
        )

        guard currentTransportType == nil || currentTransportType == .bluetooth else { return }
        guard connectionIntent.wantsConnection, connectionState == .disconnected else { return }

        if await stateMachine.isAutoReconnecting {
            logger.info("[BLE] ConnectionManager: not re-arming watchdog on foreground (iOS auto-reconnect in progress)")
            return
        }

        startReconnectionWatchdog()
        logger.info("[BLE] ConnectionManager: re-armed watchdog on foreground while disconnected")
    }

    /// Attempts BLE reconnection if user expects to be connected but iOS auto-reconnect gave up.
    /// Call this when the app returns to foreground.
    public func checkBLEConnectionHealth() async {
        // Only check BLE connections
        guard currentTransportType == nil || currentTransportType == .bluetooth else { return }

        let deviceShort = lastConnectedDeviceID?.uuidString.prefix(8) ?? "none"
        let bleState = await stateMachine.centralManagerStateName
        let blePhase = await stateMachine.currentPhaseName
        logger.info("""
            [BLE] Foreground health check - \
            connectionIntent: \(connectionIntent), \
            lastDevice: \(deviceShort), \
            connectionState: \(String(describing: connectionState)), \
            bleState: \(bleState), \
            blePhase: \(blePhase)
            """)

        // Check if user expects to be connected
        guard connectionIntent.wantsConnection,
              let deviceID = lastConnectedDeviceID else { return }

        // Check actual BLE state - if connected at BLE level, no action needed
        let bleConnected = await stateMachine.isConnected
        if bleConnected {
            return
        }

        // Don't interfere if iOS auto-reconnect is still in progress
        if await stateMachine.isAutoReconnecting {
            logger.info("[BLE] Skipping foreground reconnect: iOS auto-reconnect still in progress")
            return
        }

        // Don't attempt reconnection when Bluetooth is off
        if await stateMachine.isBluetoothPoweredOff {
            logger.info("[BLE] Skipping foreground reconnect: Bluetooth is powered off")
            return
        }

        // Detect stale connection state: app thinks connected but BLE is actually disconnected
        // This happens when iOS terminates the BLE connection while app is suspended
        if connectionState == .ready || connectionState == .connected {
            logger.warning("[BLE] Detected stale connection state on foreground: connectionState=\(String(describing: connectionState)) but BLE disconnected, triggering cleanup")
            await handleConnectionLoss(deviceID: deviceID, error: nil)
        }

        // Don't reconnect if device is connected to another app
        if await isDeviceConnectedToOtherApp(deviceID) {
            let blePeripheralState = await stateMachine.currentPeripheralState ?? "none"
            persistDisconnectDiagnostic(
                "source=checkBLEConnectionHealth.otherAppConnected, " +
                "device=\(deviceID.uuidString.prefix(8)), " +
                "bleState=\(bleState), " +
                "blePhase=\(blePhase), " +
                "blePeripheralState=\(blePeripheralState), " +
                "intent=\(connectionIntent)"
            )

            // Ensure retries continue even when this method is called directly
            // (outside appDidBecomeActive's watchdog re-arm path).
            if reconnectionWatchdogTask == nil {
                startReconnectionWatchdog()
            }
            logger.info("[BLE] Skipping foreground reconnect: device connected to another app")
            return
        }

        logger.info("[BLE] Attempting foreground reconnection to \(deviceID.uuidString.prefix(8))")
        do {
            try await connect(to: deviceID)
        } catch {
            logger.warning("[BLE] Foreground reconnection failed: \(error.localizedDescription)")
        }
    }

    /// Performs initial sync with automatic resync loop on failure.
    /// - Parameters:
    ///   - deviceID: The device ID to sync
    ///   - services: The service container
    ///   - context: Optional context string for logging (e.g., "WiFi reconnect")
    ///   - forceFullSync: When true, forces complete data exchange regardless of sync state
    private func performInitialSync(
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
    private func startResyncLoop(deviceID: UUID, services: ServiceContainer, forceFullSync: Bool = false) {
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

    /// Triggers resync if connected but sync state is failed.
    /// Called when app returns to foreground.
    public func checkSyncHealth() async {
        guard connectionState == .ready,
              connectionIntent.wantsConnection,
              let services,
              let deviceID = connectedDevice?.id else { return }

        let syncCoordinator = services.syncCoordinator
        let syncState = syncCoordinator.state
        guard case .failed = syncState else { return }

        guard resyncTask == nil else {
            logger.info("Resync loop already running, skipping foreground trigger")
            return
        }

        logger.info("Foreground return: sync state is failed, starting resync loop")
        startResyncLoop(deviceID: deviceID, services: services)
    }

    // MARK: - Initialization

    /// Creates a new connection manager.
    /// - Parameters:
    ///   - modelContainer: The SwiftData model container for persistence
    ///   - stateMachine: Optional BLE state machine for testing. If nil, creates a real BLEStateMachine.
    public init(modelContainer: ModelContainer, stateMachine: (any BLEStateMachineProtocol)? = nil) {
        self.modelContainer = modelContainer

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

    // MARK: - Public Lifecycle Methods

    /// Activates the connection manager on app launch.
    /// Call this once during app initialization.
    public func activate() async {
        let lastDeviceShort = lastConnectedDeviceID?.uuidString.prefix(8) ?? "none"
        let bleState = await stateMachine.centralManagerStateName
        logger.info("""
            Activating ConnectionManager - \
            connectionIntent: \(connectionIntent), \
            lastConnectedDeviceID: \(lastDeviceShort), \
            connectionState: \(String(describing: connectionState)), \
            bleState: \(bleState)
            """)

        #if targetEnvironment(simulator)
        // Skip auto-reconnect if user explicitly disconnected
        if connectionIntent.isUserDisconnected {
            logger.info("Simulator: skipping auto-reconnect - user previously disconnected")
            return
        }
        // On simulator, skip ASK entirely and auto-reconnect to simulator device
        if let lastDeviceID = lastConnectedDeviceID,
           lastDeviceID == MockDataProvider.simulatorDeviceID {
            logger.info("Simulator: auto-reconnecting to mock device")
            connectionIntent = .wantsConnection()
            do {
                try await simulatorConnect()
            } catch {
                logger.warning("Simulator auto-reconnect failed: \(error.localizedDescription)")
            }
            return
        }
        // Simulator doesn't support real BLE devices - show connection UI for simulator pairing
        return
        #else
        // Activate AccessorySetupKit early; it is required for ASK events and iOS 26 state restoration.
        do {
            try await accessorySetupKit.activateSession()
        } catch {
            logger.error("Failed to activate AccessorySetupKit: \(error.localizedDescription)")
            // Don't return - WiFi doesn't need ASK
        }

        // Skip auto-reconnect if user explicitly disconnected
        if connectionIntent.isUserDisconnected {
            logger.info("Skipping auto-reconnect: user previously disconnected")
            return
        }

        // Auto-reconnect to last device if available
        if let lastDeviceID = lastConnectedDeviceID {
            logger.info("Attempting auto-reconnect to last device: \(lastDeviceID)")

            // Set intent before checking state
            connectionIntent = .wantsConnection()

            // Check if last device was WiFi - try WiFi first
            let dataStore = PersistenceStore(modelContainer: modelContainer)
            if let device = try? await dataStore.fetchDevice(id: lastDeviceID),
               let wifiMethod = device.connectionMethods.first(where: { $0.isWiFi }) {
                if case .wifi(let host, let port, _) = wifiMethod {
                    logger.info("Auto-reconnecting via WiFi to \(host):\(port)")
                    do {
                        try await connectViaWiFi(host: host, port: port)
                        return
                    } catch {
                        logger.warning("WiFi auto-reconnect failed: \(error.localizedDescription)")
                        // Fall through to try BLE
                    }
                }
            }

            // Activate BLE state machine before checking BLE state restoration status.
            // Must be after: ASK activation (line 700), explicit disconnect guard (line 709).
            // Must be before: isAutoReconnecting check, isDeviceConnectedToSystem.
            await stateMachine.activate()

            // If state machine is already auto-reconnecting (from state restoration),
            // let it complete rather than fighting with it
            if await stateMachine.isAutoReconnecting {
                let blePhase = await stateMachine.currentPhaseName
                let blePeripheralState = await stateMachine.currentPeripheralState ?? "none"
                logger.info(
                    "State restoration in progress - blePhase: \(blePhase), blePeripheralState: \(blePeripheralState), waiting for auto-reconnect"
                )
                return
            }

            if await stateMachine.isConnected, await stateMachine.connectedDeviceID == lastDeviceID {
                logger.info("State restoration complete - device already connected, waiting for session setup")
                return
            }

            // Check if device is connected to another app before auto-reconnect
            // Silently skip per HIG: minimize interruptions on app launch
            if await isDeviceConnectedToOtherApp(lastDeviceID) {
                logger.info("Auto-reconnect skipped: device connected to another app")
                let bleState = await stateMachine.centralManagerStateName
                let blePhase = await stateMachine.currentPhaseName
                let blePeripheralState = await stateMachine.currentPeripheralState ?? "none"
                persistDisconnectDiagnostic(
                    "source=activate.autoReconnectSkippedOtherApp, " +
                    "device=\(lastDeviceID.uuidString.prefix(8)), " +
                    "bleState=\(bleState), " +
                    "blePhase=\(blePhase), " +
                    "blePeripheralState=\(blePeripheralState), " +
                    "intent=\(connectionIntent)"
                )

                // Keep intent so we can retry on foreground/watchdog, but avoid
                // fighting another app's connection on launch.
                startReconnectionWatchdog()
                return
            }

            do {
                try await connect(to: lastDeviceID)
            } catch {
                logger.warning("Auto-reconnect failed: \(error.localizedDescription)")
                let bleState = await stateMachine.centralManagerStateName
                let blePhase = await stateMachine.currentPhaseName
                let blePeripheralState = await stateMachine.currentPeripheralState ?? "none"
                persistDisconnectDiagnostic(
                    "source=activate.autoReconnectFailed, " +
                    "device=\(lastDeviceID.uuidString.prefix(8)), " +
                    "bleState=\(bleState), " +
                    "blePhase=\(blePhase), " +
                    "blePeripheralState=\(blePeripheralState), " +
                    "error=\(error.localizedDescription), " +
                    "intent=\(connectionIntent)"
                )
                startReconnectionWatchdog()
                // Don't propagate - auto-reconnect failure is not fatal
            }
        } else {
            logger.info("No last connected device - skipping auto-reconnect")
        }
        #endif
    }

    /// Pairs a new device using AccessorySetupKit picker.
    /// - Returns: The device ID if pairing succeeds but connection fails (for recovery UI)
    /// - Throws: `PairingError` with device ID if connection fails after ASK pairing succeeds
    public func pairNewDevice() async throws {
        logger.info("Starting device pairing")

        // Clear intentional disconnect flag - user is explicitly pairing
        connectionIntent = .wantsConnection()
        connectionIntent.persist()

        // Show AccessorySetupKit picker
        let deviceID = try await accessorySetupKit.showPicker()

        // Set connecting state for immediate UI feedback
        connectionState = .connecting

        // Connect to the newly paired device
        do {
            try await connectAfterPairing(deviceID: deviceID)
        } catch {
            // Connection failed (e.g., wrong PIN causes "Authentication is insufficient")
            // Don't auto-remove - throw error with device ID so UI can offer recovery
            logger.error("Connection after pairing failed: \(error.localizedDescription)")
            connectionState = .disconnected
            throw PairingError.connectionFailed(deviceID: deviceID, underlying: error)
        }
    }

    /// Removes a device that failed to connect after pairing.
    /// Call this when user explicitly chooses to remove and retry.
    /// - Parameter deviceID: The device ID from `PairingError.connectionFailed`
    public func removeFailedPairing(deviceID: UUID) async {
        logger.info("Removing failed pairing for device: \(deviceID)")

        // Remove from ASK
        if let accessory = accessorySetupKit.accessory(for: deviceID) {
            do {
                try await accessorySetupKit.removeAccessory(accessory)
                logger.info("Removed device from ASK")
            } catch {
                logger.warning("Failed to remove from ASK: \(error.localizedDescription)")
            }
        }

        // Clean up SwiftData (may not exist for fresh pairing)
        let dataStore = PersistenceStore(modelContainer: modelContainer)
        try? await dataStore.deleteDevice(id: deviceID)

        // Clear persisted connection if needed
        if lastConnectedDeviceID == deviceID {
            clearPersistedConnection()
        }
    }

    /// Connects to a previously paired device.
    ///
    /// This method handles all connection scenarios:
    /// - If disconnected: connects to the device
    /// - If already connected to this device: no-op
    /// - If connected to a different device: switches to the new device
    ///
    /// - Parameters:
    ///   - deviceID: The UUID of the device to connect to
    ///   - forceFullSync: Whether to force a full sync instead of incremental
    ///   - forceReconnect: When `true`, bypasses the circuit breaker (user-initiated)
    /// - Throws: Connection errors
    public func connect(to deviceID: UUID, forceFullSync: Bool = false, forceReconnect: Bool = false) async throws {
        // Circuit breaker: prevent rapid reconnection loops after repeated failures
        guard shouldAllowConnection(force: forceReconnect) else {
            logger.info("[BLE] Circuit breaker open, rejecting connection to \(deviceID.uuidString.prefix(8))")
            throw BLEError.connectionFailed("Connection blocked by circuit breaker (cooling down)")
        }

        // Prevent concurrent connection attempts
        if connectionState == .connecting {
            logger.info("Connection already in progress, ignoring request for \(deviceID)")
            return
        }

        // Handle already-connected cases
        if connectionState != .disconnected {
            if connectedDevice?.id == deviceID {
                logger.info("Already connected to device: \(deviceID)")
                return
            }
            // Connected to different device - switch to new one
            logger.info("Switching from current device to: \(deviceID)")
            try await switchDevice(to: deviceID)
            return
        }

        // Handle state restoration auto-reconnect
        if await stateMachine.isAutoReconnecting {
            let restoringDeviceID = await stateMachine.connectedDeviceID
            let blePhase = await stateMachine.currentPhaseName
            let blePeripheralState = await stateMachine.currentPeripheralState ?? "none"

            if restoringDeviceID != deviceID {
                logger.info("Cancelling state restoration auto-reconnect to \(restoringDeviceID?.uuidString ?? "unknown") to connect to \(deviceID)")
                await transport.disconnect()
            } else {
                // Same device - let auto-reconnect complete instead of racing with it.
                // The reconnection handler will create the session when auto-reconnect succeeds.
                // Preserve user intent so the watchdog can retry if auto-reconnect fails.
                connectionIntent = .wantsConnection(forceFullSync: forceFullSync)
                connectionIntent.persist()
                // Show connecting UI so the user sees their tap did something
                if connectionState != .connecting {
                    connectionState = .connecting
                }
                // Re-arm timeout in case the previous one already fired
                reconnectionCoordinator.restartTimeout(deviceID: deviceID)
                logger.warning(
                    "[BLE] Deferring to iOS auto-reconnect for device \(deviceID.uuidString.prefix(8)) - connectionState: \(String(describing: connectionState)), blePhase: \(blePhase), blePeripheralState: \(blePeripheralState)"
                )
                return
            }
        }

        // Check for other app connection before changing state
        if await isDeviceConnectedToOtherApp(deviceID) {
            throw BLEError.deviceConnectedToOtherApp
        }

        // Clear intentional disconnect flag before changing state,
        // so the didSet invariant check sees consistent state
        connectionIntent = .wantsConnection(forceFullSync: forceFullSync)
        connectionIntent.persist()

        // Set connecting state for immediate UI feedback
        connectionState = .connecting

        logger.info("Connecting to device: \(deviceID)")

        // Cancel any pending auto-reconnect timeout and clear device identity
        reconnectionCoordinator.cancelTimeout()
        reconnectionCoordinator.clearReconnectingDevice()

        do {
            // Validate device is still registered with ASK
            if accessorySetupKit.isSessionActive {
                let isRegistered = accessorySetupKit.pairedAccessories.contains {
                    $0.bluetoothIdentifier == deviceID
                }

                if !isRegistered {
                    await logDeviceNotFoundDiagnostics(deviceID: deviceID, context: "connect(to:) ASK paired accessories mismatch")
                    throw ConnectionError.deviceNotFound
                }
            }

            // Attempt connection with retry
            try await connectWithRetry(deviceID: deviceID, maxAttempts: 4)
        } catch {
            // Differentiate cancellation in logs
            if error is CancellationError {
                logger.info("Connection cancelled")
            } else {
                logger.warning("Connection failed: \(error.localizedDescription)")
            }
            connectionState = .disconnected
            throw error
        }
    }

    /// Disconnects from the current device.
    /// - Parameter reason: The reason for disconnecting (for debugging)
    public func disconnect(reason: DisconnectReason = .userInitiated) async {
        let initialState = String(describing: connectionState)
        let transportName = switch currentTransportType {
        case .bluetooth: "bluetooth"
        case .wifi: "wifi"
        case nil: "none"
        }
        let activeDevice = connectedDevice?.id.uuidString.prefix(8) ?? "none"

        logger.info(
            "Disconnecting from device (" +
            "reason: \(reason.rawValue), " +
            "transport: \(transportName), " +
            "device: \(activeDevice), " +
            "initialState: \(initialState), " +
            "intent: \(connectionIntent)" +
            ")"
        )

        // Cancel any pending auto-reconnect timeout and clear device identity
        reconnectionCoordinator.cancelTimeout()
        reconnectionCoordinator.clearReconnectingDevice()

        // Cancel any WiFi reconnection in progress
        cancelWiFiReconnection()

        // Stop WiFi heartbeat
        stopWiFiHeartbeat()

        // Stop reconnection watchdog
        stopReconnectionWatchdog()

        cancelResyncLoop()

        // Only clear user intent for user-initiated disconnects
        switch reason {
        case .userInitiated, .statusMenuDisconnectTap, .forgetDevice, .deviceRemovedFromSettings, .factoryReset, .switchingDevice:
            connectionIntent = .userDisconnected
            connectionIntent.persist()
        case .resyncFailed, .wifiAddressChange, .wifiReconnectPrep, .pairingFailed:
            // Preserve .wantsConnection so health check can retry
            break
        }

        // Mark room sessions disconnected before tearing down services
        let remoteNodeService = services?.remoteNodeService
        if let remoteNodeService {
            _ = await remoteNodeService.handleBLEDisconnection()
            sessionsAwaitingReauth = []
        }

        // Stop event monitoring
        await services?.stopEventMonitoring()

        // Reset sync state and clear notification suppression (safety net)
        if let services {
            await services.syncCoordinator.onDisconnected(services: services)
        }

        // Stop session
        await session?.stop()

        // Disconnect appropriate transport based on current type
        if let wifiTransport {
            await wifiTransport.disconnect()
            self.wifiTransport = nil
        } else {
            await transport.disconnect()
        }

        // Clear transport type
        currentTransportType = nil

        // Clear state
        await cleanupConnection()

        persistDisconnectDiagnostic(
            "source=disconnect(reason), " +
            "reason=\(reason.rawValue), " +
            "transport=\(transportName), " +
            "device=\(activeDevice), " +
            "initialState=\(initialState), " +
            "finalState=\(String(describing: connectionState)), " +
            "intent=\(connectionIntent)"
        )

        logger.info(
            "Disconnected (" +
            "reason: \(reason.rawValue), " +
            "transport: \(transportName), " +
            "device: \(activeDevice), " +
            "initialState: \(initialState), " +
            "finalState: \(String(describing: connectionState)), " +
            "intent: \(connectionIntent)" +
            ")"
        )
    }

    /// Connects to the simulator device with mock data.
    /// Used for simulator builds and demo mode on device.
    public func simulatorConnect() async throws {
        logger.info("Starting simulator connection")

        connectionIntent = .wantsConnection()
        connectionIntent.persist()
        connectionState = .connecting

        do {
            // Connect simulator mode
            await simulatorMode.connect()

            // Create services with a placeholder session
            // Note: We need a MeshCoreSession but won't actually use it for communication
            // The mock data is seeded directly into the persistence store
            let mockTransport = SimulatorMockTransport()
            let session = MeshCoreSession(transport: mockTransport)
            self.session = session

            // Create services
            let newServices = ServiceContainer(
                session: session,
                modelContainer: modelContainer,
                appStateProvider: appStateProvider
            )
            await newServices.wireServices()
                self.services = newServices

            // Seed mock data
            try await simulatorMode.seedDataStore(newServices.dataStore)

            // Set connected device
            self.connectedDevice = MockDataProvider.simulatorDevice

            // Persist for auto-reconnect
            persistConnection(
                deviceID: MockDataProvider.simulatorDeviceID,
                deviceName: "PocketMesh Sim"
            )

            // Notify observers
            await onConnectionReady?()

            connectionState = .ready
            logger.info("Simulator connection complete")
        } catch {
            // Cleanup on failure
            await cleanupConnection()
            throw error
        }
    }

    /// Whether the last connection was a simulator connection
    public var wasSimulatorConnection: Bool {
        lastConnectedDeviceID == MockDataProvider.simulatorDeviceID
    }

    /// Connects to a device via WiFi/TCP.
    ///
    /// - Parameters:
    ///   - host: The hostname or IP address of the device
    ///   - port: The TCP port to connect to
    ///   - forceFullSync: When true, performs a complete sync ignoring cached timestamps
    /// - Throws: Connection or session errors
    public func connectViaWiFi(host: String, port: UInt16, forceFullSync: Bool = false) async throws {
        logger.info("Connecting via WiFi to \(host):\(port)")

        // Disconnect existing connection if any
        if connectionState != .disconnected {
            await disconnect(reason: .wifiReconnectPrep)
        }

        connectionIntent = .wantsConnection()
        connectionIntent.persist()
        connectionState = .connecting

        do {
            // Create and configure WiFi transport
            let newWiFiTransport = WiFiTransport()
            await newWiFiTransport.setConnectionInfo(host: host, port: port)
            wifiTransport = newWiFiTransport

            // Connect the transport
            try await newWiFiTransport.connect()

            connectionState = .connected

            // Create session (same as BLE)
            let newSession = MeshCoreSession(transport: newWiFiTransport)
            self.session = newSession

            let (meshCoreSelfInfo, deviceCapabilities) = try await initializeSession(newSession)

            // Derive device ID from public key (WiFi devices don't have Bluetooth UUIDs)
            let deviceID = DeviceIdentity.deriveUUID(from: meshCoreSelfInfo.publicKey)

            // Create services
            let newServices = ServiceContainer(
                session: newSession,
                modelContainer: modelContainer,
                appStateProvider: appStateProvider
            )
            await newServices.wireServices()
            self.services = newServices

            // Fetch existing device and auto-add config concurrently (independent operations)
            async let existingDeviceResult = newServices.dataStore.fetchDevice(id: deviceID)
            async let autoAddConfigResult = newSession.getAutoAddConfig()
            let existingDevice = try? await existingDeviceResult
            let autoAddConfig = (try? await autoAddConfigResult) ?? 0

            // Create WiFi connection method
            let wifiMethod = ConnectionMethod.wifi(host: host, port: port, displayName: nil)

            // Create and save device
            let device = createDevice(
                deviceID: deviceID,
                selfInfo: meshCoreSelfInfo,
                capabilities: deviceCapabilities,
                autoAddConfig: autoAddConfig,
                existingDevice: existingDevice,
                connectionMethods: [wifiMethod]
            )

            try await newServices.dataStore.saveDevice(DeviceDTO(from: device))
            self.connectedDevice = DeviceDTO(from: device)

            // Persist connection for potential future use
            persistConnection(deviceID: deviceID, deviceName: meshCoreSelfInfo.name)

            await onConnectionReady?()
            await performInitialSync(deviceID: deviceID, services: newServices, forceFullSync: forceFullSync)

            // User may have disconnected while sync was in progress
            guard connectionIntent.wantsConnection else { return }

            await syncDeviceTimeIfNeeded()
            guard connectionIntent.wantsConnection else { return }

            // Wire disconnection handler for auto-reconnect
            await newWiFiTransport.setDisconnectionHandler { [weak self] error in
                Task { @MainActor in
                    await self?.handleWiFiDisconnection(error: error)
                }
            }

            currentTransportType = .wifi
            connectionState = .ready
            stopReconnectionWatchdog()

            startWiFiHeartbeat()
            logger.info("WiFi connection complete - device ready")

        } catch {
            // Cleanup on failure
            if let wifiTransport {
                await wifiTransport.disconnect()
                self.wifiTransport = nil
            }
            currentTransportType = nil
            await cleanupConnection()
            throw error
        }
    }

    /// Switches to a different device.
    ///
    /// - Parameter deviceID: UUID of the new device to connect to
    public func switchDevice(to deviceID: UUID) async throws {
        logger.info("Switching to device: \(deviceID)")

        // Update intent
        connectionIntent = .wantsConnection()
        connectionIntent.persist()

        // Validate device is registered with ASK
        if accessorySetupKit.isSessionActive {
            let isRegistered = accessorySetupKit.pairedAccessories.contains {
                $0.bluetoothIdentifier == deviceID
            }
            if !isRegistered {
                await logDeviceNotFoundDiagnostics(deviceID: deviceID, context: "switchDevice ASK paired accessories mismatch")
                throw ConnectionError.deviceNotFound
            }
        }

        // Reset sync state before destroying services to prevent stuck "Syncing" pill
        if let services {
            await services.syncCoordinator.onDisconnected(services: services)
        }

        // Stop current services
        await services?.stopEventMonitoring()
        await session?.stop()

        // Switch transport
        logger.info("[BLE] switchDevice: state → .connecting for device: \(deviceID.uuidString.prefix(8))")
        connectionState = .connecting
        try await transport.switchDevice(to: deviceID)
        logger.info("[BLE] switchDevice: state → .connected for device: \(deviceID.uuidString.prefix(8))")
        connectionState = .connected

        // Re-create session with existing transport
        let newSession = MeshCoreSession(transport: transport)
        self.session = newSession

        let (meshCoreSelfInfo, deviceCapabilities) = try await initializeSession(newSession)

        // Configure BLE write pacing based on device platform
        await configureBLEPacing(for: deviceCapabilities)

        // Create and wire services
        let newServices = ServiceContainer(
            session: newSession,
            modelContainer: modelContainer,
            appStateProvider: appStateProvider
        )
        await newServices.wireServices()
        self.services = newServices

        // Fetch existing device and auto-add config concurrently (independent operations)
        async let existingDeviceResult = newServices.dataStore.fetchDevice(id: deviceID)
        async let autoAddConfigResult = newSession.getAutoAddConfig()
        let existingDevice = try? await existingDeviceResult
        let autoAddConfig = (try? await autoAddConfigResult) ?? 0

        // Create and save device
        let device = createDevice(
            deviceID: deviceID,
            selfInfo: meshCoreSelfInfo,
            capabilities: deviceCapabilities,
            autoAddConfig: autoAddConfig,
            existingDevice: existingDevice
        )

        try await newServices.dataStore.saveDevice(DeviceDTO(from: device))
        self.connectedDevice = DeviceDTO(from: device)

        // Persist connection for auto-reconnect
        persistConnection(deviceID: deviceID, deviceName: meshCoreSelfInfo.name)

        // Notify observers BEFORE sync starts so they can wire callbacks
        await onConnectionReady?()
        await performInitialSync(deviceID: deviceID, services: newServices, context: "Device switch", forceFullSync: true)

        // User may have disconnected while sync was in progress
        guard connectionIntent.wantsConnection else { return }

        await syncDeviceTimeIfNeeded()
        guard connectionIntent.wantsConnection else { return }

        currentTransportType = .bluetooth
        connectionState = .ready
        stopReconnectionWatchdog()
        logger.info("Device switch complete - device ready")
    }

    /// Forgets the device, removing it from paired accessories and local storage.
    /// - Throws: `ConnectionError.deviceNotFound` if no device is connected
    public func forgetDevice() async throws {
        guard let deviceID = connectedDevice?.id else {
            throw ConnectionError.notConnected
        }

        guard let accessory = accessorySetupKit.accessory(for: deviceID) else {
            throw ConnectionError.deviceNotFound
        }

        logger.info("Forgetting device: \(deviceID)")

        // Remove from paired accessories first (most important operation)
        try await accessorySetupKit.removeAccessory(accessory)

        // Disconnect
        await disconnect(reason: .forgetDevice)

        // Delete from SwiftData (cascades to contacts, messages, channels, trace paths)
        let dataStore = PersistenceStore(modelContainer: modelContainer)
        do {
            try await dataStore.deleteDevice(id: deviceID)
        } catch {
            // Log but don't fail - ASK removal succeeded, data cleanup is best-effort
            logger.warning("Failed to delete device data from SwiftData: \(error.localizedDescription)")
        }

        logger.info("Device forgotten")
    }

    /// Forgets a device by ID, removing it from paired accessories and local storage.
    /// Best-effort cleanup — does not throw. Use after factory reset when the device
    /// may have already disconnected.
    public func forgetDevice(id: UUID) async {
        logger.info("Forgetting device by ID: \(id)")

        // Remove from paired accessories (most important — without this, re-pairing fails)
        if let accessory = accessorySetupKit.accessory(for: id) {
            do {
                try await accessorySetupKit.removeAccessory(accessory)
            } catch {
                logger.warning("Failed to remove accessory from ASK: \(error.localizedDescription)")
            }
        }

        // Always disconnect — even if BLE already dropped, this cancels any pending
        // auto-reconnect, sets connectionIntent, and cleans up state.
        await disconnect(reason: .factoryReset)

        // Delete from SwiftData
        let dataStore = PersistenceStore(modelContainer: modelContainer)
        do {
            try await dataStore.deleteDevice(id: id)
        } catch {
            logger.warning("Failed to delete device data from SwiftData: \(error.localizedDescription)")
        }

        logger.info("Device forgotten by ID: \(id)")
    }

    /// Returns the number of non-favorite contacts for the current device.
    public func unfavoritedNodeCount() async throws -> Int {
        guard let deviceID = connectedDevice?.id else {
            throw ConnectionError.notConnected
        }

        let dataStore = PersistenceStore(modelContainer: modelContainer)
        let allContacts = try await dataStore.fetchContacts(deviceID: deviceID)
        return allContacts.filter { !$0.isFavorite }.count
    }

    /// Removes all non-favorite contacts from the device and app, along with their messages.
    /// For room/repeater contacts, also removes the associated RemoteNodeSession.
    /// - Returns: Count of removed vs total non-favorite contacts
    /// - Throws: `ConnectionError.notConnected` if no device is connected
    public func removeUnfavoritedNodes() async throws -> RemoveUnfavoritedResult {
        guard let deviceID = connectedDevice?.id else {
            throw ConnectionError.notConnected
        }

        guard let services else {
            throw ConnectionError.notConnected
        }

        let dataStore = PersistenceStore(modelContainer: modelContainer)
        let allContacts = try await dataStore.fetchContacts(deviceID: deviceID)
        let unfavorited = allContacts.filter { !$0.isFavorite }

        if unfavorited.isEmpty {
            return RemoveUnfavoritedResult(removed: 0, total: 0)
        }

        var removedCount = 0

        for contact in unfavorited {
            try Task.checkCancellation()

            do {
                try await services.contactService.removeContact(
                    deviceID: deviceID,
                    publicKey: contact.publicKey
                )
                removedCount += 1
            } catch ContactServiceError.contactNotFound {
                // Contact exists locally but not on device — run full local cleanup
                do {
                    try await services.contactService.removeLocalContact(
                        contactID: contact.id,
                        publicKey: contact.publicKey
                    )
                    removedCount += 1
                    logger.info("Contact not found on device, cleaned up locally: \(contact.name)")
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    logger.warning("Failed to clean up local data for \(contact.name): \(error.localizedDescription)")
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Connection error — stop the loop, report partial progress
                logger.warning("Failed to remove contact \(contact.name): \(error.localizedDescription)")
                return RemoveUnfavoritedResult(removed: removedCount, total: unfavorited.count)
            }
        }

        return RemoveUnfavoritedResult(removed: removedCount, total: unfavorited.count)
    }

    /// Clears all stale pairings from AccessorySetupKit.
    /// Use when a device has been factory-reset but iOS still has the old pairing.
    public func clearStalePairings() async {
        let accessories = self.accessorySetupKit.pairedAccessories
        logger.info("Clearing \(accessories.count) stale pairings")

        for accessory in accessories {
            do {
                try await self.accessorySetupKit.removeAccessory(accessory)
            } catch {
                // Continue trying to remove others even if one fails
                logger.warning("Failed to remove accessory: \(error.localizedDescription)")
            }
        }

        logger.info("Stale pairings cleared")
    }

    /// Updates the connected device with new settings from SelfInfo.
    /// Called by SettingsService after device settings are successfully changed.
    /// Also persists to SwiftData so changes appear in Connect Device sheet.
    public func updateDevice(from selfInfo: MeshCore.SelfInfo) {
        guard let device = connectedDevice else { return }
        let updated = device.updating(from: selfInfo)
        connectedDevice = updated

        // Persist to SwiftData
        Task {
            try? await services?.dataStore.saveDevice(updated)
        }
    }

    /// Updates the connected device with a new DeviceDTO.
    /// Called by DeviceService after local device settings are successfully changed.
    public func updateDevice(with deviceDTO: DeviceDTO) {
        connectedDevice = deviceDTO
    }

    /// Updates the connected device's auto-add config.
    /// Called by SettingsService after auto-add config is successfully changed.
    public func updateAutoAddConfig(_ config: UInt8) {
        guard var device = connectedDevice else { return }
        device = device.withAutoAddConfig(config)
        connectedDevice = device
    }

    /// Updates the connected device's client repeat state.
    /// Called by SettingsService after client repeat is successfully changed.
    public func updateClientRepeat(_ enabled: Bool) {
        guard let device = connectedDevice else { return }
        let updated = device.withClientRepeat(enabled)
        connectedDevice = updated

        Task {
            do { try await services?.dataStore.saveDevice(updated) }
            catch { logger.error("Failed to persist client repeat state: \(error)") }
        }
    }

    /// Saves the connected device's current radio settings as pre-repeat settings.
    /// Called before enabling repeat mode so settings can be restored later.
    public func savePreRepeatSettings() {
        guard let device = connectedDevice else { return }
        let updated = device.savingPreRepeatSettings()
        connectedDevice = updated

        Task {
            do { try await services?.dataStore.saveDevice(updated) }
            catch { logger.error("Failed to persist pre-repeat settings: \(error)") }
        }
    }

    /// Clears the connected device's pre-repeat settings after restoration.
    public func clearPreRepeatSettings() {
        guard let device = connectedDevice else { return }
        let updated = device.clearingPreRepeatSettings()
        connectedDevice = updated

        Task {
            do { try await services?.dataStore.saveDevice(updated) }
            catch { logger.error("Failed to persist cleared pre-repeat settings: \(error)") }
        }
    }

    /// Checks if an accessory is registered with AccessorySetupKit.
    /// - Parameter deviceID: The Bluetooth UUID of the device
    /// - Returns: `true` if the accessory is available for connection
    public func hasAccessory(for deviceID: UUID) -> Bool {
        accessorySetupKit.accessory(for: deviceID) != nil
    }

    /// Fetches all previously paired devices from storage.
    /// Available even when disconnected, for device selection UI.
    public func fetchSavedDevices() async throws -> [DeviceDTO] {
        logger.info("fetchSavedDevices called, connectionState: \(String(describing: self.connectionState))")
        let dataStore = PersistenceStore(modelContainer: modelContainer)
        let devices = try await dataStore.fetchDevices()
        logger.info("fetchSavedDevices returning \(devices.count) devices")
        return devices
    }

    /// Deletes a previously paired device and all its associated data.
    /// - Parameter id: The device UUID to delete
    public func deleteDevice(id: UUID) async throws {
        logger.info("deleteDevice called for device: \(id)")
        let dataStore = PersistenceStore(modelContainer: modelContainer)
        try await dataStore.deleteDevice(id: id)
        logger.info("deleteDevice completed for device: \(id)")
    }

    /// Returns paired accessories from AccessorySetupKit.
    /// Use as fallback when SwiftData has no device records.
    public var pairedAccessoryInfos: [(id: UUID, name: String)] {
        accessorySetupKit.pairedAccessories.compactMap { accessory in
            guard let id = accessory.bluetoothIdentifier else { return nil }
            return (id: id, name: accessory.displayName)
        }
    }

    /// Renames the currently connected device via AccessorySetupKit.
    /// - Throws: `ConnectionError.notConnected` if no device is connected
    public func renameCurrentDevice() async throws {
        guard let deviceID = connectedDevice?.id else {
            throw ConnectionError.notConnected
        }

        guard let accessory = accessorySetupKit.accessory(for: deviceID) else {
            throw ConnectionError.deviceNotFound
        }

        try await accessorySetupKit.renameAccessory(accessory)
    }

    /// Connects with retry logic for reconnection scenarios
    private func connectWithRetry(deviceID: UUID, maxAttempts: Int) async throws {
        var lastError: Error = ConnectionError.connectionFailed("Unknown error")

        for attempt in 1...maxAttempts {
            do {
                try await performConnection(deviceID: deviceID)

                recordConnectionSuccess()
                if attempt > 1 {
                    logger.info("Reconnection succeeded on attempt \(attempt)")
                }
                return

            } catch {
                lastError = error

                // BLE precondition failures won't resolve between retries.
                // Exit without retrying or tripping the circuit breaker so that
                // onBluetoothPoweredOn can reconnect cleanly when BLE comes back.
                if let bleError = error as? BLEError {
                    switch bleError {
                    case .bluetoothPoweredOff, .bluetoothUnavailable, .bluetoothUnauthorized:
                        throw error
                    default:
                        break
                    }
                }

                if isDeviceNotFoundError(error) {
                    await logDeviceNotFoundDiagnostics(deviceID: deviceID, context: "connectWithRetry attempt \(attempt)")
                }

                // Diagnostic: Log BLE state on each failed attempt
                let blePhase = await stateMachine.currentPhaseName
                let blePeripheralState = await stateMachine.currentPeripheralState ?? "none"
                let backoffDelay = attempt < maxAttempts ? 0.3 * pow(2.0, Double(attempt - 1)) : 0.0
                logger.warning(
                    "[BLE] Reconnection attempt \(attempt)/\(maxAttempts) failed - error: \(error.localizedDescription), blePhase: \(blePhase), blePeripheralState: \(blePeripheralState), nextBackoff: \(String(format: "%.2f", backoffDelay))s"
                )

                // Clean up resources but keep state as .connecting
                await cleanupResources()
                await transport.disconnect()

                if attempt < maxAttempts {
                    // Backoff delay - state remains .connecting
                    let baseDelay = 0.3 * pow(2.0, Double(attempt - 1))
                    let jitter = Double.random(in: 0...0.1) * baseDelay
                    try await Task.sleep(for: .seconds(baseDelay + jitter))
                }
            }
        }

        // All retries exhausted - trip circuit breaker, then throw
        recordConnectionFailure()

        // Diagnostic: Log final failure state
        let finalBlePhase = await stateMachine.currentPhaseName
        let finalBlePeripheralState = await stateMachine.currentPeripheralState ?? "none"
        logger.error(
            "[BLE] All \(maxAttempts) reconnection attempts exhausted - lastError: \(lastError.localizedDescription), blePhase: \(finalBlePhase), blePeripheralState: \(finalBlePeripheralState)"
        )

        throw lastError
    }

    // MARK: - Private Connection Methods

    /// Starts a session and queries device capabilities.
    private func initializeSession(
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
    private func syncDeviceTimeIfNeeded() async {
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

    /// Connects to a device immediately after ASK pairing with retry logic
    private func connectAfterPairing(deviceID: UUID, maxAttempts: Int = 4) async throws {
        logger.info("[BLE] connectAfterPairing: device=\(deviceID.uuidString.prefix(8)), maxAttempts=\(maxAttempts)")
        var lastError: Error = ConnectionError.connectionFailed("Unknown error")

        for attempt in 1...maxAttempts {
            // Allow ASK/CoreBluetooth bond to register on first attempt
            if attempt == 1 {
                try await Task.sleep(for: .milliseconds(100))
            }

            do {
                try await performConnection(deviceID: deviceID)

                if attempt > 1 {
                    logger.info("Connection succeeded on attempt \(attempt)")
                }
                return

            } catch {
                lastError = error
                if isDeviceNotFoundError(error) {
                    await logDeviceNotFoundDiagnostics(deviceID: deviceID, context: "connectAfterPairing attempt \(attempt)")
                }
                logger.warning("Connection attempt \(attempt) failed: \(error.localizedDescription)")

                // Clean up resources but keep state as .connecting
                await cleanupResources()
                await transport.disconnect()

                if attempt < maxAttempts {
                    // Backoff delay - state remains .connecting
                    let baseDelay = 0.3 * pow(2.0, Double(attempt - 1))
                    let jitter = Double.random(in: 0...0.1) * baseDelay
                    try await Task.sleep(for: .seconds(baseDelay + jitter))
                }
            }
        }

        // All retries exhausted - caller's catch block sets .disconnected
        throw lastError
    }

    /// Performs the actual connection to a device
    private func performConnection(deviceID: UUID) async throws {
        // Note: connectionState is already .connecting (set by caller)

        // Stop any existing session to prevent multiple receive loops racing for transport data
        await session?.stop()
        session = nil

        // Set device ID and connect
        await transport.setDeviceID(deviceID)
        try await transport.connect()

        logger.info("[BLE] State → .connected (transport connected for device: \(deviceID.uuidString.prefix(8)))")
        connectionState = .connected

        // Create session
        let newSession = MeshCoreSession(transport: transport)
        self.session = newSession

        let (meshCoreSelfInfo, deviceCapabilities) = try await initializeSession(newSession)

        // Configure BLE write pacing based on device platform
        await configureBLEPacing(for: deviceCapabilities)

        // Create services
        let newServices = ServiceContainer(
            session: newSession,
            modelContainer: modelContainer,
            appStateProvider: appStateProvider
        )
        await newServices.wireServices()
        self.services = newServices

        // Fetch existing device and auto-add config concurrently (independent operations)
        async let existingDeviceResult = newServices.dataStore.fetchDevice(id: deviceID)
        async let autoAddConfigResult = newSession.getAutoAddConfig()
        let existingDevice = try? await existingDeviceResult
        let autoAddConfig = (try? await autoAddConfigResult) ?? 0

        // Create and save device
        let device = createDevice(
            deviceID: deviceID,
            selfInfo: meshCoreSelfInfo,
            capabilities: deviceCapabilities,
            autoAddConfig: autoAddConfig,
            existingDevice: existingDevice
        )

        try await newServices.dataStore.saveDevice(DeviceDTO(from: device))
        self.connectedDevice = DeviceDTO(from: device)

        // Persist connection for auto-reconnect
        persistConnection(deviceID: deviceID, deviceName: meshCoreSelfInfo.name)

        // Notify observers BEFORE sync starts so they can wire callbacks
        // (e.g., AppState needs to set sync activity callbacks for the syncing pill)
        await onConnectionReady?()
        let shouldForceFullSync: Bool
        if case .wantsConnection(let force) = connectionIntent {
            shouldForceFullSync = force
            if force { connectionIntent = .wantsConnection() }
        } else {
            shouldForceFullSync = false
        }
        await performInitialSync(deviceID: deviceID, services: newServices, forceFullSync: shouldForceFullSync)

        // User may have disconnected while sync was in progress
        guard connectionIntent.wantsConnection else { return }

        await syncDeviceTimeIfNeeded()
        guard connectionIntent.wantsConnection else { return }

        currentTransportType = .bluetooth
        connectionState = .ready
        stopReconnectionWatchdog()
        logger.info("Connection complete - device ready")
    }

    private func logDeviceNotFoundDiagnostics(deviceID: UUID, context: String) async {
        let bleState = await stateMachine.centralManagerStateName
        let blePhase = await stateMachine.currentPhaseName
        let lastDeviceShort = lastConnectedDeviceID?.uuidString.prefix(8) ?? "none"
        let pairedAccessories = accessorySetupKit.pairedAccessories
        let pairedSummary = pairedAccessories.prefix(5).compactMap { accessory -> String? in
            guard let id = accessory.bluetoothIdentifier else { return nil }
            return "\(accessory.displayName)(\(id.uuidString.prefix(8)))"
        }
        let pairedSummaryText = pairedSummary.isEmpty ? "none" : pairedSummary.joined(separator: ", ")

        logger.warning(
            "[BLE] Device not found diagnostics (\(context)) - device: \(deviceID.uuidString.prefix(8)), lastDevice: \(lastDeviceShort), connectionIntent: \(connectionIntent), bleState: \(bleState), blePhase: \(blePhase), askActive: \(accessorySetupKit.isSessionActive), pairedCount: \(pairedAccessories.count), paired: \(pairedSummaryText)"
        )
    }

    private func isDeviceNotFoundError(_ error: Error) -> Bool {
        if case ConnectionError.deviceNotFound = error { return true }
        if case BLEError.deviceNotFound = error { return true }
        return false
    }

    /// Creates a Device from MeshCore types
    private func createDevice(
        deviceID: UUID,
        selfInfo: MeshCore.SelfInfo,
        capabilities: MeshCore.DeviceCapabilities,
        autoAddConfig: UInt8,
        existingDevice: DeviceDTO? = nil,
        connectionMethods: [ConnectionMethod] = []
    ) -> Device {
        // Merge new connection methods with existing ones, avoiding duplicates
        var mergedMethods = existingDevice?.connectionMethods ?? []
        for method in connectionMethods where !mergedMethods.contains(method) {
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
            preRepeatFrequency: existingDevice?.preRepeatFrequency,
            preRepeatBandwidth: existingDevice?.preRepeatBandwidth,
            preRepeatSpreadingFactor: existingDevice?.preRepeatSpreadingFactor,
            preRepeatCodingRate: existingDevice?.preRepeatCodingRate,
            manualAddContacts: selfInfo.manualAddContacts,
            autoAddConfig: autoAddConfig,
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
    private func configureBLEPacing(for capabilities: MeshCore.DeviceCapabilities) async {
        let platform = DevicePlatform.detect(from: capabilities.model)
        let pacing = platform.recommendedWritePacing
        await stateMachine.setWritePacingDelay(pacing)
        if pacing > 0 {
            logger.info("[BLE] Platform detected: \(capabilities.model) -> \(platform), write pacing: \(pacing)s")
        }
    }

    // MARK: - Connection Loss Handling

    /// Handles unexpected connection loss
    private func handleConnectionLoss(deviceID: UUID, error: Error?) async {
        let stateBeforeLoss = connectionState
        var errorInfo = "none"
        if let error = error as NSError? {
            errorInfo = "domain=\(error.domain), code=\(error.code), desc=\(error.localizedDescription)"
        }
        logger.warning("[BLE] Connection lost: \(deviceID.uuidString.prefix(8)), currentState: \(String(describing: connectionState)), error: \(errorInfo)")

        // Cancel any pending auto-reconnect timeout and clear device identity
        reconnectionCoordinator.cancelTimeout()
        reconnectionCoordinator.clearReconnectingDevice()

        cancelResyncLoop()

        // Mark room sessions disconnected before tearing down services
        let remoteNodeService = services?.remoteNodeService
        if let remoteNodeService {
            _ = await remoteNodeService.handleBLEDisconnection()
        }

        await services?.stopEventMonitoring()

        // Reset sync state before destroying services to prevent stuck "Syncing" pill
        if let services {
            await services.syncCoordinator.onDisconnected(services: services)
        }

        logger.warning("[BLE] State → .disconnected (connection loss for device: \(deviceID.uuidString.prefix(8)))")
        connectionState = .disconnected
        connectedDevice = nil
        services = nil
        session = nil

        persistDisconnectDiagnostic(
            "source=handleConnectionLoss, " +
            "device=\(deviceID.uuidString.prefix(8)), " +
            "stateBefore=\(String(describing: stateBeforeLoss)), " +
            "error=\(errorInfo), " +
            "intent=\(connectionIntent)"
        )

        // Keep transport reference for iOS auto-reconnect to use

        // Notify UI layer of connection loss
        await onConnectionLost?()

        // iOS auto-reconnect handles normal disconnects via reconnectionCoordinator
        // Bluetooth power-cycle handled via onBluetoothPoweredOn callback
        // Watchdog provides fallback retry if both fail
        if connectionIntent.wantsConnection {
            startReconnectionWatchdog()
        }
    }

    /// Logs Bluetooth state changes for diagnostics.
    /// Disconnect logic is NOT duplicated here — BLEStateMachine already handles
    /// `.poweredOff` via `cancelCurrentOperation` which fires `onDisconnection`.
    private func handleBluetoothStateChange(_ state: CBManagerState) {
        let stateName: String
        switch state {
        case .unknown: stateName = "unknown"
        case .resetting: stateName = "resetting"
        case .unsupported: stateName = "unsupported"
        case .unauthorized: stateName = "unauthorized"
        case .poweredOff: stateName = "poweredOff"
        case .poweredOn: stateName = "poweredOn"
        @unknown default: stateName = "unknown(\(state.rawValue))"
        }
        logger.info("[BLE] Bluetooth state changed: \(stateName), connectionState: \(String(describing: self.connectionState)), connectionIntent: \(self.connectionIntent)")
    }

    // MARK: - BLEReconnectionDelegate

    func setConnectionState(_ state: ConnectionState) {
        let previousState = connectionState
        connectionState = state
        if state == .disconnected, previousState != .disconnected {
            let transportName = switch currentTransportType {
            case .bluetooth: "bluetooth"
            case .wifi: "wifi"
            case nil: "none"
            }
            persistDisconnectDiagnostic(
                "source=reconnectionCoordinator.setConnectionState, " +
                "previousState=\(String(describing: previousState)), " +
                "transport=\(transportName), " +
                "intent=\(connectionIntent)"
            )
        }
    }

    func setConnectedDevice(_ device: DeviceDTO?) {
        connectedDevice = device
    }

    func teardownSessionForReconnect() async {
        // Mark room sessions disconnected before tearing down services.
        let remoteNodeService = services?.remoteNodeService
        if let remoteNodeService {
            sessionsAwaitingReauth = await remoteNodeService.handleBLEDisconnection()
        }

        await services?.stopEventMonitoring()
        cancelResyncLoop()

        // Reset sync state before destroying services to prevent stuck "Syncing" pill
        if let services {
            await services.syncCoordinator.onDisconnected(services: services)
        }
        services = nil
        session = nil
    }

    // Background execution note: iOS provides ~10s of background execution time.
    // Session rebuild (transport + session.start) should complete within this window.
    // Full sync is deferred until performInitialSync returns to foreground via onConnectionEstablished.
    func rebuildSession(deviceID: UUID) async throws {
        logger.info("[BLE] Rebuilding session for auto-reconnect: \(deviceID.uuidString.prefix(8))")

        // Stop any existing session to prevent multiple receive loops racing for transport data
        await session?.stop()
        session = nil

        let newSession = MeshCoreSession(transport: transport)
        self.session = newSession

        do {
            try await newSession.start()
        } catch {
            logger.warning("[BLE] rebuildSession: session.start() failed: \(error.localizedDescription)")
            throw error
        }

        // Check after await — user may have disconnected
        guard connectionIntent.wantsConnection else {
            logger.info("User disconnected during session setup")
            await newSession.stop()
            connectionState = .disconnected
            return
        }

        guard let selfInfo = await newSession.currentSelfInfo else {
            logger.warning("[BLE] rebuildSession: selfInfo is nil after start()")
            throw ConnectionError.initializationFailed("No self info")
        }
        let capabilities: DeviceCapabilities
        do {
            capabilities = try await newSession.queryDevice()
        } catch {
            logger.warning("[BLE] rebuildSession: queryDevice() failed: \(error.localizedDescription)")
            throw error
        }

        // Configure BLE write pacing based on device platform
        await configureBLEPacing(for: capabilities)

        // Check after await
        guard connectionIntent.wantsConnection else {
            logger.info("User disconnected during device query")
            await newSession.stop()
            connectionState = .disconnected
            return
        }

        let newServices = ServiceContainer(
            session: newSession,
            modelContainer: modelContainer,
            appStateProvider: appStateProvider
        )
        await newServices.wireServices()

        // Check after await
        guard connectionIntent.wantsConnection else {
            logger.info("User disconnected during service wiring")
            await newSession.stop()
            connectionState = .disconnected
            return
        }

        self.services = newServices

        // Fetch existing device and auto-add config concurrently (independent operations)
        async let existingDeviceResult = newServices.dataStore.fetchDevice(id: deviceID)
        async let autoAddConfigResult = newSession.getAutoAddConfig()
        let existingDevice = try? await existingDeviceResult
        let autoAddConfig = (try? await autoAddConfigResult) ?? 0

        let device = createDevice(deviceID: deviceID, selfInfo: selfInfo, capabilities: capabilities, autoAddConfig: autoAddConfig, existingDevice: existingDevice)
        try await newServices.dataStore.saveDevice(DeviceDTO(from: device))
        self.connectedDevice = DeviceDTO(from: device)

        // Notify observers BEFORE sync starts so they can wire callbacks
        await onConnectionReady?()
        await performInitialSync(deviceID: deviceID, services: newServices, context: "[BLE] iOS auto-reconnect")

        // User may have disconnected while sync was in progress
        guard connectionIntent.wantsConnection else { return }

        await syncDeviceTimeIfNeeded()
        guard connectionIntent.wantsConnection else { return }

        // Re-authenticate room sessions that were connected before BLE loss
        let sessionIDs = sessionsAwaitingReauth
        sessionsAwaitingReauth = []
        await newServices.remoteNodeService.handleBLEReconnection(sessionIDs: sessionIDs)

        currentTransportType = .bluetooth
        connectionState = .ready
        recordConnectionSuccess()
        stopReconnectionWatchdog()
        logger.info("[BLE] iOS auto-reconnect: session ready, device: \(deviceID.uuidString.prefix(8))")
    }

    func disconnectTransport() async {
        await transport.disconnect()
    }

    func notifyConnectionLost() async {
        await onConnectionLost?()
    }

    func isTransportAutoReconnecting() async -> Bool {
        await stateMachine.isAutoReconnecting
    }

    func handleReconnectionFailure() async {
        logger.error("[BLE] Auto-reconnect session rebuild failed")
        await session?.stop()
        session = nil
        services = nil
        await transport.disconnect()
        connectionState = .disconnected
        connectedDevice = nil

        // Start watchdog to periodically retry if user still wants connection
        if connectionIntent.wantsConnection {
            startReconnectionWatchdog()
        }
    }

    /// Cleans up session and services without changing connection state (used during retries)
    private func cleanupResources() async {
        await session?.stop()
        session = nil
        services = nil
    }

    /// Full cleanup including state reset (used on explicit disconnect)
    private func cleanupConnection() async {
        logger.info("[BLE] cleanupConnection: state → .disconnected")
        connectionState = .disconnected
        connectedDevice = nil
        await cleanupResources()
    }

    private func persistDisconnectDiagnostic(_ summary: String) {
        let timestamp = Date().ISO8601Format()
        UserDefaults.standard.set("\(timestamp) \(summary)", forKey: lastDisconnectDiagnosticKey)
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
        connectionIntent: ConnectionIntent? = nil
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
    }
    #endif
}

// MARK: - AccessorySetupKitServiceDelegate

extension ConnectionManager: BLEReconnectionDelegate {}

extension ConnectionManager: AccessorySetupKitServiceDelegate {
    public func accessorySetupKitService(
        _ service: AccessorySetupKitService,
        didRemoveAccessoryWithID bluetoothID: UUID
    ) {
        // Handle device removed from Settings > Accessories
        logger.info("Device removed from ASK: \(bluetoothID)")

        Task {
            // Disconnect if this was the connected device
            if connectedDevice?.id == bluetoothID {
                await disconnect(reason: .deviceRemovedFromSettings)
            }

            // Delete from SwiftData (cascades to contacts, messages, channels, trace paths)
            let dataStore = PersistenceStore(modelContainer: modelContainer)
            do {
                try await dataStore.deleteDevice(id: bluetoothID)
            } catch {
                logger.warning("Failed to delete device data from SwiftData: \(error.localizedDescription)")
            }
        }

        // Clear persisted connection if it was this device
        if lastConnectedDeviceID == bluetoothID {
            clearPersistedConnection()
        }
    }

    public func accessorySetupKitService(
        _ service: AccessorySetupKitService,
        didFailPairingForAccessoryWithID bluetoothID: UUID
    ) {
        // Handle pairing failure (e.g., wrong PIN)
        // Clean up any existing device data so the device can appear in picker again
        logger.info("Pairing failed for device: \(bluetoothID)")

        Task {
            // Disconnect if this was somehow the connected device
            if connectedDevice?.id == bluetoothID {
                await disconnect(reason: .pairingFailed)
            }

            // Delete from SwiftData (may not exist if this was a fresh pairing attempt)
            let dataStore = PersistenceStore(modelContainer: modelContainer)
            do {
                try await dataStore.deleteDevice(id: bluetoothID)
                logger.info("Deleted device data after failed pairing")
            } catch {
                // Expected if device wasn't previously saved
                logger.info("No device data to delete: \(error.localizedDescription)")
            }
        }

        // Clear persisted connection if it was this device
        if lastConnectedDeviceID == bluetoothID {
            clearPersistedConnection()
        }
    }
}
