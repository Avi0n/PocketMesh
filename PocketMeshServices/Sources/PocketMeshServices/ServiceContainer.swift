import Foundation
import OSLog
import SwiftData
import MeshCore

/// Dependency injection container for PocketMeshServices.
///
/// `ServiceContainer` creates and manages all services needed by the PocketMesh app,
/// handling the dependency graph between services. It provides a single point of
/// initialization for the service layer.
///
/// ## Usage
///
/// ```swift
/// // Create container with session and model container
/// let container = ServiceContainer(
///     session: meshCoreSession,
///     modelContainer: modelContainer
/// )
///
/// // Wire up inter-service dependencies
/// await container.wireServices()
///
/// // Start event monitoring when device is connected
/// await container.startEventMonitoring(deviceID: deviceUUID)
/// ```
///
/// ## Service Dependencies
///
/// Services are initialized in dependency order:
/// 1. Independent services (KeychainService, NotificationService)
/// 2. Core services (ContactService, MessageService, ChannelService, etc.)
/// 3. Higher-level services (RemoteNodeService, RepeaterAdminService, RoomServerService)
@MainActor
@Observable
public final class ServiceContainer {

    // MARK: - Core Infrastructure

    /// The MeshCore session for device communication
    public let session: MeshCoreSession

    /// The persistence store for SwiftData operations
    public let dataStore: PersistenceStore

    // MARK: - Independent Services

    /// Keychain service for secure credential storage
    public let keychainService: KeychainService

    /// Notification service for local notifications
    public let notificationService: NotificationService

    // MARK: - Core Services

    /// Service for managing contacts
    public let contactService: ContactService

    /// Service for sending and receiving messages
    public let messageService: MessageService

    /// Service for managing channels (groups)
    public let channelService: ChannelService

    /// Service for device settings management
    public let settingsService: SettingsService

    /// Service for device data persistence
    public let deviceService: DeviceService

    /// Service for advertisements and path discovery
    public let advertisementService: AdvertisementService

    /// Service for polling and routing messages
    public let messagePollingService: MessagePollingService

    /// Service for binary protocol operations (telemetry, status, etc.)
    public let binaryProtocolService: BinaryProtocolService

    // MARK: - Remote Node Services

    /// Service for remote node session management
    public let remoteNodeService: RemoteNodeService

    /// Service for repeater administration
    public let repeaterAdminService: RepeaterAdminService

    /// Service for room server operations
    public let roomServerService: RoomServerService

    // MARK: - Sync Coordination

    /// Sync coordinator for managing sync lifecycle
    public let syncCoordinator: SyncCoordinator

    // MARK: - State

    /// Whether services have been wired together
    private var isWired = false

    /// Whether event monitoring is active
    private var isMonitoringEvents = false

    // MARK: - Initialization

    /// Creates a new service container.
    ///
    /// - Parameters:
    ///   - session: The MeshCoreSession for device communication
    ///   - modelContainer: The SwiftData model container for persistence
    public init(session: MeshCoreSession, modelContainer: ModelContainer) {
        self.session = session
        self.dataStore = PersistenceStore(modelContainer: modelContainer)

        // Independent services (no dependencies)
        self.keychainService = KeychainService()
        self.notificationService = NotificationService()

        // Core services (depend on session and/or dataStore)
        self.contactService = ContactService(session: session, dataStore: dataStore)
        self.messageService = MessageService(session: session, dataStore: dataStore)
        self.channelService = ChannelService(session: session, dataStore: dataStore)
        self.settingsService = SettingsService(session: session)
        self.deviceService = DeviceService(dataStore: dataStore)
        self.advertisementService = AdvertisementService(session: session, dataStore: dataStore)
        self.messagePollingService = MessagePollingService(session: session, dataStore: dataStore)
        self.binaryProtocolService = BinaryProtocolService(session: session, dataStore: dataStore)

        // Higher-level services (depend on other services)
        self.remoteNodeService = RemoteNodeService(
            session: session,
            dataStore: dataStore,
            keychainService: keychainService
        )
        self.repeaterAdminService = RepeaterAdminService(
            session: session,
            remoteNodeService: remoteNodeService,
            dataStore: dataStore
        )
        self.roomServerService = RoomServerService(
            session: session,
            remoteNodeService: remoteNodeService,
            dataStore: dataStore
        )

        // Sync coordinator (no dependencies on other services)
        self.syncCoordinator = SyncCoordinator()
    }

    // MARK: - Service Wiring

    /// Wires up inter-service dependencies.
    ///
    /// Call this after initialization to establish connections between services
    /// that need to communicate with each other.
    public func wireServices() async {
        guard !isWired else { return }

        // Wire message service to contact service for path management during retry
        await messageService.setContactService(contactService)

        // Wire contact service to sync coordinator for UI refresh notifications
        await contactService.setSyncCoordinator(syncCoordinator)

        isWired = true
    }

    // MARK: - Event Monitoring

    /// Starts event monitoring for all services.
    ///
    /// Call this after a device is connected to begin processing events
    /// from the MeshCoreSession.
    ///
    /// - Parameter deviceID: The connected device's UUID
    public func startEventMonitoring(deviceID: UUID) async {
        guard !isMonitoringEvents else { return }

        // Start event monitoring for services that need it
        await advertisementService.startEventMonitoring(deviceID: deviceID)
        await messageService.startEventListening()
        await remoteNodeService.startEventMonitoring()
        await messagePollingService.startAutoFetch(deviceID: deviceID)

        isMonitoringEvents = true
    }

    /// Stops event monitoring for all services.
    ///
    /// Call this when disconnecting from a device.
    public func stopEventMonitoring() async {
        guard isMonitoringEvents else { return }

        await advertisementService.stopEventMonitoring()
        await messageService.stopEventListening()
        await messagePollingService.stopAutoFetch()
        // RemoteNodeService event monitoring is per-session, handled internally

        isMonitoringEvents = false
    }

    // MARK: - Initial Sync

    /// Performs initial sync of contacts and channels from the device.
    ///
    /// This method checks for task cancellation between sync operations.
    /// Call after connection is established to ensure device data is current.
    ///
    /// - Parameter deviceID: The connected device's UUID
    public func performInitialSync(deviceID: UUID) async {
        let logger = Logger(subsystem: "com.pocketmesh.services", category: "ServiceContainer")

        // Sync contacts
        guard !Task.isCancelled else { return }
        do {
            let result = try await contactService.syncContacts(deviceID: deviceID)
            if result.contactsReceived > 0 {
                logger.info("Initial sync: \(result.contactsReceived) contacts synced")
            }
        } catch {
            logger.warning("Initial sync: contact sync failed: \(error)")
        }

        // Sync channels
        guard !Task.isCancelled else { return }
        do {
            // Fetch device to get maxChannels
            guard let device = try await dataStore.fetchDevice(id: deviceID) else {
                logger.warning("Initial sync: device not found for channel sync")
                return
            }

            let result = try await channelService.syncChannels(deviceID: deviceID, maxChannels: device.maxChannels)
            if result.channelsSynced > 0 {
                logger.info("Initial sync: \(result.channelsSynced) channels synced")
            }
        } catch {
            logger.warning("Initial sync: channel sync failed: \(error)")
        }
    }

    // MARK: - Convenience Methods

    /// Performs initial database warm-up.
    ///
    /// Call this early during app launch to avoid lazy initialization delays.
    public func warmUp() async throws {
        try await dataStore.warmUp()
    }

    /// Resets all remote node session connections.
    ///
    /// Call this on app launch since connections don't persist across app restarts.
    public func resetRemoteNodeConnections() async throws {
        try await dataStore.resetAllRemoteNodeSessionConnections()
    }
}

// MARK: - Factory Methods

extension ServiceContainer {

    /// Creates a service container with a new in-memory model container.
    ///
    /// Useful for testing and previews.
    ///
    /// - Parameter session: The MeshCoreSession for device communication
    /// - Returns: A configured ServiceContainer with in-memory storage
    public static func forTesting(session: MeshCoreSession) throws -> ServiceContainer {
        let container = try PersistenceStore.createContainer(inMemory: true)
        return ServiceContainer(session: session, modelContainer: container)
    }
}
