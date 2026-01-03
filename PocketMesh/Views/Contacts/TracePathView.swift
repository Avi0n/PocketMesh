import SwiftUI
import PocketMeshServices

/// View for building and executing network path traces
struct TracePathView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = TracePathViewModel()
    @State private var editMode: EditMode = .inactive

    // Haptic feedback triggers
    @State private var addHapticTrigger = 0
    @State private var dragHapticTrigger = 0
    @State private var copyHapticTrigger = 0

    @State private var showingSavedPaths = false
    @State private var showingSaveDialog = false
    @State private var savePathName = ""
    @State private var saveHapticTrigger = 0

    var body: some View {
        List {
            headerSection
            outboundPathSection
            availableRepeatersSection
            if viewModel.result != nil {
                resultsSection
            }
        }
        .navigationTitle("Trace Path")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 16) {
                    Button("Saved", systemImage: "bookmark") {
                        showingSavedPaths = true
                    }
                    EditButton()
                }
            }
        }
        .environment(\.editMode, $editMode)
        .safeAreaInset(edge: .bottom) {
            runTraceButton
        }
        .sensoryFeedback(.impact(weight: .light), trigger: addHapticTrigger)
        .sensoryFeedback(.impact(weight: .light), trigger: dragHapticTrigger)
        .sensoryFeedback(.success, trigger: copyHapticTrigger)
        .sheet(isPresented: $showingSavedPaths) {
            SavedPathsSheet { selectedPath in
                viewModel.loadSavedPath(selectedPath)
            }
        }
        .sensoryFeedback(.success, trigger: saveHapticTrigger)
        .task {
            viewModel.configure(appState: appState)
            viewModel.startListening()
            if let deviceID = appState.connectedDevice?.id {
                await viewModel.loadContacts(deviceID: deviceID)
            }
        }
        .onDisappear {
            viewModel.stopListening()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        Section {
            Label {
                Text("Build a path through repeaters. Return path is added automatically.")
            } icon: {
                Image(systemName: "info.circle")
                    .foregroundStyle(.blue)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Outbound Path Section

    private var outboundPathSection: some View {
        Section {
            if viewModel.outboundPath.isEmpty {
                Text("Tap a repeater below to start building your path")
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
            } else {
                ForEach(viewModel.outboundPath) { hop in
                    TracePathHopRow(hop: hop)
                }
                .onMove { source, destination in
                    dragHapticTrigger += 1
                    viewModel.moveRepeater(from: source, to: destination)
                }
                .onDelete { indexSet in
                    for index in indexSet.sorted().reversed() {
                        viewModel.removeRepeater(at: index)
                    }
                }
                .animation(.default, value: viewModel.outboundPath.map(\.id))

                // Full path display with copy button
                HStack {
                    Text(viewModel.fullPathString)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Copy Path", systemImage: "doc.on.doc") {
                        copyHapticTrigger += 1
                        viewModel.copyPathToClipboard()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                }

                if viewModel.isRunningSavedPath {
                    Button("Clear Path", systemImage: "xmark.circle", role: .destructive) {
                        viewModel.clearSavedPath()
                    }
                    .foregroundStyle(.red)
                }
            }
        } header: {
            Text("Outbound Path")
        } footer: {
            if !viewModel.outboundPath.isEmpty {
                if editMode == .active {
                    Text("Drag to reorder. Swipe to remove.")
                } else {
                    Text("Tap Edit to reorder or remove hops.")
                }
            }
        }
    }

    // MARK: - Available Repeaters Section

    private var availableRepeatersSection: some View {
        Section {
            if viewModel.availableRepeaters.isEmpty {
                ContentUnavailableView(
                    "No Repeaters Available",
                    systemImage: "antenna.radiowaves.left.and.right.slash",
                    description: Text("Repeaters appear here once they're discovered in your mesh network.")
                )
            } else {
                ForEach(viewModel.availableRepeaters) { repeater in
                    Button {
                        addHapticTrigger += 1
                        viewModel.addRepeater(repeater)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(repeater.displayName)
                                if let firstByte = repeater.publicKey.first {
                                    Text(firstByte.hexString)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "plus.circle")
                                .foregroundStyle(.tint)
                        }
                    }
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Add \(repeater.displayName) to path")
                }
            }
        } header: {
            Text("Available Repeaters")
        }
    }

    // MARK: - Results Section

    private var resultsSection: some View {
        Section {
            if let result = viewModel.result {
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
        } header: {
            Text("Trace Results")
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
                    Text(diff > 0 ? "▲" : "▼")
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

    // MARK: - Run Trace Button

    private var runTraceButton: some View {
        VStack {
            Button {
                Task {
                    await viewModel.runTrace()
                }
            } label: {
                HStack {
                    if viewModel.isRunning {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Run Trace")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .modifier(GlassProminentButtonStyle())
            .disabled(!viewModel.canRunTrace)
        }
        .padding()
    }
}

// MARK: - iOS 26 Liquid Glass Support

/// Applies `.glassProminent` on iOS 26+, falls back to `.borderedProminent` on earlier versions
private struct GlassProminentButtonStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Path Hop Row

/// Row for displaying a hop in the path building section
private struct TracePathHopRow: View {
    let hop: PathHop

    var body: some View {
        VStack(alignment: .leading) {
            if let name = hop.resolvedName {
                Text(name)
                Text(hop.hashByte.hexString)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            } else {
                Text(hop.hashByte.hexString)
                    .font(.body.monospaced())
            }
        }
        .frame(minHeight: 44)
    }
}

// MARK: - Result Hop Row

/// Row for displaying a hop in the trace results
private struct TraceResultHopRow: View {
    let hop: TraceHop

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                // Node identifier
                if hop.isStartNode {
                    Label(hop.resolvedName ?? "My Device", systemImage: "iphone")
                        .font(.body)
                    Text("Started trace")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if hop.isEndNode {
                    Label(hop.resolvedName ?? "My Device", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Received response")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let hashByte = hop.hashByte {
                    HStack {
                        Text(hashByte.hexString)
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

                // SNR display (not for start node - we're the sender)
                if hop.isStartNode {
                    // No SNR for start node
                } else if hop.isEndNode {
                    Text("Return SNR: \(hop.snr, format: .number.precision(.fractionLength(2))) dB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("SNR: \(hop.snr, format: .number.precision(.fractionLength(2))) dB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Signal strength indicator (not for start node - we're the sender)
            if !hop.isStartNode {
                Image(systemName: "cellularbars", variableValue: hop.signalLevel)
                    .foregroundStyle(hop.signalColor)
                    .font(.title2)
            }
        }
        .padding(.vertical, 4)
    }
}
