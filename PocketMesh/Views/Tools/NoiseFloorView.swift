import SwiftUI
import Charts

struct NoiseFloorView: View {
    @Environment(\.appState) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel = NoiseFloorViewModel()

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
        .navigationTitle("Noise Floor")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                liveStatusPill
            }
        }
        .task(id: appState.servicesVersion) {
            viewModel.startPolling(appState: appState)
        }
        .onDisappear {
            viewModel.stopPolling()
        }
    }
}

// MARK: - Live Status

extension NoiseFloorView {
    private var liveStatusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(viewModel.isPolling ? .green : .gray)
                .frame(width: 8, height: 8)
                .modifier(PulseAnimationModifier(isActive: viewModel.isPolling && !reduceMotion))

            Text(viewModel.isPolling ? "Live" : "Paused")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .liquidGlass(in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(viewModel.isPolling ? "Live polling active" : "Polling paused")
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
        ScrollView {
            VStack(spacing: 16) {
                if let error = viewModel.error {
                    ErrorBanner(message: error)
                }

                CurrentReadingSection(viewModel: viewModel)
                ChartSection(viewModel: viewModel)
                StatisticsSection(viewModel: viewModel)
            }
            .padding()
        }
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
            Text(displayValue, format: .number)
                .font(.largeTitle)
                .fontDesign(.rounded)
                .monospacedDigit()

            Text("dBm")
                .font(.title3)
                .foregroundStyle(.secondary)

            qualityBadge
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .liquidGlass(in: .rect(cornerRadius: 16))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("History")
                .font(.headline)

            Chart(viewModel.readings) { reading in
                LineMark(
                    x: .value("Time", reading.timestamp),
                    y: .value("dBm", reading.noiseFloor)
                )
                .foregroundStyle(.blue.gradient)

                AreaMark(
                    x: .value("Time", reading.timestamp),
                    y: .value("dBm", reading.noiseFloor)
                )
                .foregroundStyle(.blue.opacity(0.1))
            }
            .chartYScale(domain: -130 ... -60)
            .chartXAxis {
                AxisMarks(values: .automatic) { _ in
                    AxisGridLine()
                    AxisValueLabel(format: .dateTime.minute().second())
                }
            }
            .frame(height: 200)
            .accessibilityLabel("Noise floor history chart showing \(viewModel.readings.count) readings")
        }
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
        }
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

// MARK: - Pulse Animation Modifier

private struct PulseAnimationModifier: ViewModifier {
    let isActive: Bool

    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isActive && isPulsing ? 0.4 : 1.0)
            .animation(
                isActive ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true) : .default,
                value: isPulsing
            )
            .onAppear {
                if isActive {
                    isPulsing = true
                }
            }
            .onChange(of: isActive) { _, newValue in
                isPulsing = newValue
            }
    }
}

#Preview {
    NavigationStack {
        NoiseFloorView()
    }
    .environment(\.appState, AppState())
}
