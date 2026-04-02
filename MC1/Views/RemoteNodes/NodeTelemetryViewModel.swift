import OSLog
import MC1Services
import SwiftUI

private let logger = Logger(subsystem: "com.mc1", category: "NodeTelemetryVM")

@Observable
@MainActor
final class NodeTelemetryViewModel {

    // MARK: - Shared Helper

    var helper = NodeStatusHelper()

    // MARK: - Dependencies

    private var binaryProtocolService: BinaryProtocolService?
    private var nodeSnapshotService: NodeSnapshotService?
    private var publicKey: Data?

    // MARK: - Initialization

    func configure(appState: AppState, contact: ContactDTO) {
        self.binaryProtocolService = appState.services?.binaryProtocolService
        self.nodeSnapshotService = appState.services?.nodeSnapshotService
        self.publicKey = contact.publicKey
        helper.configure(
            contactService: appState.services?.contactService,
            nodeSnapshotService: appState.services?.nodeSnapshotService
        )
        helper.configureForDirectTelemetry(publicKey: contact.publicKey)
    }

    // MARK: - Telemetry

    func requestTelemetry() async {
        guard let binaryProtocolService, let publicKey else { return }

        helper.isLoadingTelemetry = true
        helper.errorMessage = nil

        do {
            let response = try await binaryProtocolService.requestTelemetry(from: publicKey)
            helper.handleTelemetryResponse(response)
            await saveTelemetrySnapshot()
        } catch BinaryProtocolError.sessionError(MeshCoreError.timeout) {
            helper.errorMessage = L10n.RemoteNodes.RemoteNodes.Status.telemetryTimedOut
            helper.isLoadingTelemetry = false
        } catch {
            helper.errorMessage = error.localizedDescription
            helper.isLoadingTelemetry = false
        }
    }

    // MARK: - Snapshot Persistence

    private func saveTelemetrySnapshot() async {
        guard let nodeSnapshotService, let publicKey else { return }

        let entries: [TelemetrySnapshotEntry] = helper.cachedDataPoints.compactMap { dp in
            let numericValue: Double?
            switch dp.value {
            case .float(let value): numericValue = value
            case .integer(let value): numericValue = Double(value)
            default: numericValue = nil
            }
            guard let value = numericValue else { return nil }
            return TelemetrySnapshotEntry(channel: Int(dp.channel), type: dp.typeName, value: value)
        }

        guard !entries.isEmpty else { return }
        _ = await nodeSnapshotService.saveTelemetryOnlySnapshot(
            nodePublicKey: publicKey,
            telemetryEntries: entries
        )
    }
}
