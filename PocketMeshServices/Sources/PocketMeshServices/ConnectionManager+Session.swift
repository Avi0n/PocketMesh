import Foundation
import MeshCore

// MARK: - BLEReconnectionDelegate

extension ConnectionManager: BLEReconnectionDelegate {

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
        let expectedGeneration = reconnectionCoordinator.reconnectGeneration

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

        // Check after await — user may have disconnected or a new reconnect cycle may have started
        guard connectionIntent.wantsConnection else {
            logger.info("User disconnected during session setup")
            await newSession.stop()
            connectionState = .disconnected
            return
        }
        guard reconnectionCoordinator.reconnectGeneration == expectedGeneration else {
            logger.info("[BLE] rebuildSession superseded by new reconnect cycle during session setup")
            await newSession.stop()
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
        guard reconnectionCoordinator.reconnectGeneration == expectedGeneration else {
            logger.info("[BLE] rebuildSession superseded by new reconnect cycle during device query")
            await newSession.stop()
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
        guard reconnectionCoordinator.reconnectGeneration == expectedGeneration else {
            logger.info("[BLE] rebuildSession superseded by new reconnect cycle during service wiring")
            await newSession.stop()
            return
        }

        self.services = newServices

        // Fetch existing device and auto-add config concurrently (independent operations)
        async let existingDeviceResult = newServices.dataStore.fetchDevice(id: deviceID)
        async let autoAddConfigResult = newSession.getAutoAddConfig()
        let existingDevice = try? await existingDeviceResult
        let autoAddConfig = (try? await autoAddConfigResult) ?? MeshCore.AutoAddConfig(bitmask: 0)

        let repeatFreqRanges: [MeshCore.FrequencyRange] = capabilities.clientRepeat
            ? (try? await newSession.getRepeatFreq()) ?? []
            : []

        let device = createDevice(deviceID: deviceID, selfInfo: selfInfo, capabilities: capabilities, autoAddConfig: autoAddConfig, existingDevice: existingDevice)
        try await newServices.dataStore.saveDevice(DeviceDTO(from: device))
        self.connectedDevice = DeviceDTO(from: device)
        self.allowedRepeatFreqRanges = repeatFreqRanges

        // Notify observers BEFORE sync starts so they can wire callbacks
        await onConnectionReady?()
        await performInitialSync(deviceID: deviceID, services: newServices, context: "[BLE] iOS auto-reconnect")

        // User may have disconnected or a new reconnect cycle may have started while sync was in progress
        guard connectionIntent.wantsConnection,
              reconnectionCoordinator.reconnectGeneration == expectedGeneration
        else {
            await newSession.stop()
            return
        }

        await syncDeviceTimeIfNeeded()
        guard connectionIntent.wantsConnection,
              reconnectionCoordinator.reconnectGeneration == expectedGeneration
        else {
            await newSession.stop()
            return
        }

        // Re-authenticate room sessions that were connected before BLE loss
        let sessionIDs = sessionsAwaitingReauth
        sessionsAwaitingReauth = []
        await newServices.remoteNodeService.handleBLEReconnection(sessionIDs: sessionIDs)

        guard connectionIntent.wantsConnection,
              reconnectionCoordinator.reconnectGeneration == expectedGeneration
        else {
            await newSession.stop()
            return
        }

        currentTransportType = .bluetooth
        connectionState = .ready
        await onDeviceSynced?()
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
        allowedRepeatFreqRanges = []

        // Start watchdog to periodically retry if user still wants connection
        if connectionIntent.wantsConnection {
            startReconnectionWatchdog()
        }
    }
}
