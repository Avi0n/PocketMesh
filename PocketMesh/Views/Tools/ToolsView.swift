import SwiftUI

struct ToolsView: View {
    private static let lineOfSightSidebarWidthMin: CGFloat = 380
    private static let lineOfSightSidebarWidthIdeal: CGFloat = 440
    private static let lineOfSightSidebarWidthMax: CGFloat = 560

    private enum ToolSelection: Hashable {
        case tracePath
        case lineOfSight
        case rxLog
        case noiseFloor
        case cli
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
            L10n.Tools.Tools.tracePath
        case .rxLog:
            L10n.Tools.Tools.rxLog
        case .noiseFloor:
            L10n.Tools.Tools.noiseFloor
        case .cli:
            L10n.Tools.Tools.cli
        case .lineOfSight, .none:
            L10n.Tools.Tools.title
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
                        Label(L10n.Tools.Tools.tracePath, systemImage: "point.3.connected.trianglepath.dotted")
                    }

                    NavigationLink {
                        LineOfSightView()
                    } label: {
                        Label(L10n.Tools.Tools.lineOfSight, systemImage: "eye")
                    }

                    NavigationLink {
                        RxLogView()
                    } label: {
                        Label(L10n.Tools.Tools.rxLog, systemImage: "waveform.badge.magnifyingglass")
                    }

                    NavigationLink {
                        NoiseFloorView()
                    } label: {
                        Label(L10n.Tools.Tools.noiseFloor, systemImage: "waveform")
                    }

                    NavigationLink {
                        CLIToolView()
                    } label: {
                        Label(L10n.Tools.Tools.cli, systemImage: "terminal")
                    }
                }
                .navigationTitle(L10n.Tools.Tools.title)
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
                    Label(L10n.Tools.Tools.tracePath, systemImage: "point.3.connected.trianglepath.dotted")
                }

                Button {
                    selectedTool = .lineOfSight
                    isShowingLineOfSightPoints = true
                    sidebarPath = NavigationPath()
                    sidebarPath.append(SidebarDestination.lineOfSightPoints)
                } label: {
                    Label(L10n.Tools.Tools.lineOfSight, systemImage: "eye")
                }

                Button {
                    selectedTool = .rxLog
                    isShowingLineOfSightPoints = false
                    sidebarPath = NavigationPath()
                } label: {
                    Label(L10n.Tools.Tools.rxLog, systemImage: "waveform.badge.magnifyingglass")
                }

                Button {
                    selectedTool = .noiseFloor
                    isShowingLineOfSightPoints = false
                    sidebarPath = NavigationPath()
                } label: {
                    Label(L10n.Tools.Tools.noiseFloor, systemImage: "waveform")
                }

                Button {
                    selectedTool = .cli
                    isShowingLineOfSightPoints = false
                    sidebarPath = NavigationPath()
                } label: {
                    Label(L10n.Tools.Tools.cli, systemImage: "terminal")
                }
            }
            .listStyle(.sidebar)
            .navigationTitle(L10n.Tools.Tools.title)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    BLEStatusIndicatorView()
                }
            }
            .navigationDestination(for: SidebarDestination.self) { destination in
                switch destination {
                case .lineOfSightPoints:
                    LineOfSightView(viewModel: lineOfSightViewModel, layoutMode: .panel)
                        .navigationTitle(L10n.Tools.Tools.lineOfSight)
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
        case .noiseFloor:
            NoiseFloorView()
        case .cli:
            CLIToolView()
        case .none:
            ContentUnavailableView(L10n.Tools.Tools.selectTool, systemImage: "wrench.and.screwdriver")
        }
    }
}

#Preview {
    ToolsView()
        .environment(\.appState, AppState())
}
