import SwiftUI
import PocketMeshKit

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

    /// Loading states
    var isLoadingStatus = false
    var isLoadingNeighbors = false

    /// Error message if any
    var errorMessage: String?

    // MARK: - Dependencies

    private var repeaterAdminService: RepeaterAdminService?

    // MARK: - Initialization

    init() {}

    /// Configure with services from AppState
    func configure(appState: AppState) {
        self.repeaterAdminService = appState.repeaterAdminService
    }

    // MARK: - Status

    /// Request status from the repeater
    func requestStatus(for session: RemoteNodeSessionDTO) async {
        guard let repeaterAdminService else { return }

        self.session = session
        isLoadingStatus = true
        errorMessage = nil

        do {
            _ = try await repeaterAdminService.requestStatus(sessionID: session.id)
            // Status response arrives via push notification
            // The handler will update status property
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingStatus = false
    }

    /// Request neighbors from the repeater
    func requestNeighbors(for session: RemoteNodeSessionDTO) async {
        guard let repeaterAdminService else { return }

        self.session = session
        isLoadingNeighbors = true
        errorMessage = nil

        do {
            _ = try await repeaterAdminService.requestNeighbors(sessionID: session.id)
            // Neighbors response arrives via push notification
            // The handler will update neighbors property
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoadingNeighbors = false
    }

    /// Handle status response from push notification
    func handleStatusResponse(_ response: RemoteNodeStatus) {
        self.status = response
    }

    /// Handle neighbors response from push notification
    func handleNeighborsResponse(_ response: NeighboursResponse) {
        self.neighbors = response.neighbours
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
        return String(format: "%.2fV", volts)
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
