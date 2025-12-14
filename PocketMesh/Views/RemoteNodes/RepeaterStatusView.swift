import SwiftUI
import PocketMeshKit

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
                neighborsSection
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
                    .disabled(viewModel.isLoadingStatus || viewModel.isLoadingNeighbors)
                }
            }
            .task {
                viewModel.configure(appState: appState)
                await viewModel.requestStatus(for: session)
                await viewModel.requestNeighbors(for: session)
            }
            .refreshable {
                await viewModel.requestStatus(for: session)
                await viewModel.requestNeighbors(for: session)
            }
        }
        .presentationDetents([.medium, .large])
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

                    if session.isConnected {
                        Label("Connected", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
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
        if let uptime = viewModel.uptimeDisplay {
            LabeledContent("Uptime", value: uptime)
        }

        if let battery = viewModel.batteryDisplay {
            LabeledContent("Battery", value: battery)
        }

        if let noiseFloor = viewModel.noiseFloorDisplay {
            LabeledContent("Noise Floor", value: noiseFloor)
        }

        if let txCount = viewModel.txCountDisplay {
            LabeledContent("TX Count", value: txCount)
        }

        if let rxCount = viewModel.rxCountDisplay {
            LabeledContent("RX Count", value: rxCount)
        }

        if let airTime = viewModel.airTimeDisplay {
            LabeledContent("RX Airtime", value: airTime)
        }
    }

    // MARK: - Neighbors Section

    private var neighborsSection: some View {
        Section("Neighbors (\(viewModel.neighbors.count))") {
            if viewModel.isLoadingNeighbors && viewModel.neighbors.isEmpty {
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
        }
    }

    // MARK: - Actions

    private func refresh() {
        Task {
            await viewModel.requestStatus(for: session)
            await viewModel.requestNeighbors(for: session)
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

            Text(String(format: "%.1f dB", neighbor.snr))
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
