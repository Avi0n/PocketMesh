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
            }
        }
    }

    @ViewBuilder
    private var statusRows: some View {
        // Power
        LabeledContent(L10n.RemoteNodes.RemoteNodes.Status.battery, value: viewModel.batteryDisplay)
        // Health
        LabeledContent(L10n.RemoteNodes.RemoteNodes.Status.uptime, value: viewModel.uptimeDisplay)
        // Radio
        LabeledContent(L10n.RemoteNodes.RemoteNodes.Status.lastRssi, value: viewModel.lastRSSIDisplay)
        LabeledContent(L10n.RemoteNodes.RemoteNodes.Status.lastSnr, value: viewModel.lastSNRDisplay)
        LabeledContent(L10n.RemoteNodes.RemoteNodes.Status.noiseFloor, value: viewModel.noiseFloorDisplay)
        // Activity
        LabeledContent(L10n.RemoteNodes.RemoteNodes.Status.packetsSent, value: viewModel.packetsSentDisplay)
        LabeledContent(L10n.RemoteNodes.RemoteNodes.Status.packetsReceived, value: viewModel.packetsReceivedDisplay)
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
                        NeighborRow(
                            neighbor: neighbor,
                            contact: contacts.first { $0.publicKeyPrefix.starts(with: neighbor.publicKeyPrefix) }
                        )
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
                                    TelemetryRow(dataPoint: dataPoint, ocvArray: viewModel.currentOCVArray)
                                }
                            } header: {
                                Text(L10n.RemoteNodes.RemoteNodes.Status.channel(Int(group.channel)))
                                    .fontWeight(.semibold)
                            }
                        }
                    } else {
                        ForEach(viewModel.cachedDataPoints, id: \.self) { dataPoint in
                            TelemetryRow(dataPoint: dataPoint, ocvArray: viewModel.currentOCVArray)
                        }
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

// MARK: - Neighbor Row

private struct NeighborRow: View {
    let neighbor: NeighbourInfo
    let contact: ContactDTO?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)

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
            }
        }
    }

    private var displayName: String {
        contact?.displayName ?? L10n.RemoteNodes.RemoteNodes.Status.unknown
    }

    private var firstKeyByte: String {
        guard let firstByte = neighbor.publicKeyPrefix.first else { return "" }
        return String(format: "%02X", firstByte)
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

    private var snrLevel: Double {
        let snr = neighbor.snr
        if snr > 10 { return 1.0 }
        if snr > 5 { return 0.75 }
        if snr > 0 { return 0.5 }
        if snr > -10 { return 0.25 }
        return 0.1
    }

    private var snrColor: Color {
        if neighbor.snr >= 5 {
            return .green
        } else if neighbor.snr >= 0 {
            return .yellow
        } else {
            return .red
        }
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
