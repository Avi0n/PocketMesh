import PocketMeshServices
import SwiftUI

/// Display view for repeater stats, telemetry, and neighbors
struct RepeaterStatusView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss

    let session: RemoteNodeSessionDTO
    @State private var viewModel = RepeaterStatusViewModel()
    @State private var contacts: [ContactDTO] = []

    var body: some View {
        NavigationStack {
            List {
                headerSection
                statusSection
                telemetrySection
                neighborsSection
                batteryCurveSection
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(L10n.RemoteNodes.RemoteNodes.Status.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.RemoteNodes.RemoteNodes.done) { dismiss() }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .radioDisabled(
                        for: appState.connectionState,
                        or: viewModel.isLoadingStatus || viewModel.isLoadingNeighbors || viewModel.isLoadingTelemetry
                    )
                }

                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L10n.RemoteNodes.RemoteNodes.done) {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil,
                            from: nil,
                            for: nil
                        )
                    }
                }
            }
            .task {
                viewModel.configure(appState: appState)
                await viewModel.registerHandlers(appState: appState)

                // Request Status first (includes clock query)
                await viewModel.requestStatus(for: session)
                // Note: Telemetry and Neighbors are NOT auto-loaded - user must expand the section

                // Pre-load OCV settings and contacts for neighbor matching
                if let deviceID = appState.connectedDevice?.id {
                    await viewModel.loadOCVSettings(publicKey: session.publicKey, deviceID: deviceID)
                    if let dataStore = appState.services?.dataStore {
                        contacts = (try? await dataStore.fetchContacts(deviceID: deviceID)) ?? []
                    }
                }
            }
            .refreshable {
                await viewModel.requestStatus(for: session)
                // Refresh telemetry only if already loaded
                if viewModel.telemetryLoaded {
                    await viewModel.requestTelemetry(for: session)
                }
                // Refresh neighbors only if already loaded
                if viewModel.neighborsLoaded {
                    await viewModel.requestNeighbors(for: session)
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Header Section

    private var headerSection: some View {
        Section {
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    NodeAvatar(publicKey: session.publicKey, role: .repeater, size: 60)

                    Text(session.name)
                        .font(.headline)
                }
                Spacer()
            }
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        Section(L10n.RemoteNodes.RemoteNodes.Status.statusSection) {
            if viewModel.isLoadingStatus && viewModel.status == nil {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            } else if let errorMessage = viewModel.errorMessage, viewModel.status == nil {
                Text(errorMessage)
                    .foregroundStyle(.red)
            } else {
                statusRows

                if let timestamp = viewModel.previousSnapshotTimestamp {
                    Text(timestamp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                NavigationLink {
                    NodeStatusHistoryView(fetchSnapshots: viewModel.fetchHistory)
                } label: {
                    Text(L10n.RemoteNodes.RemoteNodes.History.title)
                }
            }
        }
    }

    @ViewBuilder
    private var statusRows: some View {
        MetricRow(
            label: L10n.RemoteNodes.RemoteNodes.Status.battery,
            value: viewModel.batteryDisplay,
            delta: viewModel.batteryDeltaMV.map { Double($0) / 1000.0 },
            higherIsBetter: true, unit: " V", fractionDigits: 2
        )

        LabeledContent(L10n.RemoteNodes.RemoteNodes.Status.uptime, value: viewModel.uptimeDisplay)

        MetricRow(
            label: L10n.RemoteNodes.RemoteNodes.Status.lastRssi,
            value: viewModel.lastRSSIDisplay,
            delta: viewModel.rssiDelta.map(Double.init),
            higherIsBetter: true, unit: " dBm", fractionDigits: 0
        )

        MetricRow(
            label: L10n.RemoteNodes.RemoteNodes.Status.lastSnr,
            value: viewModel.lastSNRDisplay,
            delta: viewModel.snrDelta,
            higherIsBetter: true, unit: " dB", fractionDigits: 1
        )

        MetricRow(
            label: L10n.RemoteNodes.RemoteNodes.Status.noiseFloor,
            value: viewModel.noiseFloorDisplay,
            delta: viewModel.noiseFloorDelta.map(Double.init),
            higherIsBetter: false, unit: " dBm", fractionDigits: 0
        )

        LabeledContent(L10n.RemoteNodes.RemoteNodes.Status.packetsSent, value: viewModel.packetsSentDisplay)
        LabeledContent(L10n.RemoteNodes.RemoteNodes.Status.packetsReceived, value: viewModel.packetsReceivedDisplay)

        if let receiveErrors = viewModel.receiveErrorsDisplay {
            LabeledContent(L10n.RemoteNodes.RemoteNodes.Status.receiveErrors, value: receiveErrors)
        }
    }

    // MARK: - Neighbors Section

    private var neighborsSection: some View {
        Section {
            DisclosureGroup(isExpanded: $viewModel.neighborsExpanded) {
                if viewModel.isLoadingNeighbors {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if viewModel.neighbors.isEmpty {
                    Text(L10n.RemoteNodes.RemoteNodes.Status.noNeighbors)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.neighbors, id: \.publicKeyPrefix) { neighbor in
                        let contact = contacts.first { $0.publicKeyPrefix.starts(with: neighbor.publicKeyPrefix) }
                        NavigationLink {
                            NeighborSNRChartView(
                                name: contact?.displayName ?? L10n.RemoteNodes.RemoteNodes.Status.unknown,
                                neighborPrefix: neighbor.publicKeyPrefix,
                                fetchSnapshots: viewModel.fetchHistory
                            )
                        } label: {
                            NeighborRow(
                                neighbor: neighbor,
                                contact: contact,
                                previousNeighbor: viewModel.previousSnapshot?.neighborSnapshots?.first {
                                    $0.publicKeyPrefix == neighbor.publicKeyPrefix
                                },
                                hasPreviousSnapshot: viewModel.previousSnapshot?.neighborSnapshots != nil
                            )
                        }
                    }

                    if let previousNeighbors = viewModel.previousSnapshot?.neighborSnapshots {
                        let currentPrefixes = Set(viewModel.neighbors.map(\.publicKeyPrefix))
                        let disappeared = previousNeighbors.filter { !currentPrefixes.contains($0.publicKeyPrefix) }
                        ForEach(disappeared, id: \.publicKeyPrefix) { old in
                            DisappearedNeighborRow(
                                neighbor: old,
                                contact: contacts.first { $0.publicKeyPrefix.starts(with: old.publicKeyPrefix) }
                            )
                        }
                    }
                }
            } label: {
                HStack {
                    Text(L10n.RemoteNodes.RemoteNodes.Status.neighbors)
                    Spacer()
                    if viewModel.neighborsLoaded {
                        Text("\(viewModel.neighbors.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onChange(of: viewModel.neighborsExpanded) { _, isExpanded in
                if isExpanded && !viewModel.neighborsLoaded {
                    Task {
                        await viewModel.requestNeighbors(for: session)
                    }
                }
            }
        } footer: {
            Text(L10n.RemoteNodes.RemoteNodes.Status.neighborsFooter)
        }
    }

    // MARK: - Battery Curve Section

    private var batteryCurveSection: some View {
        Section {
            DisclosureGroup(isExpanded: $viewModel.isBatteryCurveExpanded) {
                BatteryCurveSection(
                    availablePresets: OCVPreset.repeaterPresets,
                    headerText: "",
                    footerText: "",
                    selectedPreset: $viewModel.selectedOCVPreset,
                    voltageValues: $viewModel.ocvValues,
                    onSave: viewModel.saveOCVSettings,
                    isDisabled: appState.connectionState != .ready
                )

                if let error = viewModel.ocvError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } label: {
                Text(L10n.RemoteNodes.RemoteNodes.Status.batteryCurve)
            }
            .onChange(of: viewModel.isBatteryCurveExpanded) { _, isExpanded in
                if isExpanded, let deviceID = appState.connectedDevice?.id {
                    Task {
                        await viewModel.loadOCVSettings(publicKey: session.publicKey, deviceID: deviceID)
                    }
                }
            }
        } footer: {
            Text(L10n.RemoteNodes.RemoteNodes.Status.batteryCurveFooter)
        }
    }

    // MARK: - Telemetry Section

    private var telemetrySection: some View {
        Section {
            DisclosureGroup(isExpanded: $viewModel.telemetryExpanded) {
                if viewModel.isLoadingTelemetry {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if viewModel.telemetry != nil {
                    // Use cached data points to avoid repeated LPP decoding during view updates
                    if viewModel.cachedDataPoints.isEmpty {
                        Text(L10n.RemoteNodes.RemoteNodes.Status.noSensorData)
                            .foregroundStyle(.secondary)
                    } else if viewModel.hasMultipleChannels {
                        ForEach(viewModel.groupedDataPoints, id: \.channel) { group in
                            Section {
                                ForEach(group.dataPoints, id: \.self) { dataPoint in
                                    TelemetryRow(dataPoint: dataPoint, ocvArray: viewModel.ocvValues)
                                }
                            } header: {
                                Text(L10n.RemoteNodes.RemoteNodes.Status.channel(Int(group.channel)))
                                    .fontWeight(.semibold)
                            }
                        }
                    } else {
                        ForEach(viewModel.cachedDataPoints, id: \.self) { dataPoint in
                            TelemetryRow(dataPoint: dataPoint, ocvArray: viewModel.ocvValues)
                        }
                    }

                    NavigationLink {
                        TelemetryHistoryView(fetchSnapshots: viewModel.fetchHistory)
                    } label: {
                        Text(L10n.RemoteNodes.RemoteNodes.History.title)
                    }
                } else {
                    Text(L10n.RemoteNodes.RemoteNodes.Status.noTelemetryData)
                        .foregroundStyle(.secondary)
                }
            } label: {
                Text(L10n.RemoteNodes.RemoteNodes.Status.telemetry)
            }
            .onChange(of: viewModel.telemetryExpanded) { _, isExpanded in
                if isExpanded && !viewModel.telemetryLoaded {
                    Task {
                        await viewModel.requestTelemetry(for: session)
                    }
                }
            }
        } footer: {
            Text(L10n.RemoteNodes.RemoteNodes.Status.telemetryFooter)
        }
    }

    // MARK: - Actions

    private func refresh() {
        Task {
            await viewModel.requestStatus(for: session)
            // Refresh telemetry only if already loaded
            if viewModel.telemetryLoaded {
                await viewModel.requestTelemetry(for: session)
            }
            // Refresh neighbors only if already loaded
            if viewModel.neighborsLoaded {
                await viewModel.requestNeighbors(for: session)
            }
        }
    }
}

// MARK: - Metric Row

private struct MetricRow: View {
    let label: String
    let value: String
    let delta: Double?
    let higherIsBetter: Bool
    let unit: String
    let fractionDigits: Int

    var body: some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                if let delta {
                    StatusDeltaView(delta: delta, higherIsBetter: higherIsBetter, unit: unit, fractionDigits: fractionDigits)
                }
            }
        } label: {
            Text(label)
        }
    }
}

// MARK: - Neighbor SNR Chart

private struct NeighborSNRChartView: View {
    let name: String
    let neighborPrefix: Data
    let fetchSnapshots: @Sendable () async -> [NodeStatusSnapshotDTO]

    @State private var allDataPoints: [MetricChartView.DataPoint] = []
    @State private var timeRange: HistoryTimeRange = .all

    private var filteredDataPoints: [MetricChartView.DataPoint] {
        guard let start = timeRange.startDate else { return allDataPoints }
        return allDataPoints.filter { $0.date >= start }
    }

    var body: some View {
        List {
            HistoryTimeRangePicker(selection: $timeRange)

            Section {
                MetricChartView(
                    title: name,
                    unit: "dB",
                    dataPoints: filteredDataPoints,
                    accentColor: .blue
                )
            }
        }
        .navigationTitle(name)
        .liquidGlassToolbarBackground()
        .task {
            let snapshots = await fetchSnapshots()
            allDataPoints = snapshots.compactMap { snapshot in
                guard let neighbors = snapshot.neighborSnapshots,
                      let match = neighbors.first(where: { $0.publicKeyPrefix == neighborPrefix })
                else { return nil }
                return MetricChartView.DataPoint(id: snapshot.id, date: snapshot.timestamp, value: match.snr)
            }
        }
    }
}

// MARK: - Neighbor Row

private struct NeighborRow: View {
    let neighbor: NeighbourInfo
    let contact: ContactDTO?
    let previousNeighbor: NeighborSnapshotEntry?
    let hasPreviousSnapshot: Bool

    init(
        neighbor: NeighbourInfo,
        contact: ContactDTO?,
        previousNeighbor: NeighborSnapshotEntry? = nil,
        hasPreviousSnapshot: Bool = false
    ) {
        self.neighbor = neighbor
        self.contact = contact
        self.previousNeighbor = previousNeighbor
        self.hasPreviousSnapshot = hasPreviousSnapshot
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(displayName)

                    if hasPreviousSnapshot && previousNeighbor == nil {
                        Text(L10n.RemoteNodes.RemoteNodes.History.new)
                            .font(.caption2)
                            .bold()
                            .foregroundStyle(.green)
                    }
                }

                HStack(spacing: 4) {
                    Text(firstKeyByte)
                        .font(.system(.caption2, design: .monospaced))
                    Text("·")
                    Text(lastSeenText)
                        .font(.caption2)
                }
                .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Image(systemName: "cellularbars", variableValue: snrLevel)
                    .foregroundStyle(snrColor)

                Text("SNR \(neighbor.snr.formatted(.number.precision(.fractionLength(1))))dB")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let previous = previousNeighbor {
                    let snrDelta = neighbor.snr - previous.snr
                    if abs(snrDelta) >= 0.1 {
                        StatusDeltaView(delta: snrDelta, higherIsBetter: true, unit: " dB", fractionDigits: 1)
                    }
                }
            }
        }
    }

    private var displayName: String {
        contact?.displayName ?? L10n.RemoteNodes.RemoteNodes.Status.unknown
    }

    private var firstKeyByte: String {
        guard let firstByte = neighbor.publicKeyPrefix.first else { return "" }
        return Data([firstByte]).hexString()
    }

    private var lastSeenText: String {
        let seconds = neighbor.secondsAgo
        if seconds < 60 {
            return L10n.RemoteNodes.RemoteNodes.Status.secondsAgo(seconds)
        } else if seconds < 3600 {
            return L10n.RemoteNodes.RemoteNodes.Status.minutesAgo(seconds / 60)
        } else {
            return L10n.RemoteNodes.RemoteNodes.Status.hoursAgo(seconds / 3600)
        }
    }

    private var snrQuality: SNRQuality { SNRQuality(snr: neighbor.snr) }
    private var snrLevel: Double { snrQuality.barLevel }
    private var snrColor: Color { snrQuality.color }
}

// MARK: - Disappeared Neighbor Row

private struct DisappearedNeighborRow: View {
    let neighbor: NeighborSnapshotEntry
    let contact: ContactDTO?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                Text(L10n.RemoteNodes.RemoteNodes.History.notSeen)
                    .font(.caption2)
            }
            Spacer()
            Text("SNR \(neighbor.snr.formatted(.number.precision(.fractionLength(1))))dB")
                .font(.caption)
        }
        .foregroundStyle(.tertiary)
    }

    private var displayName: String {
        contact?.displayName
            ?? Data(neighbor.publicKeyPrefix.prefix(4)).hexString()
    }
}

// MARK: - Telemetry Row

private struct TelemetryRow: View {
    let dataPoint: LPPDataPoint
    let ocvArray: [Int]

    var body: some View {
        if dataPoint.type == .voltage, case .float(let voltage) = dataPoint.value {
            // Calculate percentage using OCV array
            let millivolts = Int(voltage * 1000)
            let battery = BatteryInfo(level: millivolts)
            let percentage = battery.percentage(using: ocvArray)

            LabeledContent(dataPoint.typeName) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(dataPoint.formattedValue)
                    Text("\(percentage)%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            LabeledContent(dataPoint.typeName, value: dataPoint.formattedValue)
        }
    }
}

#Preview {
    RepeaterStatusView(
        session: RemoteNodeSessionDTO(
            deviceID: UUID(),
            publicKey: Data(repeating: 0x42, count: 32),
            name: "Test Repeater",
            role: .repeater,
            isConnected: true,
            permissionLevel: .admin
        )
    )
    .environment(\.appState, AppState())
}
