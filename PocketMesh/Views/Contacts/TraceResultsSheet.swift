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
                ForEach(result.hops) { hop in
                    TraceResultHopRow(hop: hop)
                }

                // Duration row with optional comparison
                if viewModel.isRunningSavedPath, let previous = viewModel.previousRun {
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
}

// MARK: - Result Hop Row

/// Row for displaying a hop in the trace results
struct TraceResultHopRow: View {
    let hop: TraceHop

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

                // SNR display using sender attribution:
                // Shows how well the NEXT hop received this node's transmission.
                // End node has no SNR (no next hop to measure).
                if hop.isEndNode {
                    // No SNR for end node - no next hop
                } else {
                    Text("SNR: \(hop.snr, format: .number.precision(.fractionLength(2))) dB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Signal strength indicator (not for end node - no next hop)
            if !hop.isEndNode {
                Image(systemName: "cellularbars", variableValue: hop.signalLevel)
                    .foregroundStyle(hop.signalColor)
                    .font(.title2)
            }
        }
        .padding(.vertical, 4)
    }
}
