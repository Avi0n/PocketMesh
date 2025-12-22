import PocketMeshServices
import SwiftUI

/// Display view for repeater stats, telemetry, and neighbors
struct RepeaterStatusView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    let session: RemoteNodeSessionDTO
    @State private var viewModel = RepeaterStatusViewModel()

    var body: some View {
        NavigationStack {
            List {
                headerSection
                statusSection
                telemetrySection
                neighborsSection  // Moved to bottom with lazy loading
            }
            .navigationTitle("Repeater Status")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        refresh()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoadingStatus || viewModel.isLoadingNeighbors || viewModel.isLoadingTelemetry)
                }
            }
            .task {
                viewModel.configure(appState: appState)
                await viewModel.registerHandlers(appState: appState)

                // Request Status first (includes clock query)
                await viewModel.requestStatus(for: session)
                // Note: Telemetry and Neighbors are NOT auto-loaded - user must expand the section
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
        Section("Status") {
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
        LabeledContent("Battery", value: viewModel.batteryDisplay)
        // Health
        LabeledContent("Uptime", value: viewModel.uptimeDisplay)
        LabeledContent("Clock", value: viewModel.clockDisplay)
        // Radio
        LabeledContent("Last RSSI", value: viewModel.lastRSSIDisplay)
        LabeledContent("Last SNR", value: viewModel.lastSNRDisplay)
        LabeledContent("Noise Floor", value: viewModel.noiseFloorDisplay)
        // Activity
        LabeledContent("Packets Sent", value: viewModel.packetsSentDisplay)
        LabeledContent("Packets Received", value: viewModel.packetsReceivedDisplay)
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
                    Text("No neighbors discovered")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.neighbors, id: \.publicKeyPrefix) { neighbor in
                        NeighborRow(neighbor: neighbor)
                    }
                }
            } label: {
                HStack {
                    Text("Neighbors")
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
                } else if let telemetry = viewModel.telemetry {
                    if telemetry.dataPoints.isEmpty {
                        Text("No sensor data")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(telemetry.dataPoints, id: \.channel) { dataPoint in
                            TelemetryRow(dataPoint: dataPoint)
                        }
                    }
                } else {
                    Text("No telemetry data")
                        .foregroundStyle(.secondary)
                }
            } label: {
                HStack {
                    Text("Telemetry")
                    Spacer()
                    if viewModel.telemetryLoaded {
                        Text("\(viewModel.telemetry?.dataPoints.count ?? 0)")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("tap to load")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
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

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(publicKeyHex)
                    .font(.system(.footnote, design: .monospaced))

                Text(lastSeenText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(neighbor.snr.formatted(.number.precision(.fractionLength(1)))) dB")
                .font(.caption)
                .foregroundStyle(snrColor)
        }
    }

    private var publicKeyHex: String {
        neighbor.publicKeyPrefix.map { String(format: "%02X", $0) }.joined()
    }

    private var lastSeenText: String {
        let seconds = neighbor.secondsAgo
        if seconds < 60 {
            return "\(seconds)s ago"
        } else if seconds < 3600 {
            return "\(seconds / 60)m ago"
        } else {
            return "\(seconds / 3600)h ago"
        }
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

    var body: some View {
        if dataPoint.type == .voltage, let percentage = dataPoint.batteryPercentage {
            // For voltage, show both voltage and calculated battery percentage
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
    .environment(AppState())
}
