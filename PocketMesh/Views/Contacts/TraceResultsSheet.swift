import SwiftUI
import PocketMeshServices

/// Full-screen sheet displaying trace results
struct TraceResultsSheet: View {
    let result: TraceResult
    @Bindable var viewModel: TracePathViewModel
    @Environment(\.dismiss) private var dismiss

    // Save dialog state
    @State private var showingSaveDialog = false
    @State private var savePathName = ""
    @State private var saveHapticTrigger = 0
    @State private var copyHapticTrigger = 0

    var body: some View {
        NavigationStack {
            List {
                resultsSection
                outboundPathSection
            }
            .navigationTitle("Trace Results")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Dismiss", systemImage: "xmark") {
                        dismiss()
                    }
                }
            }
            .sensoryFeedback(.success, trigger: saveHapticTrigger)
            .sensoryFeedback(.success, trigger: copyHapticTrigger)
        }
    }

    // MARK: - Outbound Path Section

    private var outboundPathSection: some View {
        Section {
            HStack {
                Text(result.tracedPathString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Copy Path", systemImage: "doc.on.doc") {
                    copyHapticTrigger += 1
                    UIPasteboard.general.string = result.tracedPathString
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
        } header: {
            Text("Outbound Path")
        }
    }

    // MARK: - Results Section

    private var resultsSection: some View {
        Section {
            if result.success {
                ForEach(Array(result.hops.enumerated()), id: \.element.id) { index, hop in
                    TraceResultHopRow(
                        hop: hop,
                        hopIndex: index,
                        batchStats: viewModel.batchEnabled ? viewModel.hopStats(at: index) : nil,
                        latestSNR: viewModel.batchEnabled ? viewModel.latestHopSNR(at: index) : nil,
                        isBatchInProgress: viewModel.isBatchInProgress
                    )
                }

                // Batch progress indicator
                if viewModel.batchEnabled && viewModel.isBatchInProgress {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Running Trace \(viewModel.currentTraceIndex) of \(viewModel.batchSize)...")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Batch progress: trace \(viewModel.currentTraceIndex) of \(viewModel.batchSize)")
                }

                // Batch completion status
                if viewModel.batchEnabled && viewModel.isBatchComplete {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("\(viewModel.successCount) of \(viewModel.batchSize) successful")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Batch complete: \(viewModel.successCount) of \(viewModel.batchSize) traces successful")
                }

                // Duration row with batch or single display
                if viewModel.batchEnabled && viewModel.successCount > 0 {
                    batchRTTRow
                } else if viewModel.isRunningSavedPath, let previous = viewModel.previousRun {
                    comparisonRow(currentMs: result.durationMs, previousRun: previous)
                } else {
                    HStack {
                        Text("Round Trip")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(result.durationMs) ms")
                            .font(.body.monospacedDigit())
                    }
                }

                // Save path action (only for successful traces when not running a saved path)
                if !viewModel.isRunningSavedPath {
                    savePathRow
                }
            } else if let error = result.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Save Path Row

    @ViewBuilder
    private var savePathRow: some View {
        if showingSaveDialog {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Path name", text: $savePathName)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Cancel") {
                        showingSaveDialog = false
                        savePathName = ""
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Save") {
                        Task {
                            let success = await viewModel.savePath(name: savePathName)
                            if success {
                                saveHapticTrigger += 1
                            }
                            showingSaveDialog = false
                            savePathName = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(savePathName.trimmingCharacters(in: .whitespaces).isEmpty || !viewModel.canSavePath)
                }
            }
            .padding(.vertical, 4)
        } else {
            Button {
                savePathName = viewModel.generatePathName()
                showingSaveDialog = true
            } label: {
                HStack {
                    Label("Save Path", systemImage: "bookmark")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
            .disabled(!viewModel.canSavePath)
        }
    }

    // MARK: - Comparison Row

    @ViewBuilder
    private func comparisonRow(currentMs: Int, previousRun: TracePathRunDTO) -> some View {
        let diff = currentMs - previousRun.roundTripMs
        let percentChange = previousRun.roundTripMs > 0
            ? Double(diff) / Double(previousRun.roundTripMs) * 100
            : 0

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Round Trip")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(currentMs) ms")
                    .font(.body.monospacedDigit())

                // Change indicator
                if diff != 0 {
                    Text(diff > 0 ? "\u{25B2}" : "\u{25BC}")
                        .foregroundStyle(diff > 0 ? .red : .green)
                    Text(abs(percentChange), format: .number.precision(.fractionLength(0)))
                        .font(.caption.monospacedDigit())
                    + Text("%")
                        .font(.caption)
                }
            }

            Text("vs. \(previousRun.roundTripMs) ms on \(previousRun.date.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        // Sparkline with history link
        if let savedPath = viewModel.activeSavedPath, !savedPath.recentRTTs.isEmpty {
            HStack {
                MiniSparkline(values: savedPath.recentRTTs)
                    .frame(height: 20)

                Spacer()

                NavigationLink {
                    SavedPathDetailView(savedPath: savedPath)
                } label: {
                    Text("View \(savedPath.runCount) runs")
                        .font(.caption)
                }
            }
        }
    }

    // MARK: - Batch RTT Row

    @ViewBuilder
    private var batchRTTRow: some View {
        if let avg = viewModel.averageRTT,
           let min = viewModel.minRTT,
           let max = viewModel.maxRTT {
            HStack {
                Text("Avg Round Trip")
                    .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing) {
                    Text("\(avg) ms")
                        .font(.body.monospacedDigit())
                    Text("(\(min)–\(max))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Average round trip: \(avg) milliseconds, range \(min) to \(max)")
        }
    }
}

// MARK: - Result Hop Row

/// Row for displaying a hop in the trace results
struct TraceResultHopRow: View {
    let hop: TraceHop
    let hopIndex: Int
    var batchStats: (avg: Double, min: Double, max: Double)?
    var latestSNR: Double?
    var isBatchInProgress: Bool = false

    /// SNR value to use for signal bars (latest during progress, average when complete)
    private var displaySNR: Double {
        if isBatchInProgress {
            return latestSNR ?? hop.snr
        } else if let stats = batchStats {
            return stats.avg
        } else {
            return hop.snr
        }
    }

    private var signalLevel: Double {
        TraceHop.signalLevel(for: displaySNR)
    }

    private var signalColor: Color {
        TraceHop.signalColor(for: displaySNR)
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                // Node identifier
                if hop.isStartNode {
                    Text(hop.resolvedName ?? "My Device")
                    Text("Started trace")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if hop.isEndNode {
                    Text(hop.resolvedName ?? "My Device")
                        .foregroundStyle(.green)
                    Text("Received response")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let hashDisplay = hop.hashDisplayString {
                    HStack {
                        Text(hashDisplay)
                            .font(.body.monospaced())
                        if let name = hop.resolvedName {
                            Text(name)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Repeated")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // SNR display - batch mode shows avg with range, single shows plain SNR
                if !hop.isStartNode {
                    if let stats = batchStats {
                        Text("Avg SNR: \(stats.avg, format: .number.precision(.fractionLength(1))) dB (\(stats.min, format: .number.precision(.fractionLength(1)))–\(stats.max, format: .number.precision(.fractionLength(1))))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Average signal to noise ratio: \(stats.avg, format: .number.precision(.fractionLength(1))) decibels, range \(stats.min, format: .number.precision(.fractionLength(1))) to \(stats.max, format: .number.precision(.fractionLength(1)))")
                    } else {
                        Text("SNR: \(hop.snr, format: .number.precision(.fractionLength(2))) dB")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Signal strength indicator (not for start node - it didn't receive)
            if !hop.isStartNode {
                Image(systemName: "cellularbars", variableValue: signalLevel)
                    .foregroundStyle(signalColor)
                    .font(.title2)
            }
        }
        .padding(.vertical, 4)
    }
}
