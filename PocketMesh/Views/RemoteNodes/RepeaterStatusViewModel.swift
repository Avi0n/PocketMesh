import SwiftUI
import PocketMeshServices

/// ViewModel for repeater status display
@Observable
@MainActor
final class RepeaterStatusViewModel {

    // MARK: - Properties

    /// Current session
    var session: RemoteNodeSessionDTO?

    /// Last received status
    var status: RemoteNodeStatus?

    /// Neighbor entries
    var neighbors: [NeighbourInfo] = []

    /// Last received telemetry
    var telemetry: TelemetryResponse?

    /// Loading states
    var isLoadingStatus = false
    var isLoadingNeighbors = false
    var isLoadingTelemetry = false

    /// Whether neighbors have been loaded at least once (for refresh logic)
    var neighborsLoaded = false

    /// Whether the neighbors disclosure group is expanded
    var neighborsExpanded = false

    /// Error message if any
    var errorMessage: String?

    // MARK: - Dependencies

    private var repeaterAdminService: RepeaterAdminService?

    // MARK: - Initialization

    init() {}

    /// Configure with services from AppState
    func configure(appState: AppState) {
        self.repeaterAdminService = appState.services?.repeaterAdminService
        // Handler registration moved to registerHandlers() called from view's .task modifier
    }

    /// Register for push notification handlers
    /// Called from view's .task modifier to ensure proper lifecycle management
    /// This method is idempotent - it clears existing handlers before registering new ones
    func registerHandlers(appState: AppState) async {
        guard let repeaterAdminService = appState.services?.repeaterAdminService else { return }

        // Clear any existing handlers first (idempotent setup)
        await repeaterAdminService.clearHandlers()

        await repeaterAdminService.setStatusHandler { [weak self] status in
            await MainActor.run {
                self?.handleStatusResponse(status)
            }
        }

        await repeaterAdminService.setNeighboursHandler { [weak self] response in
            await MainActor.run {
                self?.handleNeighboursResponse(response)
            }
        }

        await repeaterAdminService.setTelemetryHandler { [weak self] response in
            await MainActor.run {
                self?.handleTelemetryResponse(response)
            }
        }
    }

    // MARK: - Status

    /// Timeout duration for status/neighbors requests
    private static let requestTimeout: Duration = .seconds(15)

    /// Timeout task for status request
    private var statusTimeoutTask: Task<Void, Never>?

    /// Timeout task for neighbors request
    private var neighborsTimeoutTask: Task<Void, Never>?

    /// Timeout task for telemetry request
    private var telemetryTimeoutTask: Task<Void, Never>?

    /// Request status from the repeater
    func requestStatus(for session: RemoteNodeSessionDTO) async {
        guard let repeaterAdminService else { return }

        self.session = session
        isLoadingStatus = true
        errorMessage = nil

        // Start timeout
        statusTimeoutTask?.cancel()
        statusTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.requestTimeout)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                if self?.isLoadingStatus == true && self?.status == nil {
                    self?.errorMessage = "Request timed out"
                    self?.isLoadingStatus = false
                }
            }
        }

        do {
            let response = try await repeaterAdminService.requestStatus(sessionID: session.id)
            handleStatusResponse(response)
        } catch {
            errorMessage = error.localizedDescription
            isLoadingStatus = false
            statusTimeoutTask?.cancel()
        }
    }

    /// Request neighbors from the repeater
    func requestNeighbors(for session: RemoteNodeSessionDTO) async {
        guard let repeaterAdminService else { return }

        self.session = session
        isLoadingNeighbors = true
        errorMessage = nil

        // Start timeout
        neighborsTimeoutTask?.cancel()
        neighborsTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.requestTimeout)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                if self?.isLoadingNeighbors == true && (self?.neighbors.isEmpty ?? true) {
                    self?.errorMessage = "Request timed out"
                    self?.isLoadingNeighbors = false
                }
            }
        }

        do {
            _ = try await repeaterAdminService.requestNeighbors(sessionID: session.id)
            // Neighbors response arrives via push notification
            // The handler will set isLoadingNeighbors = false when response arrives
        } catch {
            errorMessage = error.localizedDescription
            isLoadingNeighbors = false  // Only clear on error
            neighborsTimeoutTask?.cancel()
        }
        // Note: Don't clear isLoadingNeighbors here - it's cleared by handleNeighboursResponse
    }

    /// Handle status response from push notification
    /// Validates response matches current session before updating
    func handleStatusResponse(_ response: RemoteNodeStatus) {
        // Session validation: only accept responses for our session
        guard let expectedPrefix = session?.publicKeyPrefix,
              response.publicKeyPrefix == expectedPrefix else {
            return  // Ignore responses for other sessions
        }
        statusTimeoutTask?.cancel()  // Cancel timeout on success
        self.status = response
        self.isLoadingStatus = false
    }

    /// Handle neighbours response from push notification
    func handleNeighboursResponse(_ response: NeighboursResponse) {
        // Note: NeighboursResponse may not include source prefix - validate if available
        neighborsTimeoutTask?.cancel()  // Cancel timeout on success
        self.neighbors = response.neighbours
        self.isLoadingNeighbors = false
        self.neighborsLoaded = true
    }

    // MARK: - Telemetry

    /// Request telemetry from the repeater
    func requestTelemetry(for session: RemoteNodeSessionDTO) async {
        guard let repeaterAdminService else { return }

        self.session = session
        isLoadingTelemetry = true

        // Start timeout
        telemetryTimeoutTask?.cancel()
        telemetryTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.requestTimeout)
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                if self?.isLoadingTelemetry == true && self?.telemetry == nil {
                    self?.isLoadingTelemetry = false
                }
            }
        }

        do {
            let response = try await repeaterAdminService.requestTelemetry(sessionID: session.id)
            handleTelemetryResponse(response)
        } catch {
            errorMessage = error.localizedDescription
            isLoadingTelemetry = false
            telemetryTimeoutTask?.cancel()
        }
    }

    /// Handle telemetry response from push notification
    func handleTelemetryResponse(_ response: TelemetryResponse) {
        // Session validation: only accept responses for our session
        guard let expectedPrefix = session?.publicKeyPrefix,
              response.publicKeyPrefix == expectedPrefix else {
            return  // Ignore responses for other sessions
        }
        telemetryTimeoutTask?.cancel()  // Cancel timeout on success
        self.telemetry = response
        self.isLoadingTelemetry = false
    }

    // MARK: - Computed Properties

    var uptimeDisplay: String? {
        guard let uptime = status?.uptimeSeconds else { return nil }
        let hours = uptime / 3600
        let minutes = (uptime % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    var batteryDisplay: String? {
        guard let mv = status?.batteryMillivolts else { return nil }
        let volts = Double(mv) / 1000.0
        return "\(volts.formatted(.number.precision(.fractionLength(2))))V"
    }

    var noiseFloorDisplay: String? {
        guard let nf = status?.noiseFloor else { return nil }
        return "\(nf) dBm"
    }

    var txCountDisplay: String? {
        guard let count = status?.packetsSent else { return nil }
        return count.formatted()
    }

    var rxCountDisplay: String? {
        guard let count = status?.packetsReceived else { return nil }
        return count.formatted()
    }

    var airTimeDisplay: String? {
        guard let seconds = status?.repeaterRxAirtimeSeconds else { return nil }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
