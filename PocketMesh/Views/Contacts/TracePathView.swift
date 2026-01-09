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
    @State private var jumpHapticTrigger = 0

    // Row feedback
    @State private var recentlyAddedRepeaterID: UUID?

    @State private var showingSavedPaths = false
    @State private var presentedResult: TraceResult?
    @State private var showingClearConfirmation = false

    // Jump to path button visibility (implemented in Task 3)
    @State private var showJumpToPath = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Form {
                    headerSection
                    availableRepeatersSection
                    outboundPathSection
                }
                .scrollDisabled(true)
                .containerRelativeFrame(.vertical) { height, _ in
                    max(height * 0.5, 300)
                }

                runTraceButton
                    .id("runTraceButton")
                    .padding(.horizontal)
                    .padding(.bottom)
                    .safeAreaPadding(.bottom)
            }
            .scrollDismissesKeyboard(.interactively)
            .overlay(alignment: .bottom) {
                jumpToPathButton(proxy: proxy)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                // Button is off-screen when visible bottom edge is above content height minus button area
                let visibleBottom = geometry.contentOffset.y + geometry.containerSize.height
                let buttonTop = geometry.contentSize.height - 120
                return visibleBottom < buttonTop
            } action: { _, isButtonOffScreen in
                withAnimation(.easeInOut(duration: 0.2)) {
                    showJumpToPath = isButtonOffScreen && !viewModel.outboundPath.isEmpty
                }
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
                Text("Tap repeaters below to build your path.")
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
            Toggle(isOn: $viewModel.autoReturnPath) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto Return Path")
                    Text("Mirror outbound path for the return journey")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !viewModel.autoReturnPath {
                Label {
                    Text("You must be within range of the last repeater to receive a response.")
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.blue)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }

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
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            Button {
                viewModel.clearError()
                Task {
                    await viewModel.runTrace()
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isRunning {
                        ProgressView()
                            .controlSize(.small)
                        Text("Running Trace...")
                    } else {
                        Text(viewModel.errorMessage != nil ? "Retry" : "Run Trace")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .modifier(GlassButtonStyle(isRunning: viewModel.isRunning))
            .disabled(!viewModel.canRunTrace)
            .accessibilityLabel(viewModel.isRunning ? "Running trace, please wait" : "Run trace")
            .accessibilityHint(viewModel.isRunning ? "Trace is in progress" : "Double tap to trace the path")
        }
    }

    // MARK: - Jump to Path Button

    @ViewBuilder
    private func jumpToPathButton(proxy: ScrollViewProxy) -> some View {
        JumpToPathButton(isVisible: showJumpToPath) {
            jumpHapticTrigger += 1
            withAnimation {
                proxy.scrollTo("runTraceButton", anchor: .bottom)
            }
        }
        .padding(.bottom)
        .sensoryFeedback(.selection, trigger: jumpHapticTrigger)
    }
}

// MARK: - iOS 26 Liquid Glass Support

/// Applies `.glassProminent` on iOS 26+, falls back to `.borderedProminent` on earlier versions
private struct GlassButtonStyle: ViewModifier {
    var isRunning: Bool = false

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glassProminent)
                .tint(isRunning ? .gray : nil)
        } else {
            content
                .buttonStyle(.borderedProminent)
                .tint(isRunning ? .gray : nil)
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

// MARK: - Jump to Path Button

/// Floating button to scroll to the Run Trace button
private struct JumpToPathButton: View {
    let isVisible: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(systemName: "chevron.down.circle.fill")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: .circle)
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.5)
        .animation(.snappy(duration: 0.2), value: isVisible)
        .accessibilityLabel("Jump to Run Trace button")
        .accessibilityHint("Double tap to scroll to the bottom of the path")
        .accessibilityHidden(!isVisible)
    }
}
