import SwiftUI
import Charts
import PocketMeshServices

struct SavedPathDetailView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel: SavedPathDetailViewModel

    init(savedPath: SavedTracePathDTO) {
        _viewModel = State(initialValue: SavedPathDetailViewModel(savedPath: savedPath))
    }

    var body: some View {
        List {
            pathSection
            performanceSection
            historySection
        }
        .navigationTitle(viewModel.savedPath.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            viewModel.configure(appState: appState)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Path Section

    private var pathSection: some View {
        Section("Path") {
            PathChipsView(pathBytes: viewModel.savedPath.pathHashBytes)
        }
    }

    // MARK: - Performance Section

    private var performanceSection: some View {
        Section("Performance") {
            // Chart
            if viewModel.successfulRuns.count >= 2 {
                Chart(viewModel.successfulRuns) { run in
                    LineMark(
                        x: .value("Date", run.date),
                        y: .value("RTT", run.roundTripMs)
                    )
                    .foregroundStyle(.blue)

                    PointMark(
                        x: .value("Date", run.date),
                        y: .value("RTT", run.roundTripMs)
                    )
                    .foregroundStyle(.blue)
                }
                .frame(height: 150)
                .chartYAxisLabel("Round Trip (ms)")
            }

            // Summary stats
            HStack {
                StatView(label: "Avg", value: viewModel.averageRoundTrip.map { "\($0) ms" } ?? "-")
                Divider()
                StatView(label: "Best", value: viewModel.bestRoundTrip.map { "\($0) ms" } ?? "-")
                Divider()
                StatView(label: "Success", value: viewModel.successRateText)
            }
            .frame(height: 50)
        }
    }

    // MARK: - History Section

    private var historySection: some View {
        Section("History") {
            ForEach(viewModel.sortedRuns) { run in
                NavigationLink {
                    RunDetailView(run: run)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(run.date.formatted(date: .abbreviated, time: .shortened))
                            if run.success {
                                Text("\(run.roundTripMs) ms")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        if !run.success {
                            Text("Failed")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.red.opacity(0.2), in: .capsule)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Views

private struct PathChipsView: View {
    let pathBytes: [UInt8]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 4) {
                ForEach(Array(pathBytes.enumerated()), id: \.offset) { index, byte in
                    if index > 0 {
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(byte.hexString)
                        .font(.caption.monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.fill.tertiary, in: .capsule)
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

private struct StatView: View {
    let label: String
    let value: String

    var body: some View {
        VStack {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RunDetailView: View {
    let run: TracePathRunDTO

    var body: some View {
        List {
            Section("Overview") {
                LabeledContent("Date", value: run.date.formatted())
                LabeledContent("Round Trip", value: "\(run.roundTripMs) ms")
                LabeledContent("Status", value: run.success ? "Success" : "Failed")
            }

            if run.success && !run.hopsSNR.isEmpty {
                Section("Per-Hop SNR") {
                    ForEach(Array(run.hopsSNR.enumerated()), id: \.offset) { index, snr in
                        LabeledContent("Hop \(index + 1)") {
                            Text(snr, format: .number.precision(.fractionLength(2)))
                            + Text(" dB")
                        }
                    }
                }
            }
        }
        .navigationTitle("Run Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}
