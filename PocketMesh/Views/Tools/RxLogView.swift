// PocketMesh/Views/Tools/RxLogView.swift
import SwiftUI
import UIKit
import PocketMeshServices
import MeshCore

struct RxLogView: View {
    @Environment(\.appState) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var viewModel = RxLogViewModel()
    @State private var expandedHashes: Set<String> = []
    @State private var groupDuplicates = false

    var body: some View {
        Group {
            if appState.services?.rxLogService == nil {
                disconnectedState
            } else if viewModel.entries.isEmpty {
                emptyState
            } else {
                entryList
            }
        }
        .navigationTitle(L10n.Tools.Tools.rxLog)
        .toolbar {
            toolbarContent
        }
        .task(id: appState.servicesVersion) {
            guard let service = appState.services?.rxLogService else { return }
            await viewModel.subscribe(to: service)
        }
        .onDisappear {
            viewModel.unsubscribe()
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label(L10n.Tools.Tools.RxLog.listening, systemImage: "antenna.radiowaves.left.and.right")
        } description: {
            Text(L10n.Tools.Tools.RxLog.listeningDescription)
        }
    }

    private var disconnectedState: some View {
        ContentUnavailableView {
            Label(L10n.Tools.Tools.RxLog.notConnected, systemImage: "antenna.radiowaves.left.and.right.slash")
        } description: {
            Text(L10n.Tools.Tools.RxLog.notConnectedDescription)
        }
    }

    // MARK: - Entry List

    private var entryList: some View {
        List {
            Section {
                ForEach(displayEntries, id: \.id) { entry in
                    RxLogRowView(
                        entry: entry,
                        isExpanded: expandedBinding(for: entry.packetHash),
                        groupCount: groupDuplicates ? viewModel.groupCounts[entry.packetHash, default: 1] : 1,
                        localPublicKeyPrefix: appState.connectedDevice?.publicKeyPrefix
                    )
                }
            } header: {
                liveStatusHeader
                    .textCase(nil)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func expandedBinding(for hash: String) -> Binding<Bool> {
        Binding(
            get: { expandedHashes.contains(hash) },
            set: { isExpanded in
                if isExpanded {
                    expandedHashes.insert(hash)
                } else {
                    expandedHashes.remove(hash)
                }
            }
        )
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 16) {
                filterMenu
                overflowMenu
            }
        }
    }

    private var isConnected: Bool {
        appState.services?.rxLogService != nil
    }

    private var liveStatusHeader: some View {
        HStack(spacing: 8) {
            statusPill

            Text(L10n.Tools.Tools.RxLog.packetsCount(viewModel.entries.count))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .modifier(GlassContainerModifier())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isConnected ? L10n.Tools.Tools.RxLog.live : L10n.Tools.Tools.RxLog.offline), \(L10n.Tools.Tools.RxLog.packetsCount(viewModel.entries.count))")
    }

    private var statusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isConnected ? .green : .gray)
                .frame(width: 8, height: 8)
                .modifier(PulseAnimationModifier(isActive: isConnected && !reduceMotion))

            Text(isConnected ? L10n.Tools.Tools.RxLog.live : L10n.Tools.Tools.RxLog.offline)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .modifier(GlassEffectModifier())
    }

    private var filterMenu: some View {
        Menu {
            Section(L10n.Tools.Tools.RxLog.routeType) {
                ForEach(RxLogViewModel.RouteFilter.allCases, id: \.self) { filter in
                    Button {
                        viewModel.setRouteFilter(filter)
                    } label: {
                        HStack {
                            Text(filter.displayName)
                            if viewModel.routeFilter == filter {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }

            Section(L10n.Tools.Tools.RxLog.decryptStatus) {
                ForEach(RxLogViewModel.DecryptFilter.allCases, id: \.self) { filter in
                    Button {
                        viewModel.setDecryptFilter(filter)
                    } label: {
                        HStack {
                            Text(filter.displayName)
                            if viewModel.decryptFilter == filter {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            Label(L10n.Tools.Tools.RxLog.filter, systemImage: viewModel.routeFilter == .all && viewModel.decryptFilter == .all
                ? "line.3.horizontal.decrease.circle"
                : "line.3.horizontal.decrease.circle.fill")
        }
        .modifier(GlassButtonModifier())
    }

    @State private var showClearConfirmation = false

    private var overflowMenu: some View {
        Menu {
            Button {
                groupDuplicates.toggle()
            } label: {
                HStack {
                    Text(L10n.Tools.Tools.RxLog.groupDuplicates)
                    if groupDuplicates { Image(systemName: "checkmark") }
                }
            }

            Divider()

            Button(role: .destructive) {
                showClearConfirmation = true
            } label: {
                Label(L10n.Tools.Tools.RxLog.deleteLogs, systemImage: "trash")
            }
        } label: {
            Label(L10n.Tools.Tools.RxLog.more, systemImage: "ellipsis.circle")
        }
        .modifier(GlassButtonModifier())
        .confirmationDialog(L10n.Tools.Tools.RxLog.deleteConfirmation, isPresented: $showClearConfirmation, titleVisibility: .visible) {
            Button(L10n.Tools.Tools.RxLog.delete, role: .destructive) {
                clearLog()
            }
        }
    }

    // MARK: - Helpers

    private var displayEntries: [RxLogEntryDTO] {
        let filtered = viewModel.filteredEntries
        if groupDuplicates {
            var seen = Set<String>()
            return filtered.filter { entry in
                if seen.contains(entry.packetHash) {
                    return false
                }
                seen.insert(entry.packetHash)
                return true
            }
        }
        return filtered
    }

    private func clearLog() {
        Task {
            await viewModel.clearLog()
        }
        expandedHashes.removeAll()
    }
}

// MARK: - Row View

struct RxLogRowView: View {
    let entry: RxLogEntryDTO
    @Binding var isExpanded: Bool
    let groupCount: Int
    let localPublicKeyPrefix: Data?

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            expandedContent
        } label: {
            collapsedContent
        }
        .sensoryFeedback(.selection, trigger: isExpanded)
    }

    // MARK: - Collapsed Content (3 lines)

    private var collapsedContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Line 1: Route type, time, signal bars
            HStack {
                Text(entry.routeTypeSimple)
                    .font(.caption.bold())
                    .foregroundStyle(entry.isFlood ? .green : .blue)

                Text(entry.receivedAt, format: .dateTime.hour().minute().second())
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                Spacer()

                if entry.snr != nil {
                    Image(systemName: "cellularbars", variableValue: entry.snrLevel)
                        .foregroundStyle(signalColor)
                        .accessibilityLabel(L10n.Tools.Tools.RxLog.signalStrength(entry.snrQualityLabel))
                }
            }

            // Line 2: Path visualization + From/To for direct text messages
            HStack(spacing: 4) {
                Text(pathDisplayString)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Direct message payload format: [dest: 1B] [src: 1B] [MAC + encrypted]
                if isDirectTextMessage, entry.packetPayload.count >= 2 {
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text("<\(String(format: "%02x", entry.packetPayload[1]))> → <\(String(format: "%02x", entry.packetPayload[0]))>")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)

            // Line 3: Message preview or packet info, SNR, duplicate count
            HStack {
                if let text = entry.decodedText {
                    Text("\"\(text)\"")
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                } else {
                    let versionSuffix = entry.payloadVersion > 0 ? " v\(entry.payloadVersion)" : ""
                    Text("\(entry.payloadType.displayName)\(versionSuffix) · \(entry.rawPayload.count) \(L10n.Tools.Tools.RxLog.bytes)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let snrString = entry.snrDisplayString {
                    Text(snrString)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }

                if groupCount > 1 {
                    Text("×\(groupCount)")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                        .accessibilityLabel(L10n.Tools.Tools.RxLog.receivedTimes(groupCount))
                }
            }
        }
    }

    // MARK: - Path Display

    private var pathDisplayString: String {
        if entry.pathLength == 0 {
            return L10n.Tools.Tools.RxLog.direct
        }

        var parts: [String] = []
        for byte in entry.pathNodes {
            let hex = String(format: "%02X", byte)
            // Check if this is the local device
            if let prefix = localPublicKeyPrefix, prefix.first == byte {
                parts.append("YOU")
            } else {
                parts.append(hex)
            }
        }

        // Truncate long paths: show first 3 + ellipsis + last 3
        if parts.count > 6 {
            let first = parts.prefix(3).joined(separator: " → ")
            let last = parts.suffix(3).joined(separator: " → ")
            return "\(first) → … → \(last)"
        }

        return parts.joined(separator: " → ")
    }

    private var pathDetailString: String {
        if entry.pathLength == 0 {
            return L10n.Tools.Tools.RxLog.direct
        }

        let hopCount = Int(entry.pathLength)
        let hopLabel = hopCount == 1 ? L10n.Tools.Tools.RxLog.hopSingular : L10n.Tools.Tools.RxLog.hopPlural
        let nodes = entry.pathNodes.map { String(format: "%02X", $0) }.joined(separator: ", ")
        return "\(hopCount) \(hopLabel) [\(nodes)]"
    }

    private var isDirectTextMessage: Bool {
        (entry.routeType == .direct || entry.routeType == .tcDirect) && entry.payloadType == .textMessage
    }

    private var signalColor: Color {
        guard let snr = entry.snr else { return .secondary }
        if snr > 5 { return .green }
        if snr > 0 { return .yellow }
        return .red
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let rssi = entry.rssi {
                DetailRow(label: L10n.Tools.Tools.RxLog.rssiLabel, value: "\(rssi) dBm")
            }
            if let snr = entry.snr {
                DetailRow(label: L10n.Tools.Tools.RxLog.snrLabel, value: snr.formatted(.number.precision(.fractionLength(1))) + " dB")
            }

            DetailRow(label: L10n.Tools.Tools.RxLog.typeLabel, value: entry.payloadType.displayName)
            DetailRow(label: L10n.Tools.Tools.RxLog.sizeLabel, value: "\(entry.rawPayload.count) \(L10n.Tools.Tools.RxLog.bytes)")
            DetailRow(label: L10n.Tools.Tools.RxLog.pathLabel, value: pathDetailString)
            DetailRow(label: L10n.Tools.Tools.RxLog.hashLabel, value: entry.packetHash, truncate: true)

            // Direct message: show sender and recipient
            // Payload format: [dest: 1B] [src: 1B] [MAC + encrypted content]
            if isDirectTextMessage, entry.packetPayload.count >= 2 {
                let destByte = entry.packetPayload[0]  // recipient
                let srcByte = entry.packetPayload[1]   // sender
                DetailRow(label: L10n.Tools.Tools.RxLog.fromLabel, value: "<\(String(format: "%02x", srcByte))>")
                DetailRow(label: L10n.Tools.Tools.RxLog.toLabel, value: "<\(String(format: "%02x", destByte))>")
            }

            // Channel message: show channel info
            if entry.decryptStatus == .success {
                if let channelHashByte = entry.packetPayload.first {
                    DetailRow(label: L10n.Tools.Tools.RxLog.channelHashLabel, value: String(format: "%02x", channelHashByte))
                }
                if let channelName = entry.channelName {
                    DetailRow(label: L10n.Tools.Tools.RxLog.channelNameLabel, value: channelName)
                }
                if let text = entry.decodedText {
                    HStack(alignment: .top) {
                        Text(L10n.Tools.Tools.RxLog.textLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(text)
                            .font(.caption)
                    }
                }
            }

            RawPayloadSection(payload: entry.rawPayload)
        }
    }
}

// MARK: - Detail Row

private struct DetailRow: View {
    let label: String
    let value: String
    var truncate: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(truncate ? .middle : .tail)
        }
    }
}

// MARK: - Raw Payload Section

private struct RawPayloadSection: View {
    let payload: Data

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(L10n.Tools.Tools.RxLog.rawPayload)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Spacer()

                Button(L10n.Tools.Tools.RxLog.copy, systemImage: copied ? "checkmark" : "doc.on.doc", action: copyToClipboard)
                    .font(.caption)
                    .foregroundStyle(copied ? .green : .secondary)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .sensoryFeedback(.success, trigger: copied) { _, newValue in newValue }
            }

            Text(hexString)
                .font(.caption2.monospaced())
                .lineLimit(3)
                .truncationMode(.tail)
        }
    }

    private var hexString: String {
        payload.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private func copyToClipboard() {
        UIPasteboard.general.string = hexString
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }
}

// MARK: - Glass Effect Modifiers

private struct GlassButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glass)
        } else {
            content
        }
    }
}

private struct GlassEffectModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect()
        } else {
            content.background(.ultraThinMaterial, in: .capsule)
        }
    }
}

private struct GlassContainerModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer { content }
        } else {
            content
        }
    }
}

// MARK: - Pulse Animation

private struct PulseAnimationModifier: ViewModifier {
    let isActive: Bool

    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isActive && isPulsing ? 0.4 : 1.0)
            .animation(
                isActive ? .easeInOut(duration: 1.0).repeatForever(autoreverses: true) : .default,
                value: isPulsing
            )
            .onAppear {
                if isActive {
                    isPulsing = true
                }
            }
            .onChange(of: isActive) { _, newValue in
                isPulsing = newValue
            }
    }
}

#Preview {
    NavigationStack {
        RxLogView()
    }
    .environment(\.appState, AppState())
}
