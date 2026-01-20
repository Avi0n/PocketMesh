import SwiftUI
import PocketMeshServices

/// List-based view for building trace paths
struct TracePathListView: View {
    @Bindable var viewModel: TracePathViewModel

    @Binding var addHapticTrigger: Int
    @Binding var dragHapticTrigger: Int
    @Binding var copyHapticTrigger: Int
    @Binding var recentlyAddedRepeaterID: UUID?
    @Binding var showingClearConfirmation: Bool
    @Binding var presentedResult: TraceResult?

    var body: some View {
        List {
            headerSection
            availableRepeatersSection
            outboundPathSection
            pathActionsSection
            runTraceSection

            Color.clear
                .frame(height: 1)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets())
                .id("bottom")
        }
        .environment(\.editMode, .constant(.active))
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

    // MARK: - Path Actions Section

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

                Toggle(isOn: $viewModel.batchEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Batch Trace")
                        Text("Run multiple traces and average the results")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if viewModel.batchEnabled {
                    HStack(spacing: 12) {
                        Text("Traces:")
                            .foregroundStyle(.secondary)
                        Spacer()
                        BatchSizeChip(size: 3, selectedSize: $viewModel.batchSize)
                        BatchSizeChip(size: 5, selectedSize: $viewModel.batchSize)
                        BatchSizeChip(size: 10, selectedSize: $viewModel.batchSize)
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
            }
        } footer: {
            if !viewModel.outboundPath.isEmpty {
                Text("You must be within range of the last repeater to receive a response.")
            }
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
                        if viewModel.batchEnabled {
                            Text("Running Trace \(viewModel.currentTraceIndex) of \(viewModel.batchSize)...")
                        } else {
                            Text("Running Trace...")
                        }
                    }
                    .frame(minWidth: 160)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(.regularMaterial, in: .capsule)
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                    }
                } else {
                    Button {
                        Task {
                            if viewModel.batchEnabled {
                                await viewModel.runBatchTrace()
                            } else {
                                await viewModel.runTrace()
                            }
                        }
                    } label: {
                        Text("Run Trace")
                            .frame(minWidth: 160)
                            .padding(.vertical, 4)
                    }
                    .liquidGlassProminentButtonStyle()
                    .disabled(!viewModel.canRunTrace)
                }
                Spacer()
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .id("runTrace")
        }
        .listSectionSeparator(.hidden)
    }
}

// MARK: - Path Hop Row

struct TracePathHopRow: View {
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

// MARK: - Batch Size Chip

struct BatchSizeChip: View {
    let size: Int
    @Binding var selectedSize: Int

    private var isSelected: Bool { selectedSize == size }

    var body: some View {
        Button {
            selectedSize = size
        } label: {
            Text("\(size)×")
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), in: .capsule)
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}
