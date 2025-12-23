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

    private let logger = Logger(subsystem: "com.pocketmesh.services", category: "ConnectionManager")

    // MARK: - Observable State

    /// Current connection state
    public private(set) var connectionState: ConnectionState = .disconnected

    /// Connected device info (nil when disconnected)
    public private(set) var connectedDevice: DeviceDTO?

    /// Services container (nil when disconnected)
    public private(set) var services: ServiceContainer?

    /// Whether user wants to be connected. Only changed by explicit user actions.
    private var shouldBeConnected = false

    /// Number of paired accessories (for troubleshooting UI)
    public var pairedAccessoriesCount: Int {
        accessorySetupKit.pairedAccessories.count
    }

    // MARK: - Internal Components

    private let modelContainer: ModelContainer
    private var transport: iOSBLETransport?
    private var session: MeshCoreSession?
    private let accessorySetupKit = AccessorySetupKitService()

    /// Shared BLE state machine to manage connection lifecycle.
    /// This prevents state restoration race conditions that cause "API MISUSE" errors.
    private let stateMachine = BLEStateMachine()

    // MARK: - Persistence Keys

    private let lastDeviceIDKey = "com.pocketmesh.lastConnectedDeviceID"
    private let lastDeviceNameKey = "com.pocketmesh.lastConnectedDeviceName"

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

    // MARK: - Initialization

    /// Creates a new connection manager.
    /// - Parameter modelContainer: The SwiftData model container for persistence
    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        accessorySetupKit.delegate = self

        // Handle Bluetooth power-cycle recovery
        Task {
            await stateMachine.setBluetoothPoweredOnHandler { [weak self] in
                Task { @MainActor in
                    guard let self,
                          self.shouldBeConnected,
                          self.connectionState == .disconnected,
                          let deviceID = self.lastConnectedDeviceID else { return }

                    self.logger.info("Bluetooth powered on: reconnecting to \(deviceID)")
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

        // Activate AccessorySetupKit session first (required before any BLE operations)
        do {
            try await accessorySetupKit.activateSession()
        } catch {
            logger.error("Failed to activate AccessorySetupKit: \(error.localizedDescription)")
            return
        }

        // Auto-reconnect to last device if available
        if let lastDeviceID = lastConnectedDeviceID {
            logger.info("Attempting auto-reconnect to last device: \(lastDeviceID)")
            do {
                try await connect(to: lastDeviceID)
            } catch {
                logger.warning("Auto-reconnect failed: \(error.localizedDescription)")
                // Don't propagate - auto-reconnect failure is not fatal
            }
        }
    }

    /// Pairs a new device using AccessorySetupKit picker.
    /// - Throws: AccessorySetupKitError if pairing fails
    public func pairNewDevice() async throws {
        logger.info("Starting device pairing")

        // Clear intentional disconnect flag - user is explicitly pairing
        shouldBeConnected = true

        // Show AccessorySetupKit picker
        let deviceID = try await accessorySetupKit.showPicker()

        // Connect to the newly paired device
        try await connectAfterPairing(deviceID: deviceID)
    }

    /// Connects to a previously paired device.
    /// - Parameter deviceID: The UUID of the device to connect to
    /// - Throws: Connection errors
    public func connect(to deviceID: UUID) async throws {
        // Prevent concurrent connection attempts
        guard connectionState == .disconnected else {
            logger.debug("Connection already in progress or established, skipping")
            return
        }

        logger.info("Connecting to device: \(deviceID)")

        // Clear intentional disconnect flag - user is explicitly connecting
        shouldBeConnected = true

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
    }

    /// Disconnects from the current device.
    public func disconnect() async {
        logger.info("Disconnecting from device (user-initiated)")

        // Mark as intentional disconnect to suppress auto-reconnect
        shouldBeConnected = false

        // Stop event monitoring
        await services?.stopEventMonitoring()

        // Stop session
        await session?.stop()

        // Disconnect transport
        await transport?.disconnect()

        // Clear state
        await cleanupConnection()

        // Clear persisted connection
        clearPersistedConnection()

        logger.info("Disconnected")
    }

    /// Switches to a different device.
    ///
    /// - Parameter deviceID: UUID of the new device to connect to
    public func switchDevice(to deviceID: UUID) async throws {
        logger.info("Switching to device: \(deviceID)")

        // Update intent
        shouldBeConnected = true

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
        guard let transport = transport as? iOSBLETransport else {
            // Fallback to disconnect + connect for old transport
            await disconnect()
            try await connect(to: deviceID)
            return
        }

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
        let newServices = ServiceContainer(session: newSession, modelContainer: modelContainer)
        await newServices.wireServices()
        self.services = newServices

        // Create and save device
        let device = createDevice(
            deviceID: deviceID,
            selfInfo: meshCoreSelfInfo,
            capabilities: deviceCapabilities
        )

        try await newServices.dataStore.saveDevice(DeviceDTO(from: device))
        self.connectedDevice = DeviceDTO(from: device)

        // Persist connection for auto-reconnect
        persistConnection(deviceID: deviceID, deviceName: meshCoreSelfInfo.name)

        // Start event monitoring
        await newServices.startEventMonitoring(deviceID: deviceID)

        connectionState = .ready
        logger.info("Device switch complete - device ready")
    }

    /// Forgets the device, removing it from paired accessories.
    /// - Throws: `ConnectionError.deviceNotFound` if no device is connected
    public func forgetDevice() async throws {
        guard let deviceID = connectedDevice?.id else {
            throw ConnectionError.notConnected
        }

        guard let accessory = accessorySetupKit.accessory(for: deviceID) else {
            throw ConnectionError.deviceNotFound
        }

        logger.info("Forgetting device: \(deviceID)")

        // Remove from paired accessories
        try await accessorySetupKit.removeAccessory(accessory)

        // Disconnect
        await disconnect()

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

    /// Checks if an accessory is registered with AccessorySetupKit.
    /// - Parameter deviceID: The Bluetooth UUID of the device
    /// - Returns: `true` if the accessory is available for connection
    public func hasAccessory(for deviceID: UUID) -> Bool {
        accessorySetupKit.accessory(for: deviceID) != nil
    }

    /// Fetches all previously paired devices from storage.
    /// Available even when disconnected, for device selection UI.
    public func fetchSavedDevices() async throws -> [DeviceDTO] {
        logger.debug("fetchSavedDevices called, connectionState: \(String(describing: self.connectionState))")
        let dataStore = PersistenceStore(modelContainer: modelContainer)
        let devices = try await dataStore.fetchDevices()
        logger.debug("fetchSavedDevices returning \(devices.count) devices")
        return devices
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
                logger.warning("Reconnection attempt \(attempt) failed: \(error.localizedDescription)")

                await cleanupConnection()

                if attempt < maxAttempts {
                    let baseDelay = 0.3 * pow(2.0, Double(attempt - 1))
                    let jitter = Double.random(in: 0...0.1) * baseDelay
                    try await Task.sleep(for: .seconds(baseDelay + jitter))
                }
            }
        }

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

                // Clean up failed connection
                await cleanupConnection()

                if attempt < maxAttempts {
                    // Exponential backoff with jitter
                    let baseDelay = 0.3 * pow(2.0, Double(attempt - 1))
                    let jitter = Double.random(in: 0...0.1) * baseDelay
                    try await Task.sleep(for: .seconds(baseDelay + jitter))
                }
            }
        }

        throw lastError
    }

    /// Performs the actual connection to a device
    private func performConnection(deviceID: UUID) async throws {
        connectionState = .connecting

        // Create transport with state machine
        let newTransport = iOSBLETransport(stateMachine: stateMachine)
        self.transport = newTransport

        // Set device ID and connect
        await newTransport.setDeviceID(deviceID)
        try await newTransport.connect()

        connectionState = .connected

        // Create session
        let newSession = MeshCoreSession(transport: newTransport)
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
        let newServices = ServiceContainer(session: newSession, modelContainer: modelContainer)
        await newServices.wireServices()
        self.services = newServices

        // Create and save device
        let device = createDevice(
            deviceID: deviceID,
            selfInfo: meshCoreSelfInfo,
            capabilities: deviceCapabilities
        )

        try await newServices.dataStore.saveDevice(DeviceDTO(from: device))
        self.connectedDevice = DeviceDTO(from: device)

        // Persist connection for auto-reconnect
        persistConnection(deviceID: deviceID, deviceName: meshCoreSelfInfo.name)

        // Start event monitoring
        await newServices.startEventMonitoring(deviceID: deviceID)

        connectionState = .ready
        logger.info("Connection complete - device ready")
    }

    /// Creates a Device from MeshCore types
    private func createDevice(
        deviceID: UUID,
        selfInfo: MeshCore.SelfInfo,
        capabilities: MeshCore.DeviceCapabilities
    ) -> Device {
        Device(
            id: deviceID,
            publicKey: selfInfo.publicKey,
            nodeName: selfInfo.name,
            firmwareVersion: capabilities.firmwareVersion,
            firmwareVersionString: capabilities.version,
            manufacturerName: capabilities.model,
            buildDate: capabilities.firmwareBuild,
            maxContacts: UInt8(min(capabilities.maxContacts, 255)),
            maxChannels: UInt8(min(capabilities.maxChannels, 255)),
            frequency: UInt32(selfInfo.radioFrequency),
            bandwidth: UInt32(selfInfo.radioBandwidth),
            spreadingFactor: selfInfo.radioSpreadingFactor,
            codingRate: selfInfo.radioCodingRate,
            txPower: selfInfo.txPower,
            maxTxPower: selfInfo.maxTxPower,
            latitude: selfInfo.latitude,
            longitude: selfInfo.longitude,
            blePin: capabilities.blePin,
            manualAddContacts: selfInfo.manualAddContacts,
            multiAcks: selfInfo.multiAcks > 0,
            telemetryModeBase: selfInfo.telemetryModeBase,
            telemetryModeLoc: selfInfo.telemetryModeLocation,
            telemetryModeEnv: selfInfo.telemetryModeEnvironment,
            advertLocationPolicy: selfInfo.advertisementLocationPolicy,
            lastConnected: Date(),
            lastContactSync: 0,
            isActive: true
        )
    }

    // MARK: - Connection Loss Handling

    /// Handles unexpected connection loss
    private func handleConnectionLoss(deviceID: UUID, error: Error?) async {
        logger.warning("Connection lost to device \(deviceID): \(error?.localizedDescription ?? "unknown")")

        await services?.stopEventMonitoring()
        connectionState = .disconnected
        connectedDevice = nil
        services = nil
        session = nil
        // Keep transport reference for iOS auto-reconnect to use

        // iOS auto-reconnect handles normal disconnects via handleIOSAutoReconnect()
        // Bluetooth power-cycle handled via onBluetoothPoweredOn callback
    }

    /// Handles iOS system auto-reconnect completion.
    ///
    /// When iOS auto-reconnects the BLE peripheral (via CBConnectPeripheralOptionEnableAutoReconnect),
    /// this method re-establishes the session layer without creating a new transport.
    private func handleIOSAutoReconnect(deviceID: UUID) async {
        logger.info("iOS auto-reconnect complete for \(deviceID)")

        // User disconnected while iOS was reconnecting
        guard shouldBeConnected else {
            logger.info("Ignoring: user disconnected")
            await transport?.disconnect()
            return
        }

        // Already handling a connection
        guard self.connectionState == .disconnected else {
            logger.debug("Ignoring: already \(String(describing: self.connectionState))")
            return
        }

        connectionState = .connecting

        guard let existingTransport = transport else {
            logger.warning("No transport for session setup")
            connectionState = .disconnected
            return
        }

        do {
            let newSession = MeshCoreSession(transport: existingTransport)
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

            let newServices = ServiceContainer(session: newSession, modelContainer: modelContainer)
            await newServices.wireServices()

            // Check after await
            guard shouldBeConnected else {
                logger.info("User disconnected during service wiring")
                await newSession.stop()
                connectionState = .disconnected
                return
            }

            self.services = newServices

            let device = createDevice(deviceID: deviceID, selfInfo: selfInfo, capabilities: capabilities)
            try await newServices.dataStore.saveDevice(DeviceDTO(from: device))
            self.connectedDevice = DeviceDTO(from: device)

            await newServices.startEventMonitoring(deviceID: deviceID)

            connectionState = .ready
            logger.info("iOS auto-reconnect: session ready")

        } catch {
            logger.error("Session setup failed: \(error.localizedDescription)")
            await session?.stop()
            session = nil
            await transport?.disconnect()
            connectionState = .disconnected
            // User can manually retry if needed
        }
    }

    /// Cleans up connection state after failure or disconnect
    private func cleanupConnection() async {
        connectionState = .disconnected
        connectedDevice = nil
        services = nil
        session = nil
        transport = nil
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

        if connectedDevice?.id == bluetoothID {
            Task {
                await disconnect()
            }
        }

        // Clear persisted connection if it was this device
        if lastConnectedDeviceID == bluetoothID {
            clearPersistedConnection()
        }
    }
}
