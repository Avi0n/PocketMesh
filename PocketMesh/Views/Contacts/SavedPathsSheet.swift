import SwiftUI
import PocketMeshServices

/// Sheet displaying saved trace paths for selection
struct SavedPathsSheet: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = SavedPathsViewModel()

    /// Callback when a path is selected
    var onSelect: (SavedTracePathDTO) -> Void

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
            .navigationTitle("Saved Paths")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                viewModel.configure(appState: appState)
                await viewModel.loadSavedPaths()
            }
            .confirmationDialog(
                "Delete Path",
                isPresented: .init(
                    get: { pathToDelete != nil },
                    set: { if !$0 { pathToDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let path = pathToDelete {
                        Task { await viewModel.deletePath(path) }
                    }
                }
            } message: {
                if let path = pathToDelete {
                    Text("Delete \"\(path.name)\"? This will remove the path and all run history.")
                }
            }
            .alert("Rename Path", isPresented: .init(
                get: { pathToRename != nil },
                set: { if !$0 { pathToRename = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Cancel", role: .cancel) { }
                Button("Save") {
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
            Label("No Saved Paths", systemImage: "bookmark")
        } description: {
            Text("Save paths after running traces to quickly re-run them later.")
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
                        Button("Delete", role: .destructive) {
                            pathToDelete = path
                        }
                    }
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") {
                            renameText = path.name
                            pathToRename = path
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
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
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var subtitleText: String {
        var parts: [String] = []

        // Run count
        let runText = path.runCount == 1 ? "1 run" : "\(path.runCount) runs"
        parts.append(runText)

        // Last run
        if let lastDate = path.lastRunDate {
            parts.append("Last: \(lastDate.relativeFormatted)")
        }

        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var healthDot: some View {
        let rate = path.successRate
        Circle()
            .fill(rate >= 90 ? .green : rate >= 50 ? .yellow : .red)
            .frame(width: 8, height: 8)
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
