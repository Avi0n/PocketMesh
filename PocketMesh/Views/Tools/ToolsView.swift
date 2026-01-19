import SwiftUI

struct ToolsView: View {
    private static let lineOfSightSidebarWidthMin: CGFloat = 380
    private static let lineOfSightSidebarWidthIdeal: CGFloat = 440
    private static let lineOfSightSidebarWidthMax: CGFloat = 560

    private enum ToolSelection: Hashable {
        case tracePath
        case lineOfSight
        case rxLog
    }

    private enum SidebarDestination: Hashable {
        case lineOfSightPoints
    }

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedTool: ToolSelection?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var sidebarPath = NavigationPath()
    @State private var isShowingLineOfSightPoints = false

    @State private var lineOfSightViewModel = LineOfSightViewModel()

    private var shouldUseSplitView: Bool {
        horizontalSizeClass == .regular
    }

    private var detailTitle: String {
        switch selectedTool {
        case .tracePath:
            "Trace Path"
        case .rxLog:
            "RX Log"
        case .lineOfSight, .none:
            "Tools"
        }
    }

    var body: some View {
        if shouldUseSplitView {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                if isShowingLineOfSightPoints {
                    sidebarStack
                        .navigationSplitViewColumnWidth(
                            min: Self.lineOfSightSidebarWidthMin,
                            ideal: Self.lineOfSightSidebarWidthIdeal,
                            max: Self.lineOfSightSidebarWidthMax
                        )
                } else {
                    sidebarStack
                }
            } detail: {
                NavigationStack {
                    if selectedTool == .lineOfSight {
                        toolDetailView
                            .navigationBarTitleDisplayMode(.inline)
                    } else {
                        toolDetailView
                            .navigationTitle(detailTitle)
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
                .liquidGlassToolbarBackground()
            }
            .ignoresSafeArea(edges: .top)
            .onChange(of: sidebarPath) { _, _ in
                if sidebarPath.isEmpty, isShowingLineOfSightPoints {
                    isShowingLineOfSightPoints = false
                    selectedTool = nil
                }
            }
        } else {
            NavigationStack {
                List {
                    NavigationLink {
                        TracePathView()
                    } label: {
                        Label("Trace Path", systemImage: "point.3.connected.trianglepath.dotted")
                    }

                    NavigationLink {
                        LineOfSightView()
                    } label: {
                        Label("Line of Sight", systemImage: "eye")
                    }

                    NavigationLink {
                        RxLogView()
                    } label: {
                        Label("RX Log", systemImage: "waveform.badge.magnifyingglass")
                    }
                }
                .navigationTitle("Tools")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        BLEStatusIndicatorView()
                    }
                }
            }
        }
    }

    private var sidebarStack: some View {
        NavigationStack(path: $sidebarPath) {
            List {
                Button {
                    selectedTool = .tracePath
                    isShowingLineOfSightPoints = false
                    sidebarPath = NavigationPath()
                } label: {
                    Label("Trace Path", systemImage: "point.3.connected.trianglepath.dotted")
                }

                Button {
                    selectedTool = .lineOfSight
                    isShowingLineOfSightPoints = true
                    sidebarPath = NavigationPath()
                    sidebarPath.append(SidebarDestination.lineOfSightPoints)
                } label: {
                    Label("Line of Sight", systemImage: "eye")
                }

                Button {
                    selectedTool = .rxLog
                    isShowingLineOfSightPoints = false
                    sidebarPath = NavigationPath()
                } label: {
                    Label("RX Log", systemImage: "waveform.badge.magnifyingglass")
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Tools")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    BLEStatusIndicatorView()
                }
            }
            .navigationDestination(for: SidebarDestination.self) { destination in
                switch destination {
                case .lineOfSightPoints:
                    LineOfSightView(viewModel: lineOfSightViewModel, layoutMode: .panel)
                        .navigationTitle("Line of Sight")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
    }

    @ViewBuilder
    private var toolDetailView: some View {
        switch selectedTool {
        case .tracePath:
            TracePathView()
        case .lineOfSight:
            LineOfSightView(viewModel: lineOfSightViewModel, layoutMode: .map)
        case .rxLog:
            RxLogView()
        case .none:
            ContentUnavailableView("Select a tool", systemImage: "wrench.and.screwdriver")
        }
    }
}

#Preview {
    ToolsView()
        .environment(\.appState, AppState())
}
