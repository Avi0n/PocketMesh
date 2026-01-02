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

    // Row feedback
    @State private var recentlyAddedRepeaterID: UUID?

    @State private var showingSavedPaths = false
    @State private var presentedResult: TraceResult?
    @State private var showingClearConfirmation = false

    var body: some View {
        List {
            headerSection
            availableRepeatersSection
            outboundPathSection
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
        .sensoryFeedback(.error, trigger: viewModel.errorHapticTrigger)
        .sheet(isPresented: $showingSavedPaths) {
            SavedPathsSheet { selectedPath in
                viewModel.loadSavedPath(selectedPath)
            }
        }
        .onChange(of: viewModel.resultID) { _, newID in
            guard newID != nil else { return }
            if let result = viewModel.result, result.success {
                presentedResult = result
            }
        }
        .sheet(item: $presentedResult) { result in
            TraceResultsSheet(result: result, viewModel: viewModel)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
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
        .task(id: recentlyAddedRepeaterID) {
            guard recentlyAddedRepeaterID != nil else { return }
            try? await Task.sleep(for: .seconds(1))
            if !Task.isCancelled {
                recentlyAddedRepeaterID = nil
            }
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
                Text("Tap a repeater above to start building your path")
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

                Button("Clear Path", systemImage: "trash", role: .destructive) {
                    showingClearConfirmation = true
                }
                .foregroundStyle(.red)
                .confirmationDialog(
                    "Clear Path",
                    isPresented: $showingClearConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Clear Path", role: .destructive) {
                        viewModel.clearPath()
                    }
                } message: {
                    Text("Remove all repeaters from the path?")
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
                        recentlyAddedRepeaterID = repeater.id
                        addHapticTrigger += 1
                        viewModel.addRepeater(repeater)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(repeater.displayName)
                                Text(repeater.publicKey.hexString())
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Image(systemName: recentlyAddedRepeaterID == repeater.id ? "checkmark.circle.fill" : "plus.circle")
                                .foregroundStyle(recentlyAddedRepeaterID == repeater.id ? Color.green : Color.accentColor)
                                .contentTransition(.symbolEffect(.replace))
                        }
                    }
                    .id(repeater.id)
                    .foregroundStyle(.primary)
                    .accessibilityLabel("Add \(repeater.displayName) to path")
                }
            }
        } header: {
            Text("Available Repeaters")
        }
    }

    // MARK: - Run Trace Button

    private var runTraceButton: some View {
        VStack(spacing: 8) {
            // Error message (if present)
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            Button {
                viewModel.clearError()  // Clear error before retry
                Task {
                    await viewModel.runTrace()
                }
            } label: {
                HStack {
                    if viewModel.isRunning {
                        ProgressView()
                            .tint(.white)
                    } else {
                        // Show "Retry" if there's an error, otherwise "Run Trace"
                        Text(viewModel.errorMessage != nil ? "Retry" : "Run Trace")
                    }
                }
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
