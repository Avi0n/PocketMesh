import SwiftUI
import UIKit
import PocketMeshServices

/// List-based view for building trace paths
struct TracePathListView: View {
    @Environment(\.appState) private var appState
    @Bindable var viewModel: TracePathViewModel

    @Binding var addHapticTrigger: Int
    @Binding var dragHapticTrigger: Int
    @Binding var copyHapticTrigger: Int
    @Binding var recentlyAddedRepeaterID: UUID?
    @Binding var showingClearConfirmation: Bool
    @Binding var presentedResult: TraceResult?
    @Binding var showJumpToPath: Bool

    @State private var isRepeatersExpanded = false
    @State private var codeInput = ""
    @State private var codeInputError: String?
    @State private var pastedSuccessfully = false
    @AppStorage("tracePathShowOnlyFavorites") private var showOnlyFavorites = false

    private var filteredRepeaters: [ContactDTO] {
        showOnlyFavorites
            ? viewModel.availableRepeaters.filter(\.isFavorite)
            : viewModel.availableRepeaters
    }

    var body: some View {
        List {
            codeInputSection
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

    // MARK: - Code Input Section

    private var codeInputSection: some View {
        Section {
            HStack {
                TextField(L10n.Contacts.Contacts.Trace.List.codePlaceholder, text: $codeInput)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .onSubmit {
                        processCodeInput()
                    }

                Button(L10n.Contacts.Contacts.Trace.List.paste, systemImage: "doc.on.clipboard") {
                    pasteAndProcess()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
            }
        } footer: {
            if let error = codeInputError {
                Text(error)
                    .foregroundStyle(.red)
            } else if !pastedSuccessfully {
                Text(L10n.Contacts.Contacts.Trace.List.codeFooter)
            }
        }
    }

    private func processCodeInput() {
        guard !codeInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }

        pastedSuccessfully = false
        let result = viewModel.addRepeatersFromCodes(codeInput)
        codeInputError = result.errorMessage

        if !result.added.isEmpty {
            addHapticTrigger += 1
        }
    }

    private func pasteAndProcess() {
        guard let pasteboardString = UIPasteboard.general.string,
              !pasteboardString.isEmpty else { return }

        codeInput = pasteboardString
        let result = viewModel.addRepeatersFromCodes(codeInput)
        codeInputError = result.errorMessage
        pastedSuccessfully = !result.added.isEmpty

        if !result.added.isEmpty {
            addHapticTrigger += 1
        }
    }

    // MARK: - Repeaters Section

    private var availableRepeatersSection: some View {
        Section {
            DisclosureGroup(isExpanded: $isRepeatersExpanded) {
                Toggle(L10n.Contacts.Contacts.Trace.List.favoritesOnly, isOn: $showOnlyFavorites)

                if filteredRepeaters.isEmpty {
                    if showOnlyFavorites {
                        ContentUnavailableView(
                            L10n.Contacts.Contacts.Trace.List.NoFavorites.title,
                            systemImage: "star.slash",
                            description: Text(L10n.Contacts.Contacts.Trace.List.NoFavorites.description)
                        )
                    } else {
                        ContentUnavailableView(
                            L10n.Contacts.Contacts.PathEdit.NoRepeaters.title,
                            systemImage: "antenna.radiowaves.left.and.right.slash",
                            description: Text(L10n.Contacts.Contacts.PathEdit.NoRepeaters.description)
                        )
                    }
                } else {
                    ForEach(filteredRepeaters) { repeater in
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
                        .accessibilityLabel(L10n.Contacts.Contacts.PathEdit.addToPath(repeater.displayName))
                    }
                }
            } label: {
                HStack {
                    Text(L10n.Contacts.Contacts.Trace.List.repeaters)
                    Spacer()
                    Text("\(filteredRepeaters.count)")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Outbound Path Section

    private var outboundPathSection: some View {
        Section {
            if viewModel.outboundPath.isEmpty {
                Text(L10n.Contacts.Contacts.Trace.List.emptyPath)
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
            } else {
                ForEach(Array(viewModel.outboundPath.enumerated()), id: \.element.id) { index, hop in
                    TracePathHopRow(hop: hop, hopNumber: index + 1)
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
            Text(L10n.Contacts.Contacts.Trace.List.outboundPath)
        }
    }

    // MARK: - Path Actions Section

    private var pathActionsSection: some View {
        Section {
            if !viewModel.outboundPath.isEmpty {
                Toggle(isOn: $viewModel.autoReturnPath) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.Contacts.Contacts.Trace.List.autoReturn)
                        Text(L10n.Contacts.Contacts.Trace.List.autoReturnDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle(isOn: $viewModel.batchEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.Contacts.Contacts.Trace.List.batchTrace)
                        Text(L10n.Contacts.Contacts.Trace.List.batchTraceDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if viewModel.batchEnabled {
                    HStack(spacing: 12) {
                        Text(L10n.Contacts.Contacts.Trace.List.traces)
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

                    Button(L10n.Contacts.Contacts.Trace.List.copyPath, systemImage: "doc.on.doc") {
                        copyHapticTrigger += 1
                        viewModel.copyPathToClipboard()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                }

                Button(L10n.Contacts.Contacts.Trace.clearPath, systemImage: "trash", role: .destructive) {
                    showingClearConfirmation = true
                }
                .foregroundStyle(.red)
            }
        } footer: {
            if !viewModel.outboundPath.isEmpty {
                Text(L10n.Contacts.Contacts.Trace.List.rangeWarning)
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
                            Text(L10n.Contacts.Contacts.Trace.List.runningBatch(viewModel.currentTraceIndex, viewModel.batchSize))
                        } else {
                            Text(L10n.Contacts.Contacts.Trace.List.runningTrace)
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
                    .accessibilityLabel(viewModel.batchEnabled
                        ? L10n.Contacts.Contacts.Trace.List.runningBatchLabel(viewModel.currentTraceIndex, viewModel.batchSize)
                        : L10n.Contacts.Contacts.Trace.List.runningLabel)
                    .accessibilityHint(L10n.Contacts.Contacts.Trace.List.runningHint)
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
                        Text(L10n.Contacts.Contacts.Trace.List.runTrace)
                            .frame(minWidth: 160)
                            .padding(.vertical, 4)
                    }
                    .liquidGlassProminentButtonStyle()
                    .radioDisabled(for: appState.connectionState, or: !viewModel.canRunTraceWhenConnected)
                    .accessibilityLabel(L10n.Contacts.Contacts.Trace.List.runTraceLabel)
                    .accessibilityHint(viewModel.batchEnabled
                        ? L10n.Contacts.Contacts.Trace.List.batchHint(viewModel.batchSize)
                        : L10n.Contacts.Contacts.Trace.List.singleHint)
                }
                Spacer()
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .id("runTrace")
            .onAppear {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showJumpToPath = false
                }
            }
            .onDisappear {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showJumpToPath = true
                }
            }
        }
        .listSectionSeparator(.hidden)
    }
}

// MARK: - Path Hop Row

struct TracePathHopRow: View {
    let hop: PathHop
    let hopNumber: Int

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.Contacts.Contacts.Trace.List.hopLabel(hopNumber, hop.resolvedName ?? hop.hashByte.hexString))
        .accessibilityHint(L10n.Contacts.Contacts.Trace.List.hopHint)
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
