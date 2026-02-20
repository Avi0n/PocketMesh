import Charts
import PocketMeshServices
import SwiftUI

/// Drill-down view showing historical charts for telemetry metrics grouped by channel and type.
struct TelemetryHistoryView: View {
    let fetchSnapshots: @Sendable () async -> [NodeStatusSnapshotDTO]
    let ocvArray: [Int]

    private let voltageChartBufferMV = 500

    private var voltageYAxisDomain: ClosedRange<Double>? {
        guard let min = ocvArray.min(), let max = ocvArray.max() else { return nil }
        let yMin = Double(min - voltageChartBufferMV) / 1000.0
        let yMax = Double(max + voltageChartBufferMV) / 1000.0
        return yMin...yMax
    }

    @State private var snapshots: [NodeStatusSnapshotDTO] = []
    @State private var timeRange: HistoryTimeRange = .all

    private var filteredSnapshots: [NodeStatusSnapshotDTO] {
        guard let start = timeRange.startDate else { return snapshots }
        return snapshots.filter { $0.timestamp >= start }
    }

    var body: some View {
        List {
            HistoryTimeRangePicker(selection: $timeRange)

            let groups = channelGroups
            if groups.count > 1 {
                ForEach(groups) { channelGroup in
                    Section {
                        ForEach(channelGroup.charts, id: \.key) { chart in
                            chartView(for: chart)
                        }
                    } header: {
                        Text(L10n.RemoteNodes.RemoteNodes.Status.channel(channelGroup.channel))
                    }
                }
            } else if let singleGroup = groups.first {
                ForEach(singleGroup.charts, id: \.key) { chart in
                    Section {
                        chartView(for: chart)
                    }
                }
            }
        }
        .navigationTitle(L10n.RemoteNodes.RemoteNodes.Status.telemetry)
        .liquidGlassToolbarBackground()
        .task {
            snapshots = await fetchSnapshots()
        }
    }

    private func chartView(for chart: TelemetryChartGroup) -> MetricChartView {
        MetricChartView(
            title: chart.title,
            unit: telemetryUnit(for: chart.typeName),
            dataPoints: chart.dataPoints,
            accentColor: telemetryColor(for: chart.typeName),
            yAxisDomain: chart.typeName == "Voltage" ? voltageYAxisDomain : nil
        )
    }

    private var channelGroups: [ChannelGroup] {
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
                key: "\(channel)-\(type)", title: type, typeName: type, dataPoints: []
            )].dataPoints.append(point)
        }

        return channelTypeGroups.keys.sorted().map { channel in
            let charts = channelTypeGroups[channel]!.values.sorted { lhs, rhs in
                let lhsIsVoltage = lhs.typeName == "Voltage"
                let rhsIsVoltage = rhs.typeName == "Voltage"
                if lhsIsVoltage != rhsIsVoltage { return lhsIsVoltage }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
            return ChannelGroup(channel: channel, charts: charts)
        }
    }
}

// MARK: - Supporting Types

private struct ChannelGroup: Identifiable {
    let channel: Int
    let charts: [TelemetryChartGroup]
    var id: Int { channel }
}

private struct TelemetryChartGroup {
    let key: String
    let title: String
    let typeName: String
    var dataPoints: [MetricChartView.DataPoint]
}

// MARK: - Telemetry Display Helpers

private func telemetryUnit(for type: String) -> String {
    switch type {
    case "Voltage": "V"
    case "Temperature": "\u{00B0}C"
    case "Humidity": "%"
    case "Pressure": "hPa"
    case "Illuminance": "lux"
    case "Current": "A"
    case "Power": "W"
    case "Frequency": "Hz"
    case "Altitude": "m"
    case "Distance": "m"
    case "Energy": "kWh"
    case "Direction": "\u{00B0}"
    case "Percentage": "%"
    default: ""
    }
}

private func telemetryColor(for type: String) -> Color {
    switch type {
    case "Voltage": .orange
    case "Temperature": .red
    case "Humidity": .teal
    case "Pressure": .purple
    case "Illuminance": .yellow
    case "Current": .mint
    case "Power": .pink
    case "Frequency": .blue
    case "Altitude": .green
    case "Distance": .green
    case "Energy": .orange
    case "Direction": .indigo
    case "Percentage": .cyan
    default: .cyan
    }
}
