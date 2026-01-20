import SwiftUI
import Charts

struct NoiseFloorView: View {
    @Environment(\.appState) private var appState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var viewModel = NoiseFloorViewModel()
    @State private var chartStartTime = Date()

    private var isConnected: Bool {
        appState.services?.session != nil
    }

    var body: some View {
        Group {
            if !isConnected {
                disconnectedState
            } else if viewModel.readings.isEmpty {
                collectingState
            } else {
                mainContent
            }
        }
        .task(id: appState.servicesVersion) {
            chartStartTime = Date()
            viewModel.startPolling(appState: appState)
        }
        .onDisappear {
            viewModel.stopPolling()
        }
    }
}

// MARK: - Empty States

extension NoiseFloorView {
    private var disconnectedState: some View {
        ContentUnavailableView {
            Label("Not Connected", systemImage: "antenna.radiowaves.left.and.right.slash")
        } description: {
            Text("Connect to a mesh radio to measure noise floor.")
        }
    }

    private var collectingState: some View {
        ContentUnavailableView {
            Label("Collecting Data...", systemImage: "antenna.radiowaves.left.and.right")
        } description: {
            Text("Noise floor readings will appear as they are collected.")
        }
    }
}

// MARK: - Main Content

extension NoiseFloorView {
    private var mainContent: some View {
        VStack(spacing: 16) {
            if let error = viewModel.error {
                ErrorBanner(message: error)
            }

            ChartSection(viewModel: viewModel, startTime: chartStartTime)

            if horizontalSizeClass == .compact {
                VStack(spacing: 16) {
                    CurrentReadingSection(viewModel: viewModel)
                    StatisticsSection(viewModel: viewModel)
                }
            } else {
                HStack(spacing: 16) {
                    CurrentReadingSection(viewModel: viewModel)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    StatisticsSection(viewModel: viewModel)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
    }
}

// MARK: - Error Banner

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.subheadline)
            Spacer()
        }
        .padding()
        .liquidGlass(in: .rect(cornerRadius: 12))
    }
}

// MARK: - Current Reading Section

private struct CurrentReadingSection: View {
    let viewModel: NoiseFloorViewModel

    private var displayValue: Int16 {
        viewModel.currentReading?.noiseFloor ?? 0
    }

    var body: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)

            Text(displayValue, format: .number)
                .font(.largeTitle)
                .fontDesign(.rounded)
                .monospacedDigit()

            Text("dBm")
                .font(.title3)
                .foregroundStyle(.secondary)

            qualityBadge

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .liquidGlass(in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.updatesFrequently)
    }

    @ViewBuilder
    private var qualityBadge: some View {
        let quality = viewModel.qualityLevel
        if quality != .unknown {
            HStack(spacing: 4) {
                Image(systemName: quality.icon)
                Text(quality.label)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(quality.color.opacity(0.2), in: .capsule)
            .foregroundStyle(quality.color)
        }
    }

    private var accessibilityLabel: String {
        guard let reading = viewModel.currentReading else {
            return "No reading available"
        }
        let quality = viewModel.qualityLevel
        return "\(reading.noiseFloor) decibel-milliwatts, \(quality.label) signal quality"
    }
}

// MARK: - Chart Section

private struct ChartSection: View {
    let viewModel: NoiseFloorViewModel
    let startTime: Date

    private var trendDescription: String {
        let readings = viewModel.readings
        guard readings.count >= 4 else { return "stable" }

        let halfCount = readings.count / 2
        let firstHalf = readings.prefix(halfCount)
        let secondHalf = readings.suffix(halfCount)

        let firstAvg = firstHalf.map { Int($0.noiseFloor) }.reduce(0, +) / max(1, halfCount)
        let secondAvg = secondHalf.map { Int($0.noiseFloor) }.reduce(0, +) / max(1, halfCount)

        if secondAvg > firstAvg + 3 {
            return "increasing"
        } else if secondAvg < firstAvg - 3 {
            return "decreasing"
        }
        return "stable"
    }

    private var chartAccessibilityLabel: String {
        let count = viewModel.readings.count
        guard count > 0, let stats = viewModel.statistics else {
            return "Noise floor history chart, no data"
        }

        return "Noise floor history: \(count) readings, minimum \(stats.min) dBm, maximum \(stats.max) dBm, average \(Int(stats.average)) dBm, trend \(trendDescription)"
    }

    private var chartDomain: ClosedRange<Double> {
        guard let lastReading = viewModel.readings.last else {
            return 0...300
        }
        let latestElapsed = lastReading.timestamp.timeIntervalSince(startTime)
        if latestElapsed <= 300 {
            return 0...300
        }
        return (latestElapsed - 300)...latestElapsed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Noise Floor")
                .font(.headline)

            Chart(viewModel.readings) { reading in
                let elapsed = reading.timestamp.timeIntervalSince(startTime)
                LineMark(
                    x: .value("Time", elapsed),
                    y: .value("dBm", reading.noiseFloor)
                )
                .foregroundStyle(.blue.gradient)

                AreaMark(
                    x: .value("Time", elapsed),
                    yStart: .value("Min", -130),
                    yEnd: .value("dBm", reading.noiseFloor)
                )
                .foregroundStyle(.blue.opacity(0.1))
            }
            .chartYScale(domain: -130 ... -60)
            .chartXScale(domain: chartDomain)
            .chartXAxis {
                AxisMarks(values: .stride(by: 60)) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let seconds = value.as(Double.self) {
                            let minute = Int(seconds) / 60
                            Text("\(minute):00")
                                .monospacedDigit()
                        }
                    }
                }
            }
            .chartPlotStyle { content in
                content.clipped()
            }
            .frame(maxHeight: .infinity)
            .accessibilityLabel(chartAccessibilityLabel)
        }
        .frame(maxHeight: .infinity)
        .padding()
        .liquidGlass(in: .rect(cornerRadius: 12))
    }
}

// MARK: - Statistics Section

private struct StatisticsSection: View {
    let viewModel: NoiseFloorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Statistics")
                .font(.headline)

            if let stats = viewModel.statistics {
                Grid(alignment: .leading, verticalSpacing: 6) {
                    statRow(label: "Minimum", value: Int(stats.min), unit: "dBm")
                    statRow(label: "Average", value: stats.average, unit: "dBm", precision: 1)
                    statRow(label: "Maximum", value: Int(stats.max), unit: "dBm")

                    Divider()
                        .gridCellColumns(4)

                    if let reading = viewModel.currentReading {
                        statRow(label: "Last RSSI", value: Int(reading.lastRSSI), unit: "dBm")
                        statRow(label: "Last SNR", value: reading.lastSNR, unit: "dB", precision: 1)
                    }
                }
                .font(.subheadline)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .liquidGlass(in: .rect(cornerRadius: 12))
    }

    private func statRow(label: String, value: Int, unit: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value, format: .number)
                .monospacedDigit()
            Text(unit)
                .foregroundStyle(.secondary)
        }
    }

    private func statRow(label: String, value: Double, unit: String, precision: Int) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value, format: .number.precision(.fractionLength(precision)))
                .monospacedDigit()
            Text(unit)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        NoiseFloorView()
    }
    .environment(\.appState, AppState())
}
