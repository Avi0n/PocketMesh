import CoreLocation
import MapKit
import MC1Services
import SwiftUI

private extension CLLocationCoordinate2D {
    var formattedString: String {
        "\(latitude.formatted(.number.precision(.fractionLength(6)))), \(longitude.formatted(.number.precision(.fractionLength(6))))"
    }
}

private let analysisSheetDetentCollapsed: PresentationDetent = .fraction(0.25)
private let analysisSheetDetentHalf: PresentationDetent = .fraction(0.5)
private let analysisSheetDetentExpanded: PresentationDetent = .large

// MARK: - Line of Sight View

/// Full-screen map view for analyzing line-of-sight between two points
struct LineOfSightView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: LineOfSightViewModel
    @State private var sheetDetent: PresentationDetent = analysisSheetDetentCollapsed
    @State private var enableHalfDetent = false
    @State private var showAnalysisSheet: Bool
    @State private var editingPoint: PointID?
    @State private var isDropPinMode = false
    @State private var mapStyleSelection: MapStyleSelection = .topo
    @State private var sheetBottomInset: CGFloat = 220
    @State private var isResultsExpanded = false
    @State private var isRFSettingsExpanded = false
    @State private var showingMapStyleMenu = false
    @State private var showLabels = true
    @State private var copyHapticTrigger = 0
    @ScaledMetric(relativeTo: .body) private var iconButtonSize: CGFloat = 16

    private let layoutMode: LineOfSightLayoutMode

    // One-time drag hint tooltip for repeater marker
    @AppStorage("hasSeenRepeaterDragHint") private var hasSeenDragHint = false
    @State private var showDragHint = false
    @State private var repeaterMarkerCenter: CGPoint?
    @State private var isNavigatingBack = false

    private var isRelocating: Bool { viewModel.relocatingPoint != nil }

    private var shouldShowExpandedAnalysis: Bool {
        sheetDetent != analysisSheetDetentCollapsed
    }

    private var mapOverlayBottomPadding: CGFloat {
        showAnalysisSheet ? sheetBottomInset : 0
    }

    private var availableSheetDetents: Set<PresentationDetent> {
        if enableHalfDetent {
            [analysisSheetDetentCollapsed, analysisSheetDetentHalf, analysisSheetDetentExpanded]
        } else {
            [analysisSheetDetentCollapsed, analysisSheetDetentExpanded]
        }
    }

    // MARK: - Initialization

    init(preselectedContact: ContactDTO? = nil) {
        _viewModel = State(initialValue: LineOfSightViewModel(preselectedContact: preselectedContact))
        layoutMode = .mapWithSheet
        _showAnalysisSheet = State(initialValue: true)
    }

    init(viewModel: LineOfSightViewModel, layoutMode: LineOfSightLayoutMode) {
        _viewModel = State(initialValue: viewModel)
        self.layoutMode = layoutMode
        _showAnalysisSheet = State(initialValue: layoutMode == .mapWithSheet)
    }

    // MARK: - Body

    var body: some View {
        switch layoutMode {
        case .panel:
            ScrollView {
                analysisSheetContent
            }
            .scrollDismissesKeyboard(.immediately)

        case .map:
            mapCanvasWithBehaviors(showSheet: false)

        case .mapWithSheet:
            mapCanvasWithBehaviors(showSheet: true)
        }
    }

    @ViewBuilder
    private func mapCanvasWithBehaviors(showSheet: Bool) -> some View {
        let base = LOSMapCanvasView(
            viewModel: viewModel,
            appState: appState,
            mapStyleSelection: $mapStyleSelection,
            showingMapStyleMenu: $showingMapStyleMenu,
            showLabels: $showLabels,
            isDropPinMode: $isDropPinMode,
            mapOverlayBottomPadding: mapOverlayBottomPadding,
            cameraBottomSheetFraction: showSheet ? 0.25 : 0,
            onRepeaterTap: { handleRepeaterTap($0) },
            onMapTap: { handleMapTap(at: $0) }
        )
            .onChange(of: viewModel.pointA) { oldValue, newValue in
                if oldValue == nil, newValue != nil, viewModel.pointB != nil {
                    if showSheet {
                        enableHalfDetent = true
                        withAnimation {
                            sheetDetent = analysisSheetDetentHalf
                        }
                    }
                }

                if showSheet, newValue == nil, viewModel.pointB == nil {
                    withAnimation {
                        sheetDetent = analysisSheetDetentCollapsed
                    }
                }
            }
            .onChange(of: viewModel.pointB) { oldValue, newValue in
                if oldValue == nil, newValue != nil, viewModel.pointA != nil {
                    if showSheet {
                        enableHalfDetent = true
                        withAnimation {
                            sheetDetent = analysisSheetDetentHalf
                        }
                    }
                }

                if showSheet, newValue == nil, viewModel.pointA == nil {
                    withAnimation {
                        sheetDetent = analysisSheetDetentCollapsed
                    }
                }
            }
            .onChange(of: sheetDetent) { oldValue, newValue in
                guard showSheet else { return }

                if isRelocating, newValue != analysisSheetDetentCollapsed {
                    viewModel.relocatingPoint = nil
                }

                // Disable half detent once user drags away from it
                if oldValue == analysisSheetDetentHalf, newValue != analysisSheetDetentHalf {
                    enableHalfDetent = false
                }
            }
            .onChange(of: viewModel.repeaterPoint) { oldValue, newValue in
                if oldValue == nil,
                   newValue != nil,
                   newValue?.isOnPath == true,
                   !hasSeenDragHint {
                    withAnimation(.easeIn(duration: 0.3)) {
                        showDragHint = true
                    }
                    hasSeenDragHint = true
                    Task {
                        try? await Task.sleep(for: .seconds(5))
                        withAnimation(.easeOut(duration: 0.3)) {
                            showDragHint = false
                        }
                    }
                }
            }
            .onChange(of: viewModel.analysisStatus) { _, newStatus in
                handleAnalysisStatusChange(newStatus, showSheet: showSheet)
            }
            .task {
                appState.locationService.requestPermissionIfNeeded()
                viewModel.configure(appState: appState)
                await viewModel.loadRepeaters()
                viewModel.centerOnAllRepeaters()
            }

        if showSheet {
            base
                .navigationBarBackButtonHidden(true)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismissLineOfSight()
                        } label: {
                            Label(L10n.Tools.Tools.LineOfSight.back, systemImage: "chevron.left")
                                .labelStyle(.titleAndIcon)
                        }
                        .accessibilityLabel(L10n.Tools.Tools.LineOfSight.back)
                    }
                }
                .liquidGlassToolbarBackground()
                .onDisappear {
                    showAnalysisSheet = false
                }
                .sheet(isPresented: $showAnalysisSheet) {
                    analysisSheet
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.height - proxy.safeAreaInsets.bottom + 15
                        } action: { inset in
                            if sheetDetent == analysisSheetDetentCollapsed {
                                sheetBottomInset = max(0, inset)
                            }
                        }
                        .presentationDetents(availableSheetDetents, selection: $sheetDetent)
                        .presentationDragIndicator(.visible)
                        .presentationBackgroundInteraction(.enabled)
                        .presentationBackground(.regularMaterial)
                        .interactiveDismissDisabled()
                }
        } else {
            base
                .liquidGlassToolbarBackground()
        }
    }

    @MainActor
    private func dismissLineOfSight() {
        guard !isNavigatingBack else { return }
        isNavigatingBack = true

        showAnalysisSheet = false
        viewModel.relocatingPoint = nil

        Task { @MainActor in
            await Task.yield()
            dismiss()
        }
    }

    // MARK: - Analysis Sheet

    private var analysisSheet: some View {
        NavigationStack {
            ScrollView {
                analysisSheetContent
            }
            .scrollDismissesKeyboard(.immediately)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var analysisSheetContent: some View {
        analysisSheetVStack
            .padding()
    }

    private var analysisSheetVStack: some View {
        VStack(alignment: .leading, spacing: 16) {
            pointsSummarySection

            // Before analysis: show analyze button, then RF settings
            if viewModel.canAnalyze, !hasAnalysisResult {
                analyzeButtonSection
                rfSettingsSection
            }

            // After analysis: show button, results, terrain, then RF settings
            if case .result(let result) = viewModel.analysisStatus {
                analyzeButtonSection

                resultSummarySection(result)

                if shouldShowExpandedAnalysis {
                    terrainProfileSection
                    rfSettingsSection
                }
            }

            // Relay analysis: show relay-specific results card
            if case .relayResult(let result) = viewModel.analysisStatus {
                analyzeButtonSection

                RelayResultsCardView(result: result, isExpanded: $isResultsExpanded)

                if shouldShowExpandedAnalysis {
                    terrainProfileSection
                    rfSettingsSection
                }
            }

            if case .error(let message) = viewModel.analysisStatus {
                errorSection(message)
            }
        }
    }

    // MARK: - Points Summary Section

    private var pointsSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with optional cancel button
            HStack {
                Text(L10n.Tools.Tools.LineOfSight.points)
                    .font(.headline)

                Spacer()

                if isRelocating {
                    Button(L10n.Tools.Tools.LineOfSight.cancel) {
                        viewModel.relocatingPoint = nil
                    }
                    .glassButtonStyle()
                    .controlSize(.small)
                }
            }

            // Show relocating message OR point rows
            if let relocatingPoint = viewModel.relocatingPoint {
                relocatingMessageView(for: relocatingPoint)
            } else {
                // Point A row
                pointRow(
                    label: "A",
                    color: .blue,
                    point: viewModel.pointA,
                    pointID: .pointA,
                    onClear: { viewModel.clearPointA() }
                )

                // Repeater row (placeholder or full, positioned between A and B)
                // Inline check for repeaterPoint to ensure SwiftUI properly tracks the dependency
                if let repeater = viewModel.repeaterPoint {
                    repeaterRow
                        .id("repeater-\(repeater.coordinate.latitude)-\(repeater.coordinate.longitude)")
                } else if viewModel.shouldShowRepeaterPlaceholder {
                    addRepeaterRow
                }

                // Point B row
                pointRow(
                    label: "B",
                    color: .green,
                    point: viewModel.pointB,
                    pointID: .pointB,
                    onClear: { viewModel.clearPointB() }
                )

                if viewModel.pointA == nil || viewModel.pointB == nil {
                    Text(L10n.Tools.Tools.LineOfSight.selectPointsHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if viewModel.elevationFetchFailed {
                    Label(
                        L10n.Tools.Tools.LineOfSight.elevationUnavailable,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private func relocatingMessageView(for pointID: PointID) -> some View {
        let pointName: String = switch pointID {
        case .pointA: L10n.Tools.Tools.LineOfSight.pointA
        case .pointB: L10n.Tools.Tools.LineOfSight.pointB
        case .repeater: L10n.Tools.Tools.LineOfSight.repeater
        }

        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.Tools.Tools.LineOfSight.relocating(pointName))
                .font(.subheadline)
                .bold()

            Text(L10n.Tools.Tools.LineOfSight.tapMapInstruction)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(L10n.Tools.Tools.LineOfSight.relocating(pointName)) \(L10n.Tools.Tools.LineOfSight.tapMapInstruction)")
    }

    @ViewBuilder
    private func pointRow(
        label: String,
        color: Color,
        point: SelectedPoint?,
        pointID: PointID,
        onClear: @escaping () -> Void
    ) -> some View {
        let isEditing = editingPoint == pointID

        VStack(alignment: .leading, spacing: 12) {
            // Header row (always visible)
            HStack {
                // Point marker
                Circle()
                    .fill(point != nil ? color : .gray.opacity(0.3))
                    .frame(width: 24, height: 24)
                    .overlay {
                        Text(label)
                            .font(.caption)
                            .bold()
                            .foregroundStyle(.white)
                    }

                // Point info
                if let point {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(point.displayName)
                            .font(.subheadline)
                            .lineLimit(1)

                        if point.isLoadingElevation {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .controlSize(.mini)
                                Text(L10n.Tools.Tools.LineOfSight.loadingElevation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if let elevation = point.groundElevation {
                            Text("\(Int(elevation) + point.additionalHeight)m")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    pointRowButtons(
                        pointID: pointID,
                        isEditing: isEditing,
                        onClear: onClear
                    )
                } else {
                    Text(L10n.Tools.Tools.LineOfSight.notSelected)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()
                }
            }

            // Expanded editor (when editing)
            if isEditing, let point {
                Divider()

                pointHeightEditor(point: point, pointID: pointID)
            }
        }
        .padding(12)
        .animation(.easeInOut(duration: 0.2), value: isEditing)
    }

    @ViewBuilder
    private func pointRowButtons(
        pointID: PointID,
        isEditing: Bool,
        onClear: @escaping () -> Void
    ) -> some View {
        let point = pointID == .pointA ? viewModel.pointA : viewModel.pointB

        // Share menu
        Menu {
            if let coord = point?.coordinate {
                Button(L10n.Tools.Tools.LineOfSight.openInMaps, systemImage: "map") {
                    let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coord))
                    mapItem.name = pointID == .pointA ? L10n.Tools.Tools.LineOfSight.pointA : L10n.Tools.Tools.LineOfSight.pointB
                    mapItem.openInMaps()
                }

                Button(L10n.Tools.Tools.LineOfSight.copyCoordinates, systemImage: "doc.on.doc") {
                    copyHapticTrigger += 1
                    UIPasteboard.general.string = coord.formattedString
                }

                ShareLink(item: coord.formattedString) {
                    Label(L10n.Tools.Tools.LineOfSight.share, systemImage: "square.and.arrow.up")
                }
            }
        } label: {
            Label(L10n.Tools.Tools.LineOfSight.shareLabel, systemImage: "square.and.arrow.up")
                .labelStyle(.iconOnly)
                .frame(width: iconButtonSize, height: iconButtonSize)
        }
        .glassButtonStyle()
        .sensoryFeedback(.success, trigger: copyHapticTrigger)
        .controlSize(.small)

        // Relocate button (toggles on/off)
        Button {
            if viewModel.relocatingPoint == pointID {
                viewModel.relocatingPoint = nil
            } else {
                viewModel.relocatingPoint = pointID
                withAnimation {
                    sheetDetent = analysisSheetDetentCollapsed
                }
            }
        } label: {
            Label(L10n.Tools.Tools.LineOfSight.relocate, systemImage: "mappin")
                .labelStyle(.iconOnly)
                .frame(width: iconButtonSize, height: iconButtonSize)
        }
        .glassButtonStyle()
        .controlSize(.small)
        .disabled(viewModel.relocatingPoint != nil && viewModel.relocatingPoint != pointID)

        // Edit/Done toggle
        Button {
            withAnimation {
                editingPoint = isEditing ? nil : pointID
            }
        } label: {
            Group {
                if isEditing {
                    Label(L10n.Tools.Tools.LineOfSight.done, systemImage: "checkmark")
                        .labelStyle(.iconOnly)
                } else {
                    Label(L10n.Tools.Tools.LineOfSight.edit, systemImage: "ruler")
                        .labelStyle(.iconOnly)
                        .rotationEffect(.degrees(90))
                }
            }
            .frame(width: iconButtonSize, height: iconButtonSize)
        }
        .glassButtonStyle()
        .controlSize(.small)

        // Clear button
        Button(action: onClear) {
            Label(L10n.Tools.Tools.LineOfSight.clear, systemImage: "xmark")
                .labelStyle(.iconOnly)
                .frame(width: iconButtonSize, height: iconButtonSize)
        }
        .glassButtonStyle()
        .controlSize(.small)
    }

    @ViewBuilder
    private func pointHeightEditor(point: SelectedPoint, pointID: PointID) -> some View {
        Grid(alignment: .leading, verticalSpacing: 8) {
            // Ground elevation row
            GridRow {
                Text(L10n.Tools.Tools.LineOfSight.groundElevation)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                if let elevation = point.groundElevation {
                    Text("\(Int(elevation)) m")
                        .font(.caption)
                        .monospacedDigit()
                } else {
                    ProgressView()
                        .controlSize(.mini)
                }
            }

            // Additional height row
            GridRow {
                Text(L10n.Tools.Tools.LineOfSight.additionalHeight)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Stepper(
                    value: Binding(
                        get: { point.additionalHeight },
                        set: { viewModel.updateAdditionalHeight(for: pointID, meters: $0) }
                    ),
                    in: 0...200
                ) {
                    Text("\(point.additionalHeight) m")
                        .font(.caption)
                        .monospacedDigit()
                }
                .controlSize(.small)
            }

            // Total row
            if let elevation = point.groundElevation {
                Divider()
                    .gridCellColumns(2)

                GridRow {
                    Text(L10n.Tools.Tools.LineOfSight.totalHeight)
                        .font(.caption)
                        .bold()

                    Spacer()

                    Text("\(Int(elevation) + point.additionalHeight) m")
                        .font(.caption)
                        .monospacedDigit()
                        .bold()
                }
            }
        }
    }

    // MARK: - Repeater Row

    @ViewBuilder
    private var repeaterRow: some View {
        let isEditing = editingPoint == .repeater

        VStack(alignment: .leading, spacing: 12) {
            // Header row
            HStack {
                // Repeater marker (purple)
                Circle()
                    .fill(.purple)
                    .frame(width: 24, height: 24)
                    .overlay {
                        Text("R")
                            .font(.caption)
                            .bold()
                            .foregroundStyle(.white)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.Tools.Tools.LineOfSight.repeater)
                        .font(.subheadline)
                        .lineLimit(1)

                    if let elevation = viewModel.repeaterGroundElevation {
                        let totalHeight = Int(elevation) + (viewModel.repeaterPoint?.additionalHeight ?? 0)
                        Text("\(totalHeight)m")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Share menu
                Menu {
                    if let coord = viewModel.repeaterPoint?.coordinate {
                        Button(L10n.Tools.Tools.LineOfSight.openInMaps, systemImage: "map") {
                            let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coord))
                            mapItem.name = L10n.Tools.Tools.LineOfSight.repeaterLocation
                            mapItem.openInMaps()
                        }

                        Button(L10n.Tools.Tools.LineOfSight.copyCoordinates, systemImage: "doc.on.doc") {
                            copyHapticTrigger += 1
                            UIPasteboard.general.string = coord.formattedString
                        }

                        ShareLink(item: coord.formattedString) {
                            Label(L10n.Tools.Tools.LineOfSight.share, systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    Label(L10n.Tools.Tools.LineOfSight.shareLabel, systemImage: "square.and.arrow.up")
                        .labelStyle(.iconOnly)
                        .frame(width: iconButtonSize, height: iconButtonSize)
                }
                .glassButtonStyle()
                .sensoryFeedback(.success, trigger: copyHapticTrigger)
                .controlSize(.small)

                // Relocate button (toggles on/off)
                Button {
                    if viewModel.relocatingPoint == .repeater {
                        viewModel.relocatingPoint = nil
                    } else {
                        viewModel.relocatingPoint = .repeater
                        withAnimation {
                            sheetDetent = analysisSheetDetentCollapsed
                        }
                    }
                } label: {
                    Label(L10n.Tools.Tools.LineOfSight.relocate, systemImage: "mappin")
                        .labelStyle(.iconOnly)
                        .frame(width: iconButtonSize, height: iconButtonSize)
                }
                .glassButtonStyle()
                .controlSize(.small)
                .disabled(viewModel.relocatingPoint != nil && viewModel.relocatingPoint != .repeater)

                // Edit/Done toggle
                Button {
                    withAnimation {
                        editingPoint = isEditing ? nil : .repeater
                    }
                } label: {
                    Group {
                        if isEditing {
                            Label(L10n.Tools.Tools.LineOfSight.done, systemImage: "checkmark")
                                .labelStyle(.iconOnly)
                        } else {
                            Label(L10n.Tools.Tools.LineOfSight.edit, systemImage: "ruler")
                                .labelStyle(.iconOnly)
                                .rotationEffect(.degrees(90))
                        }
                    }
                    .frame(width: iconButtonSize, height: iconButtonSize)
                }
                .glassButtonStyle()
                .controlSize(.small)

                // Clear button
                Button {
                    viewModel.clearRepeater()
                } label: {
                    Label(L10n.Tools.Tools.LineOfSight.clear, systemImage: "xmark")
                        .labelStyle(.iconOnly)
                        .frame(width: iconButtonSize, height: iconButtonSize)
                }
                .glassButtonStyle()
                .controlSize(.small)
            }

            // Expanded editor
            if isEditing, let repeaterPoint = viewModel.repeaterPoint {
                Divider()
                repeaterHeightEditor(repeaterPoint: repeaterPoint)
            }
        }
        .padding(12)
        .animation(.easeInOut(duration: 0.2), value: isEditing)
    }

    @ViewBuilder
    private func repeaterHeightEditor(repeaterPoint: RepeaterPoint) -> some View {
        Grid(alignment: .leading, verticalSpacing: 8) {
            if let groundElevation = viewModel.repeaterGroundElevation {
                GridRow {
                    Text(L10n.Tools.Tools.LineOfSight.groundElevation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(groundElevation)) m")
                        .font(.caption)
                        .monospacedDigit()
                }
            }

            GridRow {
                Text(L10n.Tools.Tools.LineOfSight.additionalHeight)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Stepper(
                    value: Binding(
                        get: { repeaterPoint.additionalHeight },
                        set: {
                            viewModel.updateRepeaterHeight(meters: $0)
                            viewModel.analyzeWithRepeater()
                        }
                    ),
                    in: 0...200
                ) {
                    Text("\(repeaterPoint.additionalHeight) m")
                        .font(.caption)
                        .monospacedDigit()
                }
                .controlSize(.small)
            }

            if let groundElevation = viewModel.repeaterGroundElevation {
                Divider()
                    .gridCellColumns(2)

                GridRow {
                    Text(L10n.Tools.Tools.LineOfSight.totalHeight)
                        .font(.caption)
                        .bold()
                    Spacer()
                    Text("\(Int(groundElevation) + repeaterPoint.additionalHeight) m")
                        .font(.caption)
                        .monospacedDigit()
                        .bold()
                }
            }
        }
    }

    // MARK: - Add Repeater Row (Placeholder)

    /// Placeholder row shown when analysis is marginal/obstructed but no repeater exists yet
    private var addRepeaterRow: some View {
        Button {
            viewModel.addRepeater()
            viewModel.analyzeWithRepeater()
        } label: {
            HStack {
                // Purple R marker (matches full row)
                Circle()
                    .fill(.purple)
                    .frame(width: 24, height: 24)
                    .overlay {
                        Text("R")
                            .font(.caption)
                            .bold()
                            .foregroundStyle(.white)
                    }

                Text(L10n.Tools.Tools.LineOfSight.addRepeater)
                    .font(.subheadline)

                Spacer()

                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(.purple)
            }
            .padding(.vertical, 8)
        }
        .glassButtonStyle()
    }

    // MARK: - Analyze Button Section

    private var analyzeButtonSection: some View {
        Button {
            viewModel.shouldAutoZoomOnNextResult = true

            withAnimation {
                sheetDetent = analysisSheetDetentExpanded
            }
            if viewModel.repeaterPoint != nil {
                viewModel.analyzeWithRepeater()
            } else {
                viewModel.analyze()
            }
        } label: {
            if viewModel.isAnalyzing {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(L10n.Tools.Tools.LineOfSight.analyzing)
                }
                .frame(maxWidth: .infinity)
            } else {
                Label(L10n.Tools.Tools.LineOfSight.analyze, systemImage: "waveform.path")
                    .frame(maxWidth: .infinity)
            }
        }
        .glassProminentButtonStyle()
        .controlSize(.large)
        .disabled(viewModel.isAnalyzing || hasAnalysisResult)
    }

    // MARK: - Result Summary Section

    @ViewBuilder
    private func resultSummarySection(_ result: PathAnalysisResult) -> some View {
        ResultsCardView(result: result, isExpanded: $isResultsExpanded)
    }

    // MARK: - Terrain Profile Section

    private var terrainProfileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.Tools.Tools.LineOfSight.terrainProfile)
                    .font(.headline)

                Spacer()

                Label(
                    L10n.Tools.Tools.LineOfSight.earthCurvature(LOSFormatters.formatKFactor(viewModel.refractionK)),
                    systemImage: "globe"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            TerrainProfileCanvas(
                elevationProfile: viewModel.terrainElevationProfile,
                profileSamples: viewModel.profileSamples,
                profileSamplesRB: viewModel.profileSamplesRB,
                // Show repeater marker for both on-path and off-path
                repeaterPathFraction: viewModel.repeaterVisualizationPathFraction,
                repeaterHeight: viewModel.repeaterPoint.map { Double($0.additionalHeight) },
                // Only enable drag for on-path repeaters
                onRepeaterDrag: viewModel.repeaterPoint?.isOnPath == true ? { pathFraction in
                    viewModel.updateRepeaterPosition(pathFraction: pathFraction)
                    viewModel.analyzeWithRepeater()
                } : nil,
                onRepeaterMarkerPosition: { center in
                    repeaterMarkerCenter = center
                },
                // Off-path segment distances for separator and labels
                segmentARDistanceMeters: viewModel.segmentARDistanceMeters,
                segmentRBDistanceMeters: viewModel.segmentRBDistanceMeters
            )
            .overlay {
                if showDragHint, let center = repeaterMarkerCenter {
                    Text(L10n.Tools.Tools.LineOfSight.dragToAdjust)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.regularMaterial, in: .capsule)
                        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
                        .transition(.opacity.combined(with: .scale))
                        .position(x: center.x, y: center.y + 30)
                }
            }
        }
    }

    // MARK: - RF Settings Section

    private var rfSettingsSection: some View {
        DisclosureGroup(isExpanded: $isRFSettingsExpanded) {
            VStack(spacing: 12) {
                // Frequency input - extracted to separate view for @FocusState to work in sheet
                FrequencyInputRow(viewModel: viewModel)

                Divider()

                // Refraction k-factor picker
                HStack {
                    Label(L10n.Tools.Tools.LineOfSight.refraction, systemImage: "globe")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { viewModel.refractionK },
                        set: { viewModel.refractionK = $0 }
                    )) {
                        Text(L10n.Tools.Tools.LineOfSight.Refraction.none).tag(1.0)
                        Text(L10n.Tools.Tools.LineOfSight.Refraction.standard).tag(4.0 / 3.0)
                        Text(L10n.Tools.Tools.LineOfSight.Refraction.ducting).tag(4.0)
                    }
                    .pickerStyle(.menu)
                }
            }
            .padding(.top, 8)
        } label: {
            Label(L10n.Tools.Tools.LineOfSight.rfSettings, systemImage: "antenna.radiowaves.left.and.right")
                .font(.headline)
        }
        .tint(.primary)
    }

    // MARK: - Error Section

    private func errorSection(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text(L10n.Tools.Tools.LineOfSight.analysisFailed)
                .font(.headline)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(L10n.Tools.Tools.LineOfSight.retry) {
                if viewModel.repeaterPoint != nil {
                    viewModel.analyzeWithRepeater()
                } else {
                    viewModel.analyze()
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    // MARK: - Computed Properties

    private var analysisResult: PathAnalysisResult? {
        if case .result(let result) = viewModel.analysisStatus {
            return result
        }
        return nil
    }

    private var hasAnalysisResult: Bool {
        if case .result = viewModel.analysisStatus { return true }
        if case .relayResult = viewModel.analysisStatus { return true }
        return false
    }

    // MARK: - Helper Methods

    private func handleMapTap(at coordinate: CLLocationCoordinate2D) {
        // Handle relocation mode
        if let relocating = viewModel.relocatingPoint {
            handleRelocation(to: coordinate, for: relocating)
            return
        }

        // Handle drop pin mode
        guard isDropPinMode else { return }
        viewModel.selectPoint(at: coordinate)
        isDropPinMode = false
    }

    private func handleRelocation(to coordinate: CLLocationCoordinate2D, for pointID: PointID) {
        switch pointID {
        case .pointA:
            viewModel.setPointA(coordinate: coordinate, contact: nil)
        case .pointB:
            viewModel.setPointB(coordinate: coordinate, contact: nil)
        case .repeater:
            viewModel.setRepeaterOffPath(coordinate: coordinate)
        }

        // Clear results and show Analyze button
        viewModel.clearAnalysisResults()
        viewModel.relocatingPoint = nil
        enableHalfDetent = true
        withAnimation {
            sheetDetent = analysisSheetDetentHalf
        }
    }

    private func handleAnalysisStatusChange(_ status: AnalysisStatus, showSheet: Bool) {
        switch status {
        case .result:
            if showSheet {
                sheetDetent = analysisSheetDetentExpanded
            }
        case .relayResult:
            break
        default:
            return
        }

        if viewModel.shouldAutoZoomOnNextResult {
            viewModel.shouldAutoZoomOnNextResult = false
            viewModel.zoomToShowBothPoints()
        }
    }

    private func handleRepeaterTap(_ contact: ContactDTO) {
        viewModel.toggleContact(contact)
    }
}

// MARK: - Map Canvas View

private struct LOSMapCanvasView: View {
    @Bindable var viewModel: LineOfSightViewModel
    let appState: AppState
    @Environment(\.colorScheme) private var colorScheme
    @Binding var mapStyleSelection: MapStyleSelection
    @Binding var showingMapStyleMenu: Bool
    @Binding var showLabels: Bool
    @Binding var isDropPinMode: Bool
    let mapOverlayBottomPadding: CGFloat
    let cameraBottomSheetFraction: CGFloat?
    let onRepeaterTap: (ContactDTO) -> Void
    let onMapTap: (CLLocationCoordinate2D) -> Void

    var body: some View {
        ZStack {
            MC1MapView(
                points: mapPoints,
                lines: mapLines,
                mapStyle: mapStyleSelection,
                isDarkMode: colorScheme == .dark,
                showLabels: showLabels,
                showsUserLocation: true,
                isInteractive: true,
                showsScale: true,
                cameraRegion: $viewModel.cameraRegion,
                cameraRegionVersion: viewModel.cameraRegionVersion,
                cameraBottomSheetFraction: cameraBottomSheetFraction,
                onPointTap: { point, _ in
                    if let repeater = viewModel.repeatersWithLocation.first(where: { $0.id == point.id }) {
                        onRepeaterTap(repeater)
                    }
                },
                onMapTap: onMapTap,
                onCameraRegionChange: { region in
                    viewModel.cameraRegion = region
                },
                isStyleLoaded: .constant(true)
            )
            .ignoresSafeArea()

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    MapControlsToolbar(
                        onLocationTap: {
                            Task {
                                if let location = try? await appState.locationService.requestCurrentLocation() {
                                    viewModel.cameraRegion = MKCoordinateRegion(
                                        center: location.coordinate,
                                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                                    )
                                    viewModel.cameraRegionVersion += 1
                                }
                            }
                        },
                        showingLayersMenu: $showingMapStyleMenu
                    ) {
                        Button(showLabels ? L10n.Map.Map.Controls.hideLabels : L10n.Map.Map.Controls.showLabels, systemImage: "character.textbox") {
                            showLabels.toggle()
                        }
                        .font(.body.weight(.medium))
                        .foregroundStyle(showLabels ? .blue : .primary)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                        .buttonStyle(.plain)
                        .labelStyle(.iconOnly)

                        Button(isDropPinMode ? L10n.Tools.Tools.LineOfSight.cancelDropPin : L10n.Tools.Tools.LineOfSight.dropPin, systemImage: isDropPinMode ? "mappin.slash" : "mappin") {
                            isDropPinMode.toggle()
                        }
                        .font(.body.weight(.medium))
                        .foregroundStyle(isDropPinMode ? .blue : .primary)
                        .frame(width: 44, height: 44)
                        .contentShape(.rect)
                        .buttonStyle(.plain)
                        .labelStyle(.iconOnly)
                    }
                }
            }
            .padding(.bottom, mapOverlayBottomPadding)

            if showingMapStyleMenu {
                Button {
                    withAnimation { showingMapStyleMenu = false }
                } label: {
                    Color.primary.opacity(0.3).ignoresSafeArea()
                }
                .buttonStyle(.plain)

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        LayersMenu(
                            selection: $mapStyleSelection,
                            isPresented: $showingMapStyleMenu
                        )
                        .padding(.trailing)
                    }
                }
                .padding(.bottom, mapOverlayBottomPadding)
            }
        }
    }

    // MARK: - Map Data

    private var mapPoints: [MapPoint] {
        var points: [MapPoint] = []

        let selectionState = viewModel.selectionState
        for repeater in viewModel.repeatersWithLocation {
            let selectedAs = selectionState[repeater.id]?.selectedAs
            let style: MapPoint.PinStyle = switch selectedAs {
            case .pointA: .repeaterRingBlue
            case .pointB: .repeaterRingGreen
            case .repeater, nil: .repeater
            }
            points.append(MapPoint(
                id: repeater.id,
                coordinate: repeater.coordinate,
                pinStyle: style,
                label: showLabels ? repeater.displayName : nil,
                isClusterable: selectedAs == nil,
                hopIndex: nil,
                badgeText: nil
            ))
        }

        if let pointA = viewModel.pointA, pointA.contact == nil {
            points.append(MapPoint(
                id: viewModel.pointAMapID,
                coordinate: pointA.coordinate,
                pinStyle: .pointA,
                label: nil,
                isClusterable: false,
                hopIndex: nil,
                badgeText: nil
            ))
        }

        if let pointB = viewModel.pointB, pointB.contact == nil {
            points.append(MapPoint(
                id: viewModel.pointBMapID,
                coordinate: pointB.coordinate,
                pinStyle: .pointB,
                label: nil,
                isClusterable: false,
                hopIndex: nil,
                badgeText: nil
            ))
        }

        if let target = viewModel.repeaterPoint {
            points.append(MapPoint(
                id: viewModel.repeaterTargetMapID,
                coordinate: target.coordinate,
                pinStyle: .crosshair,
                label: nil,
                isClusterable: false,
                hopIndex: nil,
                badgeText: nil
            ))
        }

        return points
    }

    private var mapLines: [MapLine] {
        guard let a = viewModel.pointA?.coordinate,
              let b = viewModel.pointB?.coordinate else { return [] }

        let activeOpacity = 0.7
        let dimOpacity = 0.3

        if let r = viewModel.repeaterPoint?.coordinate {
            let opacityAR = viewModel.relocatingPoint == .pointA ? dimOpacity : activeOpacity
            let opacityRB = viewModel.relocatingPoint == .pointB ? dimOpacity : activeOpacity
            return [
                MapLine(id: "los-ar", coordinates: [a, r], style: .los,
                        opacity: viewModel.relocatingPoint == .repeater ? dimOpacity : opacityAR),
                MapLine(id: "los-rb", coordinates: [r, b], style: .los,
                        opacity: viewModel.relocatingPoint == .repeater ? dimOpacity : opacityRB)
            ]
        } else {
            let opacity = viewModel.relocatingPoint != nil ? dimOpacity : activeOpacity
            return [MapLine(id: "los-ab", coordinates: [a, b], style: .los, opacity: opacity)]
        }
    }
}

// MARK: - Frequency Input Row

/// Extracted view for frequency input with its own @FocusState
/// This is necessary because @FocusState doesn't work properly when declared in a parent view
/// and used in sheet content.
private struct FrequencyInputRow: View {
    @Bindable var viewModel: LineOfSightViewModel
    @FocusState private var isFocused: Bool
    @State private var text: String = ""

    var body: some View {
        HStack {
            Label(L10n.Tools.Tools.LineOfSight.frequency, systemImage: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.secondary)
            Spacer()
            TextField(L10n.Tools.Tools.LineOfSight.mhz, text: $text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .focused($isFocused)
                .onChange(of: isFocused) { _, focused in
                    if focused {
                        // Sync text from view model when gaining focus
                        text = formatForEditing(viewModel.frequencyMHz)
                    } else {
                        // Commit when focus is lost
                        commitEdit()
                    }
                }

            Text(L10n.Tools.Tools.LineOfSight.mhz)
                .foregroundStyle(.secondary)

            if isFocused {
                Button {
                    commitEdit()
                    isFocused = false
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
        }
        .onAppear {
            text = formatForEditing(viewModel.frequencyMHz)
        }
    }

    private func formatForEditing(_ value: Double) -> String {
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(value))
        } else {
            return value.formatted(.number.precision(.fractionLength(1)))
        }
    }

    private func commitEdit() {
        if let parsed = Double(text) {
            viewModel.frequencyMHz = parsed
            viewModel.commitFrequencyChange()
        }
    }
}

// MARK: - Preview

#Preview("Empty") {
    LineOfSightView()
        .environment(\.appState, AppState())
}

#Preview("With Contact") {
    let contact = ContactDTO(
        id: UUID(),
        deviceID: UUID(),
        publicKey: Data(repeating: 0x01, count: 32),
        name: "Test Contact",
        typeRawValue: 0,
        flags: 0,
        outPathLength: 0xFF,
        outPath: Data(),
        lastAdvertTimestamp: 0,
        latitude: 37.7749,
        longitude: -122.4194,
        lastModified: 0,
        nickname: nil,
        isBlocked: false,
        isMuted: false,
        isFavorite: false,
        lastMessageDate: nil,
        unreadCount: 0
    )

    LineOfSightView(preselectedContact: contact)
        .environment(\.appState, AppState())
}
