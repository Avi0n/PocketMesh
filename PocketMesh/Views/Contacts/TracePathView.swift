import SwiftUI
import PocketMeshServices

/// View for building and executing network path traces
struct TracePathView: View {
    @Environment(AppState.self) private var appState
    @State private var viewModel = TracePathViewModel()

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

    @State private var showJumpToPath = false
    @State private var isBottomVisible = true

    var body: some View {
        ScrollViewReader { proxy in
            List {
                headerSection
                availableRepeatersSection
                outboundPathSection
                pathActionsSection
                runTraceSection

                // Invisible sentinel at the bottom to detect scroll position
                Color.clear
                    .frame(height: 1)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
                    .id("bottom")
                    .onAppear {
                        isBottomVisible = true
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showJumpToPath = false
                        }
                    }
                    .onDisappear {
                        isBottomVisible = false
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showJumpToPath = true
                        }
                    }
            }
            .scrollDismissesKeyboard(.interactively)
            .overlay(alignment: .bottom) {
                jumpToPathButton(proxy: proxy)
            }
        }
        .navigationTitle("Trace Path")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Saved", systemImage: "bookmark") {
                    showingSavedPaths = true
                }
            }
        }
        .environment(\.editMode, .constant(.active))
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
            }
        } header: {
            Text("Outbound Path")
        }
    }

    private var pathActionsSection: some View {
        Section {
            if !viewModel.outboundPath.isEmpty {
                Toggle(isOn: $viewModel.autoReturnPath) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Auto Return Path")
                        Text("Mirror outbound path for the return journey")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

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
        } footer: {
            if !viewModel.outboundPath.isEmpty {
                Text("You must be within range of the last repeater to receive a response.")
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

    // MARK: - Run Trace Section

    private var runTraceSection: some View {
        Section {
            HStack {
                Spacer()
                if viewModel.isRunning {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Running Trace...")
                    }
                    .frame(minWidth: 160)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(.regularMaterial, in: .capsule)
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                    }
                    .accessibilityLabel("Running trace, please wait")
                    .accessibilityHint("Trace is in progress")
                } else {
                    Button {
                        Task {
                            await viewModel.runTrace()
                        }
                    } label: {
                        Text("Run Trace")
                            .frame(minWidth: 160)
                            .padding(.vertical, 4)
                    }
                    .liquidGlassProminentButtonStyle()
                    .disabled(!viewModel.canRunTrace)
                    .accessibilityLabel("Run trace")
                    .accessibilityHint("Double tap to trace the path")
                }
                Spacer()
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .id("runTrace")
        }
        .listSectionSeparator(.hidden)
        .alert("Trace Failed", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.clearError() } }
        )) {
            Button("OK") {
                viewModel.clearError()
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }

    // MARK: - Jump to Path Button

    @ViewBuilder
    private func jumpToPathButton(proxy: ScrollViewProxy) -> some View {
        JumpToPathButton(isVisible: showJumpToPath) {
            jumpHapticTrigger += 1
            withAnimation {
                proxy.scrollTo("runTrace", anchor: .bottom)
            }
        }
        .padding(.bottom)
        .sensoryFeedback(.selection, trigger: jumpHapticTrigger)
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

/// Floating pill button to scroll to the Run Trace button
private struct JumpToPathButton: View {
    let isVisible: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Label("Jump to Path", systemImage: "arrow.down")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.accentColor, in: .capsule)
                .liquidGlass(in: .capsule)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .opacity(isVisible ? 1 : 0)
        .scaleEffect(isVisible ? 1 : 0.8)
        .allowsHitTesting(isVisible)
        .animation(.snappy(duration: 0.2), value: isVisible)
        .accessibilityLabel("Jump to Run Trace button")
        .accessibilityHint("Double tap to scroll to the bottom of the path")
        .accessibilityHidden(!isVisible)
    }
}
