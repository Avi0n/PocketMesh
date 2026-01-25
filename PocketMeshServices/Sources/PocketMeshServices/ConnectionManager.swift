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
    public private(set) var connectionState: ConnectionState = .disconnected

    /// Connected device info (nil when disconnected)
    public private(set) var connectedDevice: DeviceDTO?

    /// Services container (nil when disconnected)
    public private(set) var services: ServiceContainer?

    /// Current transport type (bluetooth or wifi)
    public private(set) var currentTransportType: TransportType?

    /// Whether user wants to be connected. Only changed by explicit user actions.
    private var shouldBeConnected = false

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
    private let stateMachine = BLEStateMachine()

    /// Timer to transition UI from "connecting" to "disconnected" after timeout.
    /// iOS auto-reconnect continues in background even after this fires.
    private var autoReconnectTimeoutTask: Task<Void, Never>?

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

    /// Temporary flag for forcing full sync on next connection
    private var pendingForceFullSync: Bool = false

    // MARK: - Persistence Keys

    private let lastDeviceIDKey = "com.pocketmesh.lastConnectedDeviceID"
    private let lastDeviceNameKey = "com.pocketmesh.lastConnectedDeviceName"
    private let userDisconnectedKey = "com.pocketmesh.userExplicitlyDisconnected"

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

    /// The last connected device ID (for auto-reconnect)
    public var lastConnectedDeviceID: UUID? {
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

    /// Whether the user explicitly disconnected (should skip auto-reconnect)
    private var userExplicitlyDisconnected: Bool {
        UserDefaults.standard.bool(forKey: userDisconnectedKey)
    }

    /// Records that user explicitly disconnected
    private func setUserDisconnected() {
        UserDefaults.standard.set(true, forKey: userDisconnectedKey)
    }

    /// Clears user disconnect flag (when user initiates connection)
    private func clearUserDisconnected() {
        UserDefaults.standard.removeObject(forKey: userDisconnectedKey)
    }

    /// Whether the disconnected pill should be suppressed (user explicitly disconnected)
    public var shouldSuppressDisconnectedPill: Bool {
        userExplicitlyDisconnected
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

    /// Cancels the auto-reconnect UI timeout timer
    private func cancelAutoReconnectTimeout() {
        autoReconnectTimeoutTask?.cancel()
        autoReconnectTimeoutTask = nil
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

    /// Handles unexpected WiFi connection loss
    private func handleWiFiDisconnection(error: Error?) async {
        // User-initiated disconnect - don't reconnect
        guard shouldBeConnected else { return }

        // Only handle WiFi disconnections
        guard currentTransportType == .wifi else { return }

        logger.warning("WiFi connection lost: \(error?.localizedDescription ?? "unknown")")

        // Stop heartbeat before teardown
        stopWiFiHeartbeat()

        cancelResyncLoop()

        // Tear down session (invalid now)
        await services?.stopEventMonitoring()
        services = nil
        session = nil

        // Show connecting state (pulsing indicator)
        connectionState = .connecting

        // Start reconnection attempts
        startWiFiReconnection()
    }

    /// Starts the WiFi reconnection retry loop
    private func startWiFiReconnection() {
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

            while !Task.isCancelled && shouldBeConnected {
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

        // Time sync (best effort)
        if let deviceTime = try? await newSession.getTime(),
           abs(deviceTime.timeIntervalSinceNow) > 60 {
            try? await newSession.setTime(Date())
            logger.info("Synced device time after reconnection")
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

        let existingDevice = try? await newServices.dataStore.fetchDevice(id: deviceID)
        let device = createDevice(
            deviceID: deviceID,
            selfInfo: selfInfo,
            capabilities: capabilities,
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

        currentTransportType = .wifi
        connectionState = .ready
        startWiFiHeartbeat()
    }

    /// Checks if the WiFi connection is still alive (call on app foreground)
    public func checkWiFiConnectionHealth() async {
        guard currentTransportType == .wifi,
              connectionState == .ready,
              let wifiTransport else { return }

        let isConnected = await wifiTransport.isConnected
        if !isConnected {
            logger.info("WiFi connection died while backgrounded")
            await handleWiFiDisconnection(error: nil)
        }
    }

    /// Attempts BLE reconnection if user expects to be connected but iOS auto-reconnect gave up.
    /// Call this when the app returns to foreground.
    public func checkBLEConnectionHealth() async {
        // Only check BLE connections
        guard currentTransportType == nil || currentTransportType == .bluetooth else { return }

        // Check if user expects to be connected but we're disconnected
        guard shouldBeConnected,
              connectionState == .disconnected,
              let deviceID = lastConnectedDeviceID else { return }

        // Don't interfere if iOS auto-reconnect is still in progress
        if await stateMachine.isAutoReconnecting {
            logger.info("[BLE] Skipping foreground reconnect: iOS auto-reconnect still in progress")
            return
        }

        // Don't reconnect if device is connected to another app
        if await isDeviceConnectedToOtherApp(deviceID) {
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
            try await services.syncCoordinator.onConnectionEstablished(
                deviceID: deviceID,
                services: services,
                forceFullSync: forceFullSync
            )
        } catch {
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

                guard shouldBeConnected,
                      connectionState == .ready else { break }

                resyncAttemptCount += 1
                logger.info("Resync attempt \(resyncAttemptCount)/\(Self.maxResyncAttempts)")

                let success = await services.syncCoordinator.performResync(
                    deviceID: deviceID,
                    services: services,
                    forceFullSync: forceFullSync
                )

                if success {
                    logger.info("Resync succeeded")
                    resyncAttemptCount = 0
                    break
                }

                if resyncAttemptCount >= Self.maxResyncAttempts {
                    logger.warning("Resync failed \(Self.maxResyncAttempts) times, disconnecting")
                    onResyncFailed?()
                    await disconnect()
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
              shouldBeConnected,
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
    /// - Parameter modelContainer: The SwiftData model container for persistence
    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.transport = iOSBLETransport(stateMachine: stateMachine)
        accessorySetupKit.delegate = self

        // Wire up transport handlers
        Task {
            // Handle disconnection events
            await transport.setDisconnectionHandler { [weak self] deviceID, error in
                Task { @MainActor in
                    guard let self else { return }
                    await self.handleConnectionLoss(deviceID: deviceID, error: error)
                }
            }

            // Handle entering auto-reconnecting phase
            await stateMachine.setAutoReconnectingHandler { [weak self] deviceID in
                Task { @MainActor in
                    guard let self else { return }
                    await self.handleEnteringAutoReconnect(deviceID: deviceID)
                }
            }

            // Handle iOS auto-reconnect completion
            // Using transport.setReconnectionHandler ensures the transport captures
            // the data stream internally before calling our handler
            await transport.setReconnectionHandler { [weak self] deviceID in
                Task { @MainActor in
                    guard let self else { return }
                    await self.handleIOSAutoReconnect(deviceID: deviceID)
                }
            }

            // Handle Bluetooth power-cycle recovery
            await stateMachine.setBluetoothPoweredOnHandler { [weak self] in
                Task { @MainActor in
                    guard let self,
                          self.shouldBeConnected,
                          self.connectionState == .disconnected,
                          let deviceID = self.lastConnectedDeviceID else { return }

                    self.logger.info("[BLE] Bluetooth powered on: attempting reconnection to \(deviceID.uuidString.prefix(8))")
                    try? await self.connect(to: deviceID)
                }
            }
        }
    }

    // MARK: - Public Lifecycle Methods

    /// Activates the connection manager on app launch.
    /// Call this once during app initialization.
    public func activate() async {
        logger.info("Activating ConnectionManager")

        #if targetEnvironment(simulator)
        // Skip auto-reconnect if user explicitly disconnected
        if userExplicitlyDisconnected {
            logger.info("Simulator: skipping auto-reconnect - user previously disconnected")
            return
        }
        // On simulator, skip ASK entirely and auto-reconnect to simulator device
        if let lastDeviceID = lastConnectedDeviceID,
           lastDeviceID == MockDataProvider.simulatorDeviceID {
            logger.info("Simulator: auto-reconnecting to mock device")
            shouldBeConnected = true
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
        // Activate AccessorySetupKit session first (required before any BLE operations)
        do {
            try await accessorySetupKit.activateSession()
        } catch {
            logger.error("Failed to activate AccessorySetupKit: \(error.localizedDescription)")
            // Don't return - WiFi doesn't need ASK
        }

        // Skip auto-reconnect if user explicitly disconnected
        if userExplicitlyDisconnected {
            logger.info("Skipping auto-reconnect: user previously disconnected")
            return
        }

        // Auto-reconnect to last device if available
        if let lastDeviceID = lastConnectedDeviceID {
            logger.info("Attempting auto-reconnect to last device: \(lastDeviceID)")

            // Set intent before checking state
            shouldBeConnected = true

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
                shouldBeConnected = false
                return
            }

            do {
                try await connect(to: lastDeviceID)
            } catch {
                logger.warning("Auto-reconnect failed: \(error.localizedDescription)")
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
        shouldBeConnected = true
        clearUserDisconnected()

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
    /// - Throws: Connection errors
    public func connect(to deviceID: UUID, forceFullSync: Bool = false) async throws {
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

        // Cancel pending state restoration auto-reconnect if connecting to different device
        if await stateMachine.isAutoReconnecting {
            let restoringDeviceID = await stateMachine.connectedDeviceID
            let blePhase = await stateMachine.currentPhaseName
            let blePeripheralState = await stateMachine.currentPeripheralState ?? "none"

            if restoringDeviceID != deviceID {
                logger.info("Cancelling state restoration auto-reconnect to \(restoringDeviceID?.uuidString ?? "unknown") to connect to \(deviceID)")
                await transport.disconnect()
            } else {
                // Diagnostic: Log when trying to connect to same device that's in autoReconnecting
                logger.warning(
                    "Attempting connect to device already in autoReconnecting - deviceID: \(deviceID), blePhase: \(blePhase), blePeripheralState: \(blePeripheralState)"
                )
            }
        }

        // Check for other app connection before changing state
        if await isDeviceConnectedToOtherApp(deviceID) {
            throw BLEError.deviceConnectedToOtherApp
        }

        // Set connecting state for immediate UI feedback
        connectionState = .connecting

        logger.info("Connecting to device: \(deviceID)")

        // Cancel any pending auto-reconnect timeout
        cancelAutoReconnectTimeout()

        // Clear intentional disconnect flag - user is explicitly connecting
        shouldBeConnected = true
        clearUserDisconnected()
        pendingForceFullSync = forceFullSync

        do {
            // Validate device is still registered with ASK
            if accessorySetupKit.isSessionActive {
                let isRegistered = accessorySetupKit.pairedAccessories.contains {
                    $0.bluetoothIdentifier == deviceID
                }

                if !isRegistered {
                    logger.warning("Device not found in ASK paired accessories")
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
    public func disconnect() async {
        logger.info("Disconnecting from device (user-initiated)")

        // Cancel any pending auto-reconnect timeout
        cancelAutoReconnectTimeout()

        // Cancel any WiFi reconnection in progress
        cancelWiFiReconnection()

        // Stop WiFi heartbeat
        stopWiFiHeartbeat()

        cancelResyncLoop()

        // Mark as intentional disconnect to suppress auto-reconnect
        shouldBeConnected = false
        setUserDisconnected()

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

        logger.info("Disconnected")
    }

    /// Connects to the simulator device with mock data.
    /// Used for simulator builds and demo mode on device.
    public func simulatorConnect() async throws {
        logger.info("Starting simulator connection")

        connectionState = .connecting
        shouldBeConnected = true
        clearUserDisconnected()

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
            await disconnect()
        }

        connectionState = .connecting
        shouldBeConnected = true
        clearUserDisconnected()

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

            // Start session (this calls sendAppStart internally)
            try await newSession.start()

            // Get device info from session
            guard let meshCoreSelfInfo = await newSession.currentSelfInfo else {
                throw ConnectionError.initializationFailed("Failed to get device self info")
            }
            let deviceCapabilities = try await newSession.queryDevice()

            // Derive device ID from public key (WiFi devices don't have Bluetooth UUIDs)
            let deviceID = DeviceIdentity.deriveUUID(from: meshCoreSelfInfo.publicKey)

            // Sync device time (best effort)
            do {
                let deviceTime = try await newSession.getTime()
                let timeDifference = abs(deviceTime.timeIntervalSinceNow)
                if timeDifference > 60 {
                    try await newSession.setTime(Date())
                    logger.info("Synced device time (was off by \(Int(timeDifference))s)")
                }
            } catch {
                logger.warning("Failed to sync device time: \(error.localizedDescription)")
            }

            // Create services
            let newServices = ServiceContainer(
                session: newSession,
                modelContainer: modelContainer,
                appStateProvider: appStateProvider
            )
            await newServices.wireServices()
            self.services = newServices

            // Fetch existing device to preserve local settings
            let existingDevice = try? await newServices.dataStore.fetchDevice(id: deviceID)

            // Create WiFi connection method
            let wifiMethod = ConnectionMethod.wifi(host: host, port: port, displayName: nil)

            // Create and save device
            let device = createDevice(
                deviceID: deviceID,
                selfInfo: meshCoreSelfInfo,
                capabilities: deviceCapabilities,
                existingDevice: existingDevice,
                connectionMethods: [wifiMethod]
            )

            try await newServices.dataStore.saveDevice(DeviceDTO(from: device))
            self.connectedDevice = DeviceDTO(from: device)

            // Persist connection for potential future use
            persistConnection(deviceID: deviceID, deviceName: meshCoreSelfInfo.name)

            await onConnectionReady?()
            await performInitialSync(deviceID: deviceID, services: newServices, forceFullSync: forceFullSync)

            // Wire disconnection handler for auto-reconnect
            await newWiFiTransport.setDisconnectionHandler { [weak self] error in
                Task { @MainActor in
                    await self?.handleWiFiDisconnection(error: error)
                }
            }

            currentTransportType = .wifi
            connectionState = .ready

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
        shouldBeConnected = true
        clearUserDisconnected()

        // Validate device is registered with ASK
        if accessorySetupKit.isSessionActive {
            let isRegistered = accessorySetupKit.pairedAccessories.contains {
                $0.bluetoothIdentifier == deviceID
            }
            if !isRegistered {
                throw ConnectionError.deviceNotFound
            }
        }

        // Stop current services
        await services?.stopEventMonitoring()
        await session?.stop()

        // Switch transport
        try await transport.switchDevice(to: deviceID)
        connectionState = .connected

        // Re-create session with existing transport
        let newSession = MeshCoreSession(transport: transport)
        self.session = newSession
        try await newSession.start()

        // Get device info
        guard let meshCoreSelfInfo = await newSession.currentSelfInfo else {
            throw ConnectionError.initializationFailed("Failed to get device self info")
        }
        let deviceCapabilities = try await newSession.queryDevice()

        // Create and wire services
        let newServices = ServiceContainer(
            session: newSession,
            modelContainer: modelContainer,
            appStateProvider: appStateProvider
        )
        await newServices.wireServices()
        self.services = newServices

        // Fetch existing device to preserve local settings (e.g., OCV preset)
        let existingDevice = try? await newServices.dataStore.fetchDevice(id: deviceID)

        // Create and save device
        let device = createDevice(
            deviceID: deviceID,
            selfInfo: meshCoreSelfInfo,
            capabilities: deviceCapabilities,
            existingDevice: existingDevice
        )

        try await newServices.dataStore.saveDevice(DeviceDTO(from: device))
        self.connectedDevice = DeviceDTO(from: device)

        // Persist connection for auto-reconnect
        persistConnection(deviceID: deviceID, deviceName: meshCoreSelfInfo.name)

        // Notify observers BEFORE sync starts so they can wire callbacks
        await onConnectionReady?()
        await performInitialSync(deviceID: deviceID, services: newServices, context: "Device switch", forceFullSync: true)

        currentTransportType = .bluetooth
        connectionState = .ready
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
        await disconnect()

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

                if attempt > 1 {
                    logger.info("Reconnection succeeded on attempt \(attempt)")
                }
                return

            } catch {
                lastError = error

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

        // All retries exhausted - caller's catch block sets .disconnected
        // Diagnostic: Log final failure state
        let finalBlePhase = await stateMachine.currentPhaseName
        let finalBlePeripheralState = await stateMachine.currentPeripheralState ?? "none"
        logger.error(
            "[BLE] All \(maxAttempts) reconnection attempts exhausted - lastError: \(lastError.localizedDescription), blePhase: \(finalBlePhase), blePeripheralState: \(finalBlePeripheralState)"
        )

        throw lastError
    }

    // MARK: - Private Connection Methods

    /// Connects to a device immediately after ASK pairing with retry logic
    private func connectAfterPairing(deviceID: UUID, maxAttempts: Int = 4) async throws {
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

        connectionState = .connected

        // Create session
        let newSession = MeshCoreSession(transport: transport)
        self.session = newSession

        // Start session (this calls sendAppStart internally)
        try await newSession.start()

        // Get device info - selfInfo is now available from session
        guard let meshCoreSelfInfo = await newSession.currentSelfInfo else {
            throw ConnectionError.initializationFailed("Failed to get device self info")
        }
        let deviceCapabilities = try await newSession.queryDevice()

        // Sync device time (best effort)
        do {
            let deviceTime = try await newSession.getTime()
            let timeDifference = abs(deviceTime.timeIntervalSinceNow)
            if timeDifference > 60 {
                try await newSession.setTime(Date())
                logger.info("Synced device time (was off by \(Int(timeDifference))s)")
            }
        } catch {
            logger.warning("Failed to sync device time: \(error.localizedDescription)")
        }

        // Create services
        let newServices = ServiceContainer(
            session: newSession,
            modelContainer: modelContainer,
            appStateProvider: appStateProvider
        )
        await newServices.wireServices()
        self.services = newServices

        // Fetch existing device to preserve local settings (e.g., OCV preset)
        let existingDevice = try? await newServices.dataStore.fetchDevice(id: deviceID)

        // Create and save device
        let device = createDevice(
            deviceID: deviceID,
            selfInfo: meshCoreSelfInfo,
            capabilities: deviceCapabilities,
            existingDevice: existingDevice
        )

        try await newServices.dataStore.saveDevice(DeviceDTO(from: device))
        self.connectedDevice = DeviceDTO(from: device)

        // Persist connection for auto-reconnect
        persistConnection(deviceID: deviceID, deviceName: meshCoreSelfInfo.name)

        // Notify observers BEFORE sync starts so they can wire callbacks
        // (e.g., AppState needs to set sync activity callbacks for the syncing pill)
        await onConnectionReady?()
        let shouldForceFullSync = pendingForceFullSync
        pendingForceFullSync = false
        await performInitialSync(deviceID: deviceID, services: newServices, forceFullSync: shouldForceFullSync)

        currentTransportType = .bluetooth
        connectionState = .ready
        logger.info("Connection complete - device ready")
    }

    /// Creates a Device from MeshCore types
    private func createDevice(
        deviceID: UUID,
        selfInfo: MeshCore.SelfInfo,
        capabilities: MeshCore.DeviceCapabilities,
        existingDevice: DeviceDTO? = nil,
        connectionMethods: [ConnectionMethod] = []
    ) -> Device {
        // Merge new connection methods with existing ones, avoiding duplicates
        var mergedMethods = existingDevice?.connectionMethods ?? []
        for method in connectionMethods where !mergedMethods.contains(method) {
            mergedMethods.append(method)
        }

        return Device(
            id: deviceID,
            publicKey: selfInfo.publicKey,
            nodeName: selfInfo.name,
            firmwareVersion: capabilities.firmwareVersion,
            firmwareVersionString: capabilities.version,
            manufacturerName: capabilities.model,
            buildDate: capabilities.firmwareBuild,
            maxContacts: UInt8(min(capabilities.maxContacts, 255)),
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
            manualAddContacts: selfInfo.manualAddContacts,
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
    }

    // MARK: - Connection Loss Handling

    /// Handles unexpected connection loss
    private func handleConnectionLoss(deviceID: UUID, error: Error?) async {
        var errorInfo = "none"
        if let error = error as NSError? {
            errorInfo = "domain=\(error.domain), code=\(error.code), desc=\(error.localizedDescription)"
        }
        logger.warning("[BLE] Connection lost: \(deviceID.uuidString.prefix(8)), currentState: \(String(describing: connectionState)), error: \(errorInfo)")

        // Cancel any pending auto-reconnect timeout
        cancelAutoReconnectTimeout()

        cancelResyncLoop()

        await services?.stopEventMonitoring()
        connectionState = .disconnected
        connectedDevice = nil
        services = nil
        session = nil
        // Keep transport reference for iOS auto-reconnect to use

        // Notify UI layer of connection loss
        await onConnectionLost?()

        // iOS auto-reconnect handles normal disconnects via handleIOSAutoReconnect()
        // Bluetooth power-cycle handled via onBluetoothPoweredOn callback
    }

    /// Handles entering iOS auto-reconnect phase.
    /// Tears down services but keeps state as "connecting" to show pulsing icon.
    private func handleEnteringAutoReconnect(deviceID: UUID) async {
        logger.info("[BLE] Entering auto-reconnect phase: \(deviceID.uuidString.prefix(8)), currentState: \(String(describing: connectionState)), startingUITimeout: 10s")

        // User may have disconnected just before this
        guard shouldBeConnected else {
            logger.info("Ignoring auto-reconnect: user disconnected")
            await transport.disconnect()
            return
        }

        // Tear down session layer (it's invalid now)
        await services?.stopEventMonitoring()

        cancelResyncLoop()

        // Reset sync state before destroying services to prevent stuck "Syncing" pill
        if let services {
            await services.syncCoordinator.onDisconnected(services: services)
        }
        services = nil
        session = nil

        // Show "connecting" state with pulsing blue icon
        // Keep connectedDevice set so we can show device name during reconnection
        connectionState = .connecting

        // Start timeout to transition UI to disconnected after 10s
        // iOS auto-reconnect continues in background even after this fires
        cancelAutoReconnectTimeout()
        autoReconnectTimeoutTask = Task {
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            if connectionState == .connecting {
                // Diagnostic: Log BLE state when UI timeout fires
                let blePhase = await stateMachine.currentPhaseName
                let blePeripheralState = await stateMachine.currentPeripheralState ?? "none"
                logger.warning(
                    "[BLE] Auto-reconnect UI timeout (10s) fired - blePhase: \(blePhase), blePeripheralState: \(blePeripheralState), transitioning UI to disconnected (iOS reconnect continues in background)"
                )
                connectionState = .disconnected
                connectedDevice = nil
                await onConnectionLost?()
            }
        }
    }

    /// Handles iOS system auto-reconnect completion.
    ///
    /// When iOS auto-reconnects the BLE peripheral (via CBConnectPeripheralOptionEnableAutoReconnect),
    /// this method re-establishes the session layer without creating a new transport.
    private func handleIOSAutoReconnect(deviceID: UUID) async {
        logger.info("[BLE] iOS auto-reconnect complete: \(deviceID.uuidString.prefix(8)), currentState: \(String(describing: connectionState)), rebuilding session...")

        // Cancel UI timeout since reconnection succeeded
        cancelAutoReconnectTimeout()

        // User disconnected while iOS was reconnecting
        guard shouldBeConnected else {
            logger.info("Ignoring: user disconnected")
            await transport.disconnect()
            return
        }

        // Accept both disconnected (normal) and connecting (auto-reconnect in progress)
        guard self.connectionState == .disconnected || self.connectionState == .connecting else {
            logger.info("Ignoring: already \(String(describing: self.connectionState))")
            return
        }

        connectionState = .connecting

        do {
            // Stop any existing session to prevent multiple receive loops racing for transport data
            await session?.stop()
            session = nil

            let newSession = MeshCoreSession(transport: transport)
            self.session = newSession

            try await newSession.start()

            // Check after await — user may have disconnected
            guard shouldBeConnected else {
                logger.info("User disconnected during session setup")
                await newSession.stop()
                connectionState = .disconnected
                return
            }

            guard let selfInfo = await newSession.currentSelfInfo else {
                throw ConnectionError.initializationFailed("No self info")
            }
            let capabilities = try await newSession.queryDevice()

            // Time sync (best effort)
            if let deviceTime = try? await newSession.getTime() {
                if abs(deviceTime.timeIntervalSinceNow) > 60 {
                    try? await newSession.setTime(Date())
                    logger.info("Synced device time")
                }
            }

            // Check after await
            guard shouldBeConnected else {
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
            guard shouldBeConnected else {
                logger.info("User disconnected during service wiring")
                await newSession.stop()
                connectionState = .disconnected
                return
            }

            self.services = newServices

            // Fetch existing device to preserve local settings (e.g., OCV preset)
            let existingDevice = try? await newServices.dataStore.fetchDevice(id: deviceID)

            let device = createDevice(deviceID: deviceID, selfInfo: selfInfo, capabilities: capabilities, existingDevice: existingDevice)
            try await newServices.dataStore.saveDevice(DeviceDTO(from: device))
            self.connectedDevice = DeviceDTO(from: device)

            // Notify observers BEFORE sync starts so they can wire callbacks
            await onConnectionReady?()
            await performInitialSync(deviceID: deviceID, services: newServices, context: "[BLE] iOS auto-reconnect")

            currentTransportType = .bluetooth
            connectionState = .ready
            logger.info("[BLE] iOS auto-reconnect: session ready, device: \(deviceID.uuidString.prefix(8))")


        } catch {
            logger.error("[BLE] iOS auto-reconnect session setup failed: \(error.localizedDescription)")
            await session?.stop()
            session = nil
            await transport.disconnect()
            connectionState = .disconnected
            connectedDevice = nil
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
        connectionState = .disconnected
        connectedDevice = nil
        await cleanupResources()
    }
}

// MARK: - AccessorySetupKitServiceDelegate

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
                await disconnect()
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
                await disconnect()
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
