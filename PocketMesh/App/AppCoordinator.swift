import SwiftUI
import SwiftData
import OSLog
import PocketMeshKit

private let logger = Logger(subsystem: "com.pocketmesh.app", category: "Coordinator")

@MainActor
final class AppCoordinator: ObservableObject {

    @Published var hasCompletedOnboarding: Bool = false
    @Published var connectedDevice: Device?
    @Published var bleManager: BLEManager?
    @Published var meshProtocol: MeshCoreProtocol?

    // Services
    var messageService: MessageService?
    var advertisementService: AdvertisementService?
    var channelService: ChannelService?
    var pollingService: MessagePollingService?

    private let modelContext: ModelContext

    init() {
        self.modelContext = PersistenceController.shared.container.mainContext

        // Check if already onboarded
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func initialize() {
        logger.info("App coordinator initializing")

        // Observe BLE connection restoration
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("BLEConnectionRestored"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleBLEConnectionRestored()
            }
        }

        // If onboarded, attempt to reconnect to last device
        if hasCompletedOnboarding {
            Task {
                await loadActiveDevice()
            }
        }
    }

    private func handleBLEConnectionRestored() {
        logger.info("BLE connection restored - reinitializing services")

        // Reinitialize services if we have both BLE manager and protocol
        if bleManager != nil && meshProtocol != nil {
            initializeServices()
        }
    }

    func completeOnboarding(device: Device?) {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        hasCompletedOnboarding = true
        connectedDevice = device

        // Only initialize services if we have a device
        if device != nil {
            initializeServices()
        }
    }

    private func loadActiveDevice() async {
        do {
            let repository = DeviceRepository(modelContext: modelContext)
            if let device = try repository.getActiveDevice() {
                connectedDevice = device
                initializeServices()
            }
        } catch {
            logger.error("Failed to load active device: \(error.localizedDescription)")
        }
    }

    private func initializeServices() {
        guard let bleManager = bleManager,
              let meshProtocol = meshProtocol else {
            return
        }

        let deviceRepo = DeviceRepository(modelContext: modelContext)

        messageService = MessageService(protocol: meshProtocol, modelContext: modelContext)
        advertisementService = AdvertisementService(protocol: meshProtocol, modelContext: modelContext)
        channelService = ChannelService(protocol: meshProtocol, modelContext: modelContext)
        pollingService = MessagePollingService(
            protocol: meshProtocol,
            modelContext: modelContext,
            deviceRepository: deviceRepo
        )

        pollingService?.startPolling()
    }
}
