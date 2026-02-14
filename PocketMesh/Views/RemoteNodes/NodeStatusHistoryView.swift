import Charts
import PocketMeshServices
import SwiftUI

/// Drill-down view showing historical charts for status metrics (battery, SNR, RSSI, noise floor).
struct NodeStatusHistoryView: View {
    let fetchSnapshots: @Sendable () async -> [NodeStatusSnapshotDTO]

    @State private var snapshots: [NodeStatusSnapshotDTO] = []
    @State private var timeRange: HistoryTimeRange = .all

    private var filteredSnapshots: [NodeStatusSnapshotDTO] {
        guard let start = timeRange.startDate else { return snapshots }
        return snapshots.filter { $0.timestamp >= start }
    }

    var body: some View {
        List {
            HistoryTimeRangePicker(selection: $timeRange)

            metricSection(
                title: L10n.RemoteNodes.RemoteNodes.History.battery, unit: "mV", color: .mint,
                dataPoints: filteredSnapshots.compactMap { s in
                    s.batteryMillivolts.map { .init(id: s.id, date: s.timestamp, value: Double($0)) }
                }
            )

            metricSection(
                title: L10n.RemoteNodes.RemoteNodes.History.snr, unit: "dB", color: .blue,
                dataPoints: filteredSnapshots.compactMap { s in
                    s.lastSNR.map { .init(id: s.id, date: s.timestamp, value: $0) }
                }
            )

            metricSection(
                title: L10n.RemoteNodes.RemoteNodes.History.rssi, unit: "dBm", color: .purple,
                dataPoints: filteredSnapshots.compactMap { s in
                    s.lastRSSI.map { .init(id: s.id, date: s.timestamp, value: Double($0)) }
                }
            )

            metricSection(
                title: L10n.RemoteNodes.RemoteNodes.History.noiseFloor, unit: "dBm", color: .indigo,
                dataPoints: filteredSnapshots.compactMap { s in
                    s.noiseFloor.map { .init(id: s.id, date: s.timestamp, value: Double($0)) }
                }
            )
        }
        .navigationTitle(L10n.RemoteNodes.RemoteNodes.History.title)
        .liquidGlassToolbarBackground()
        .task {
            snapshots = await fetchSnapshots()
        }
    }

    @ViewBuilder
    private func metricSection(
        title: String, unit: String, color: Color,
        dataPoints: [MetricChartView.DataPoint]
    ) -> some View {
        if !dataPoints.isEmpty {
            Section {
                MetricChartView(title: title, unit: unit, dataPoints: dataPoints, accentColor: color)
            }
        }
    }
}
