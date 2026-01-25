import SwiftUI
import PocketMeshServices

/// Sheet displaying saved trace paths for selection
struct SavedPathsSheet: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = SavedPathsViewModel()

    /// Callback when a path is selected
    var onSelect: (SavedTracePathDTO) -> Void
    /// Callback when a path is deleted
    var onDelete: ((UUID) -> Void)?

    @State private var pathToDelete: SavedTracePathDTO?
    @State private var pathToRename: SavedTracePathDTO?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.savedPaths.isEmpty && !viewModel.isLoading {
                    emptyState
                } else {
                    pathsList
                }
            }
            .navigationTitle(L10n.Contacts.Contacts.SavedPaths.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.Contacts.Contacts.Common.done) { dismiss() }
                }
            }
            .task {
                viewModel.configure(appState: appState)
                await viewModel.loadSavedPaths()
            }
            .confirmationDialog(
                L10n.Contacts.Contacts.SavedPaths.deleteTitle,
                isPresented: .init(
                    get: { pathToDelete != nil },
                    set: { if !$0 { pathToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button(L10n.Contacts.Contacts.Common.delete, role: .destructive) {
                    if let path = pathToDelete {
                        let pathId = path.id
                        Task {
                            await viewModel.deletePath(path)
                            onDelete?(pathId)
                        }
                    }
                }
            } message: {
                if let path = pathToDelete {
                    Text(L10n.Contacts.Contacts.SavedPaths.deleteMessage(path.name))
                }
            }
            .alert(L10n.Contacts.Contacts.SavedPaths.renameTitle, isPresented: .init(
                get: { pathToRename != nil },
                set: { if !$0 { pathToRename = nil } }
            )) {
                TextField(L10n.Contacts.Contacts.Detail.name, text: $renameText)
                Button(L10n.Contacts.Contacts.Common.cancel, role: .cancel) { }
                Button(L10n.Contacts.Contacts.Common.save) {
                    if let path = pathToRename {
                        Task { await viewModel.renamePath(path, to: renameText) }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label(L10n.Contacts.Contacts.SavedPaths.Empty.title, systemImage: "bookmark")
        } description: {
            Text(L10n.Contacts.Contacts.SavedPaths.Empty.description)
        }
    }

    // MARK: - Paths List

    private var pathsList: some View {
        List {
            ForEach(viewModel.savedPaths) { path in
                Button {
                    onSelect(path)
                    dismiss()
                } label: {
                    SavedPathRow(path: path)
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(L10n.Contacts.Contacts.Common.delete, role: .destructive) {
                            pathToDelete = path
                        }
                    }
                    .contextMenu {
                        Button(L10n.Contacts.Contacts.SavedPaths.rename, systemImage: "pencil") {
                            renameText = path.name
                            pathToRename = path
                        }
                        Button(L10n.Contacts.Contacts.Common.delete, systemImage: "trash", role: .destructive) {
                            pathToDelete = path
                        }
                    }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if viewModel.isLoading {
                ProgressView()
            }
        }
    }
}

// MARK: - Saved Path Row

private struct SavedPathRow: View {
    let path: SavedTracePathDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(path.name)
                .font(.body)

            HStack(spacing: 8) {
                // Run count and recency
                Text(subtitleText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                // Health indicator
                healthDot

                // Mini sparkline
                if !path.recentRTTs.isEmpty {
                    MiniSparkline(values: path.recentRTTs)
                        .frame(width: 50, height: 16)
                        .accessibilityLabel(sparklineAccessibilityLabel)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var subtitleText: String {
        var parts: [String] = []

        // Run count
        let runText = path.runCount == 1
            ? L10n.Contacts.Contacts.SavedPaths.Runs.singular
            : L10n.Contacts.Contacts.SavedPaths.Runs.plural(path.runCount)
        parts.append(runText)

        // Last run
        if let lastDate = path.lastRunDate {
            parts.append(L10n.Contacts.Contacts.SavedPaths.lastRun(lastDate.relativeFormatted))
        }

        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var healthDot: some View {
        let rate = path.successRate
        let healthDescription = rate >= 90
            ? L10n.Contacts.Contacts.SavedPaths.Health.healthy
            : rate >= 50
            ? L10n.Contacts.Contacts.SavedPaths.Health.degraded
            : L10n.Contacts.Contacts.SavedPaths.Health.poor
        Circle()
            .fill(rate >= 90 ? .green : rate >= 50 ? .yellow : .red)
            .frame(width: 8, height: 8)
            .accessibilityLabel(L10n.Contacts.Contacts.SavedPaths.healthLabel(healthDescription, rate))
    }

    private var sparklineAccessibilityLabel: String {
        let rtts = path.recentRTTs
        guard !rtts.isEmpty else { return L10n.Contacts.Contacts.SavedPaths.noResponseData }

        let avgRTT = rtts.reduce(0, +) / rtts.count
        let trend: String
        if rtts.count >= 2 {
            let firstHalf = rtts.prefix(rtts.count / 2).reduce(0, +) / max(1, rtts.count / 2)
            let secondHalf = rtts.suffix(rtts.count / 2).reduce(0, +) / max(1, rtts.count / 2)
            if secondHalf > firstHalf + 50 {
                trend = L10n.Contacts.Contacts.SavedPaths.Trend.increasing
            } else if secondHalf < firstHalf - 50 {
                trend = L10n.Contacts.Contacts.SavedPaths.Trend.decreasing
            } else {
                trend = L10n.Contacts.Contacts.SavedPaths.Trend.stable
            }
        } else {
            trend = L10n.Contacts.Contacts.SavedPaths.Trend.stable
        }
        return L10n.Contacts.Contacts.SavedPaths.responseTimes(avgRTT, trend)
    }
}

// MARK: - Mini Sparkline

struct MiniSparkline: View {
    let values: [Int]

    var body: some View {
        GeometryReader { geometry in
            if let minVal = values.min(), let maxVal = values.max(), maxVal > minVal {
                Path { path in
                    let range = Double(maxVal - minVal)
                    let stepX = geometry.size.width / Double(max(values.count - 1, 1))

                    for (index, value) in values.enumerated() {
                        let x = Double(index) * stepX
                        let y = geometry.size.height - (Double(value - minVal) / range * geometry.size.height)

                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(Color.accentColor, lineWidth: 1.5)
            } else {
                // Flat line for constant values
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geometry.size.height / 2))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height / 2))
                }
                .stroke(Color.accentColor, lineWidth: 1.5)
            }
        }
    }
}

// MARK: - Date Extension

private extension Date {
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}
