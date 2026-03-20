import MC1Services
import MeshCore
import SwiftUI

@Observable
@MainActor
final class TelemetryHistoryOverviewViewModel {

    // MARK: - State

    private(set) var snapshots: [NodeStatusSnapshotDTO] = []
    private(set) var ocvArray: [Int] = OCVPreset.liIon.ocvArray
    var timeRange: HistoryTimeRange = .all

    // MARK: - Computed

    var filteredSnapshots: [NodeStatusSnapshotDTO] {
        guard let start = timeRange.startDate else { return snapshots }
        return snapshots.filter { $0.timestamp >= start }
    }

    var hasSnapshots: Bool { !snapshots.isEmpty }

    var hasNeighborData: Bool {
        filteredSnapshots.contains { $0.neighborSnapshots?.isEmpty == false }
    }

    var hasTelemetryData: Bool {
        filteredSnapshots.contains { $0.telemetryEntries?.isEmpty == false }
    }

    var channelGroups: [ChannelGroup] {
        let allEntries = filteredSnapshots.flatMap { snapshot in
            (snapshot.telemetryEntries ?? []).map { (snapshot: snapshot, entry: $0) }
        }

        guard !allEntries.isEmpty else { return [] }

        var channelTypeGroups: [Int: [String: TelemetryChartGroup]] = [:]

        for item in allEntries {
            let channel = item.entry.channel
            let type = item.entry.type
            let point = MetricChartView.DataPoint(
                id: item.snapshot.id,
                date: item.snapshot.timestamp,
                value: item.entry.value
            )

            channelTypeGroups[channel, default: [:]][type, default: TelemetryChartGroup(
                key: "\(channel)-\(type)", title: type, sensorType: LPPSensorType(name: type), dataPoints: []
            )].dataPoints.append(point)
        }

        return channelTypeGroups.keys.sorted().map { channel in
            let charts = channelTypeGroups[channel]!.values.sorted { lhs, rhs in
                let lhsPriority = lhs.sensorType?.chartSortPriority ?? 1
                let rhsPriority = rhs.sensorType?.chartSortPriority ?? 1
                if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            return ChannelGroup(channel: channel, charts: charts)
        }
    }

    // MARK: - Loading

    func loadData(dataStore: PersistenceStore, publicKey: Data, deviceID: UUID) async {
        do {
            snapshots = try await dataStore.fetchNodeStatusSnapshots(
                nodePublicKey: publicKey, since: nil
            )
        } catch {
            snapshots = []
        }

        do {
            if let contact = try await dataStore.fetchContact(
                deviceID: deviceID, publicKey: publicKey
            ) {
                ocvArray = contact.activeOCVArray
            }
        } catch {
            // Keep default liIon
        }
    }
}

// MARK: - Supporting Types

struct ChannelGroup: Identifiable {
    let channel: Int
    let charts: [TelemetryChartGroup]
    var id: Int { channel }
}

struct TelemetryChartGroup: Identifiable {
    let key: String
    let title: String
    let sensorType: LPPSensorType?
    var dataPoints: [MetricChartView.DataPoint]
    var id: String { key }
}
