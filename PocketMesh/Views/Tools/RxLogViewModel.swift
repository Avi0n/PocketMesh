// PocketMesh/Views/Tools/RxLogViewModel.swift
import Foundation
import PocketMeshServices

@MainActor
@Observable
final class RxLogViewModel {
    enum RouteFilter: String, CaseIterable {
        case all
        case floodOnly
        case directOnly

        var displayName: String {
            switch self {
            case .all: L10n.Tools.Tools.RxLog.Filter.all
            case .floodOnly: L10n.Tools.Tools.RxLog.Filter.floodOnly
            case .directOnly: L10n.Tools.Tools.RxLog.Filter.directOnly
            }
        }
    }

    enum DecryptFilter: String, CaseIterable {
        case all
        case decrypted
        case failed

        var displayName: String {
            switch self {
            case .all: L10n.Tools.Tools.RxLog.Filter.all
            case .decrypted: L10n.Tools.Tools.RxLog.Filter.decrypted
            case .failed: L10n.Tools.Tools.RxLog.Filter.failed
            }
        }
    }

    private(set) var entries: [RxLogEntryDTO] = []
    private(set) var groupCounts: [String: Int] = [:]
    private(set) var routeFilter: RouteFilter = .all
    private(set) var decryptFilter: DecryptFilter = .all

    private var streamTask: Task<Void, Never>?
    private var rxLogService: RxLogService?

    func setRouteFilter(_ filter: RouteFilter) {
        routeFilter = filter
    }

    func setDecryptFilter(_ filter: DecryptFilter) {
        decryptFilter = filter
    }

    /// Entries filtered by current filter settings.
    var filteredEntries: [RxLogEntryDTO] {
        entries.filter { entry in
            // Route filter
            switch routeFilter {
            case .all: break
            case .floodOnly:
                guard entry.isFlood else { return false }
            case .directOnly:
                guard !entry.isFlood else { return false }
            }

            // Decrypt filter
            switch decryptFilter {
            case .all: break
            case .decrypted:
                guard entry.decryptStatus == .success else { return false }
            case .failed:
                guard entry.decryptStatus == .hmacFailed
                    || entry.decryptStatus == .decryptFailed
                    || entry.decryptStatus == .noMatchingKey else { return false }
            }

            return true
        }
    }

    /// Subscribe to RxLogService for updates while view is visible.
    func subscribe(to service: RxLogService) async {
        // If service changed, reset state
        if rxLogService !== service {
            unsubscribe()
            entries.removeAll()
            groupCounts.removeAll()
        }

        rxLogService = service
        entries = await service.loadExistingEntries()
        rebuildGroupCounts()

        streamTask = Task {
            for await entry in await service.entryStream() {
                guard !Task.isCancelled else { break }
                appendEntry(entry)
            }
        }
    }

    /// Stop listening to updates.
    func unsubscribe() {
        streamTask?.cancel()
        streamTask = nil
    }

    /// Clear all log entries.
    func clearLog() async {
        await rxLogService?.clearEntries()
        entries.removeAll()
        groupCounts.removeAll()
    }

    // MARK: - Incremental Updates

    private func appendEntry(_ entry: RxLogEntryDTO) {
        // Insert at front to maintain newest-first order (matching DB fetch sort)
        entries.insert(entry, at: 0)
        groupCounts[entry.packetHash, default: 0] += 1

        // Prune oldest (now at end) if over cap
        if entries.count > 1000 {
            let removed = entries.removeLast()
            groupCounts[removed.packetHash, default: 1] -= 1
            if groupCounts[removed.packetHash] == 0 {
                groupCounts.removeValue(forKey: removed.packetHash)
            }
        }
    }

    private func rebuildGroupCounts() {
        groupCounts = Dictionary(grouping: entries, by: \.packetHash)
            .mapValues(\.count)
    }
}
