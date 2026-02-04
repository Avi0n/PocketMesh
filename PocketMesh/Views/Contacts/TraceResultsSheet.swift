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
    @State private var showingDistanceInfo = false

    var body: some View {
        NavigationStack {
            List {
                resultsSection
                outboundPathSection
            }
            .navigationTitle(L10n.Contacts.Contacts.Results.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Contacts.Contacts.Results.dismiss, systemImage: "xmark") {
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

                Button(L10n.Contacts.Contacts.Trace.List.copyPath, systemImage: "doc.on.doc") {
                    copyHapticTrigger += 1
                    UIPasteboard.general.string = result.tracedPathString
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
        } header: {
            Text(L10n.Contacts.Contacts.Trace.List.outboundPath)
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

                // Batch status row (progress or completion)
                if viewModel.batchEnabled && (viewModel.isBatchInProgress || viewModel.isBatchComplete) {
                    HStack {
                        if viewModel.isBatchComplete {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(L10n.Contacts.Contacts.Results.batchSuccess(viewModel.successCount, viewModel.batchSize))
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView()
                                .controlSize(.small)
                            Text(L10n.Contacts.Contacts.Results.batchProgress(viewModel.currentTraceIndex, viewModel.batchSize))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        viewModel.isBatchComplete
                            ? L10n.Contacts.Contacts.Results.batchCompleteLabel(viewModel.successCount, viewModel.batchSize)
                            : L10n.Contacts.Contacts.Results.batchProgressLabel(viewModel.currentTraceIndex, viewModel.batchSize)
                    )
                    .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                }

                // Duration row with batch or single display
                if viewModel.batchEnabled && viewModel.successCount > 0 {
                    batchRTTRow
                } else if viewModel.isRunningSavedPath, let previous = viewModel.previousRun {
                    comparisonRow(currentMs: result.durationMs, previousRun: previous)
                } else {
                    HStack {
                        Text(L10n.Contacts.Contacts.PathDetail.roundTrip)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(result.durationMs) ms")
                            .font(.body.monospacedDigit())
                    }
                }

                // Total distance row
                totalDistanceRow

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
                TextField(L10n.Contacts.Contacts.Trace.Map.pathName, text: $savePathName)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button(L10n.Contacts.Contacts.Common.cancel) {
                        showingSaveDialog = false
                        savePathName = ""
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button(L10n.Contacts.Contacts.Common.save) {
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
                    Label(L10n.Contacts.Contacts.Results.savePath, systemImage: "bookmark")
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
                Text(L10n.Contacts.Contacts.PathDetail.roundTrip)
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

            Text(L10n.Contacts.Contacts.Results.comparison(previousRun.roundTripMs, previousRun.date.formatted(date: .abbreviated, time: .omitted)))
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
                    Text(L10n.Contacts.Contacts.Results.viewRuns(savedPath.runCount))
                        .font(.caption)
                }
            }
            .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
        }
    }

    // MARK: - Batch RTT Row

    @ViewBuilder
    private var batchRTTRow: some View {
        if let avg = viewModel.averageRTT,
           let min = viewModel.minRTT,
           let max = viewModel.maxRTT {
            HStack {
                Text(L10n.Contacts.Contacts.Results.avgRoundTrip)
                    .foregroundStyle(.secondary)
                Spacer()
                VStack(alignment: .trailing) {
                    Text("\(avg) ms")
                        .font(.body.monospacedDigit())
                    Text("(\(min) – \(max))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L10n.Contacts.Contacts.Results.avgRTTLabel(avg, min, max))
        }
    }

    // MARK: - Total Distance Row

    private func formatDistance(_ meters: Double) -> String {
        let measurement = Measurement(value: meters, unit: UnitLength.meters)
        return measurement.formatted(.measurement(width: .abbreviated, usage: .road))
    }

    @ViewBuilder
    private var totalDistanceRow: some View {
        HStack {
            Text(L10n.Contacts.Contacts.Results.totalDistance)
                .foregroundStyle(.secondary)
            Spacer()

            if let distance = viewModel.totalPathDistance {
                HStack {
                    Text(formatDistance(distance))
                        .font(.body.monospacedDigit())
                    if viewModel.isDistanceUsingFallback {
                        Button(L10n.Contacts.Contacts.Results.distanceInfo, systemImage: "info.circle") {
                            showingDistanceInfo = true
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(L10n.Contacts.Contacts.Results.partialDistanceLabel)
                        .accessibilityHint(L10n.Contacts.Contacts.Results.partialDistanceHint)
                    }
                }
            } else {
                HStack {
                    Text(L10n.Contacts.Contacts.Results.unavailable)
                        .foregroundStyle(.secondary)
                    Button(L10n.Contacts.Contacts.Results.distanceInfo, systemImage: "info.circle") {
                        showingDistanceInfo = true
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(L10n.Contacts.Contacts.Results.distanceUnavailableLabel)
                    .accessibilityHint(L10n.Contacts.Contacts.Results.distanceInfoHint)
                }
            }
        }
        .sheet(isPresented: $showingDistanceInfo) {
            distanceInfoSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    private var distanceInfoSheet: some View {
        NavigationStack {
            List {
                if viewModel.isDistanceUsingFallback {
                    Section {
                        Text(L10n.Contacts.Contacts.Results.partialDistanceExplanation)
                    } header: {
                        Label(L10n.Contacts.Contacts.Results.partialDistanceHeader, systemImage: "location.slash")
                    }
                    Section {
                        Text(L10n.Contacts.Contacts.Results.fullPathTip)
                    } header: {
                        Label(L10n.Contacts.Contacts.Results.fullPathHeader, systemImage: "lightbulb")
                    }
                } else if result.hops.filter({ !$0.isStartNode && !$0.isEndNode }).count < 2 {
                    Section {
                        Text(L10n.Contacts.Contacts.Results.needsRepeaters)
                    }
                } else if viewModel.repeatersWithoutLocation.isEmpty {
                    Section {
                        Text(L10n.Contacts.Contacts.Results.distanceError)
                    }
                } else {
                    Section {
                        Text(L10n.Contacts.Contacts.Results.missingLocations)
                    }
                    Section(L10n.Contacts.Contacts.Results.repeatersWithoutLocations) {
                        ForEach(viewModel.repeatersWithoutLocation, id: \.self) { name in
                            Text(name)
                        }
                    }
                }
            }
            .navigationTitle(viewModel.isDistanceUsingFallback ? L10n.Contacts.Contacts.Results.distanceInfoTitlePartial : L10n.Contacts.Contacts.Results.distanceInfoTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L10n.Contacts.Contacts.Common.done) {
                        showingDistanceInfo = false
                    }
                }
            }
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
                    Text(hop.resolvedName ?? L10n.Contacts.Contacts.Results.Hop.myDevice)
                    Text(L10n.Contacts.Contacts.Results.Hop.started)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if hop.isEndNode {
                    Text(hop.resolvedName ?? L10n.Contacts.Contacts.Results.Hop.myDevice)
                        .foregroundStyle(.green)
                    Text(L10n.Contacts.Contacts.Results.Hop.received)
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
                    Text(L10n.Contacts.Contacts.Results.Hop.repeated)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // SNR display - batch mode shows avg with range, single shows plain SNR
                if !hop.isStartNode {
                    if let stats = batchStats {
                        Text(L10n.Contacts.Contacts.Results.Hop.avgSNR(String(format: "%.1f", stats.avg), String(format: "%.1f", stats.min), String(format: "%.1f", stats.max)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel(L10n.Contacts.Contacts.Results.Hop.avgSNRLabel(String(format: "%.1f", stats.avg), String(format: "%.1f", stats.min), String(format: "%.1f", stats.max)))
                    } else {
                        Text(L10n.Contacts.Contacts.Results.Hop.snr(String(format: "%.2f", hop.snr)))
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
