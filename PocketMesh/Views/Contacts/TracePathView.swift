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
            ToolbarItem(placement: .confirmationAction) {
                EditButton()
            }
        }
        .environment(\.editMode, $editMode)
        .safeAreaInset(edge: .bottom) {
            runTraceButton
        }
        .sensoryFeedback(.impact(weight: .light), trigger: addHapticTrigger)
        .sensoryFeedback(.impact(weight: .light), trigger: dragHapticTrigger)
        .sensoryFeedback(.success, trigger: copyHapticTrigger)
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
                                Text(String(format: "%02X", repeater.publicKey[0]))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
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

                    // Duration row
                    HStack {
                        Text("Round Trip")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(result.durationMs) ms")
                            .font(.body.monospacedDigit())
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
                Text(String(format: "%02X", hop.hashByte))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            } else {
                Text(String(format: "%02X", hop.hashByte))
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
                        Text(String(format: "%02X", hashByte))
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

                // SNR display (not for end node)
                if !hop.isEndNode {
                    Text("SNR: \(hop.snr, format: .number.precision(.fractionLength(2))) dB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Duration shown below")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Signal strength indicator (not for end node)
            if !hop.isEndNode {
                Image(systemName: "cellularbars", variableValue: hop.signalLevel)
                    .foregroundStyle(hop.signalColor)
                    .font(.title2)
            }
        }
        .padding(.vertical, 4)
    }
}
