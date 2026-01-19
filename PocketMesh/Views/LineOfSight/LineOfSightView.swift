import CoreLocation
import MapKit
import PocketMeshServices
import SwiftUI

private let analysisSheetDetentCollapsed: PresentationDetent = .fraction(0.25)
private let analysisSheetDetentHalf: PresentationDetent = .fraction(0.5)
private let analysisSheetDetentExpanded: PresentationDetent = .large
private let analysisSheetBottomInsetPadding: CGFloat = 16

enum LineOfSightLayoutMode {
    case map
    case panel
    case mapWithSheet
}

// MARK: - PointID Identifiable Conformance

extension PointID: Identifiable {
    var id: Self { self }
}

// MARK: - Map Style Selection

/// Wrapper enum for MapStyle that conforms to Hashable for use with Picker
private enum LOSMapStyleSelection: String, CaseIterable, Hashable {
    case standard
    case satellite
    case terrain

    var mapStyle: MapStyle {
        switch self {
        case .standard: .standard
        case .satellite: .imagery
        case .terrain: .hybrid(elevation: .realistic)
        }
    }

    var label: String {
        switch self {
        case .standard: "Standard"
        case .satellite: "Satellite"
        case .terrain: "Terrain"
        }
    }

    var icon: String {
        switch self {
        case .standard: "map"
        case .satellite: "globe"
        case .terrain: "mountain.2"
        }
    }
}

// MARK: - Line of Sight View

/// Full-screen map view for analyzing line-of-sight between two points
struct LineOfSightView: View {
    @Environment(\.appState) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: LineOfSightViewModel
    @State private var sheetDetent: PresentationDetent = analysisSheetDetentCollapsed
    @State private var screenHeight: CGFloat = 0
    @State private var baseScreenHeight: CGFloat = 0
    @State private var showAnalysisSheet: Bool
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var editingPoint: PointID?
    @State private var isDropPinMode = false
    @State private var mapStyleSelection: LOSMapStyleSelection = .terrain
    @State private var sheetBottomInset: CGFloat = 220
    @State private var isResultsExpanded = false
    @State private var isInitialPointBZoom = false
    @State private var isRFSettingsExpanded = false
    @State private var showingMapStyleMenu = false
    @Namespace private var mapScope

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
        let base = mapCanvas
            .mapScope(mapScope)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height
            } action: { height in
                if height > 0 {
                    screenHeight = height

                    if baseScreenHeight == 0 || height > baseScreenHeight || height < baseScreenHeight * 0.7 {
                        baseScreenHeight = height
                    }
                }

                if showSheet, showAnalysisSheet {
                    updateSheetBottomInset()
                }
            }
            .onChange(of: sheetDetent) { _, _ in
                if showSheet, showAnalysisSheet {
                    updateSheetBottomInset()
                }
            }
            .onChange(of: viewModel.pointA) { oldValue, newValue in
                if oldValue == nil, newValue != nil, viewModel.pointB != nil {
                    if showSheet {
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

                if isInitialPointBZoom, oldValue == analysisSheetDetentHalf, newValue != analysisSheetDetentHalf {
                    isInitialPointBZoom = false
                }

                if isRelocating, newValue != analysisSheetDetentCollapsed {
                    viewModel.relocatingPoint = nil
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
                centerOnAllRepeaters()
            }

        if showSheet {
            base
                .navigationBarBackButtonHidden(true)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismissLineOfSight()
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                                .labelStyle(.titleAndIcon)
                        }
                        .accessibilityLabel("Back")
                    }
                }
                .liquidGlassToolbarBackground()
                .onDisappear {
                    showAnalysisSheet = false
                }
                .sheet(isPresented: $showAnalysisSheet) {
                    analysisSheet
                        .presentationDetents(
                            [analysisSheetDetentCollapsed, analysisSheetDetentHalf, analysisSheetDetentExpanded],
                            selection: $sheetDetent
                        )
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

    private var mapCanvas: some View {
        ZStack {
            mapLayer
                .ignoresSafeArea()

            VStack {
                Spacer()
                HStack {
                    MapScaleView(scope: mapScope)
                        .padding()
                    Spacer()
                }
            }
            .padding(.bottom, mapOverlayBottomPadding)

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    mapControlsStack
                }
            }
            .padding(.bottom, mapOverlayBottomPadding)

            if showingMapStyleMenu {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation {
                            showingMapStyleMenu = false
                        }
                    }

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VStack(spacing: 0) {
                            ForEach(LOSMapStyleSelection.allCases, id: \.self) { style in
                                Button {
                                    mapStyleSelection = style
                                    withAnimation {
                                        showingMapStyleMenu = false
                                    }
                                } label: {
                                    HStack {
                                        Text(style.label)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        if mapStyleSelection == style {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                }

                                if style != LOSMapStyleSelection.allCases.last {
                                    Divider()
                                }
                            }
                        }
                        .frame(width: 140)
                        .background(.regularMaterial, in: .rect(cornerRadius: 12))
                        .shadow(radius: 8)
                        .padding(.trailing)
                    }
                }
                .padding(.bottom, mapOverlayBottomPadding)
            }
        }
    }

    // MARK: - Map Layer

    @State private var mapProxy: MapProxy?

    private func markerOpacity(for pointID: PointID) -> Double {
        guard let relocating = viewModel.relocatingPoint else { return 1.0 }
        return relocating == pointID ? 0.4 : 1.0
    }

    private func lineOpacity(connectsTo pointID: PointID) -> Double {
        guard let relocating = viewModel.relocatingPoint else { return 0.7 }

        // When relocating repeater, both lines dim
        if relocating == .repeater { return 0.3 }

        // When relocating A or B, dim lines connected to that point
        switch pointID {
        case .pointA:
            return relocating == .pointA ? 0.3 : 0.7
        case .pointB:
            return relocating == .pointB ? 0.3 : 0.7
        case .repeater:
            return 0.7
        }
    }

    private var mapLayer: some View {
        MapReader { proxy in
            Map(position: $cameraPosition, scope: mapScope) {
                // Repeater annotations
                ForEach(viewModel.repeatersWithLocation) { contact in
                    let selectedAs = viewModel.isContactSelected(contact)
                    Annotation(
                        contact.displayName,
                        coordinate: contact.coordinate,
                        anchor: .bottom
                    ) {
                        Button {
                            handleRepeaterTap(contact)
                        } label: {
                            RepeaterAnnotationView(
                                contact: contact,
                                selectedAs: selectedAs,
                                opacity: selectedAs.map { markerOpacity(for: $0) } ?? 1.0
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .annotationTitles(.hidden)
                }

                // Point A annotation (only if dropped pin, not contact)
                if let pointA = viewModel.pointA, pointA.contact == nil {
                    Annotation("Point A", coordinate: pointA.coordinate) {
                        PointMarker(label: "A", color: .blue)
                            .opacity(markerOpacity(for: .pointA))
                    }
                    .annotationTitles(.hidden)
                }

                // Point B annotation (only if dropped pin, not contact)
                if let pointB = viewModel.pointB, pointB.contact == nil {
                    Annotation("Point B", coordinate: pointB.coordinate) {
                        PointMarker(label: "B", color: .green)
                            .opacity(markerOpacity(for: .pointB))
                    }
                    .annotationTitles(.hidden)
                }

                // Simulated repeater annotation (crosshairs target)
                if let repeaterPoint = viewModel.repeaterPoint {
                    Annotation("Repeater", coordinate: repeaterPoint.coordinate) {
                        RepeaterTargetMarker()
                            .opacity(markerOpacity(for: .repeater))
                    }
                    .annotationTitles(.hidden)
                }

                // Path lines connecting A, R, and B
                if let pointA = viewModel.pointA, let pointB = viewModel.pointB {
                    if let repeaterPoint = viewModel.repeaterPoint {
                        // Two segments: A→R and R→B
                        MapPolyline(coordinates: [pointA.coordinate, repeaterPoint.coordinate])
                            .stroke(.blue.opacity(lineOpacity(connectsTo: .pointA)), style: StrokeStyle(lineWidth: 3, dash: [8, 4]))
                        MapPolyline(coordinates: [repeaterPoint.coordinate, pointB.coordinate])
                            .stroke(.blue.opacity(lineOpacity(connectsTo: .pointB)), style: StrokeStyle(lineWidth: 3, dash: [8, 4]))
                    } else {
                        // Single segment: A→B - dims if either A or B is relocating
                        let opacity = (viewModel.relocatingPoint == .pointA || viewModel.relocatingPoint == .pointB) ? 0.3 : 0.7
                        MapPolyline(coordinates: [pointA.coordinate, pointB.coordinate])
                            .stroke(.blue.opacity(opacity), style: StrokeStyle(lineWidth: 3, dash: [8, 4]))
                    }
                }
            }
            .mapStyle(mapStyleSelection.mapStyle)
            .mapControls {
                MapCompass(scope: mapScope)
            }
            .safeAreaPadding(.bottom, isInitialPointBZoom ? sheetBottomInset : 0)
            .onAppear { mapProxy = proxy }
            // Use simultaneousGesture to handle map taps without blocking:
            // 1. Map's built-in pan/zoom gestures
            // 2. Annotation button taps (iOS 18 fix)
            .simultaneousGesture(
                SpatialTapGesture()
                    .onEnded { value in
                        if isRelocating || isDropPinMode {
                            handleMapTap(at: value.location)
                        }
                    }
            )
        }
    }

    // MARK: - Map Controls Stack

    private var mapControlsStack: some View {
        MapControlsToolbar(
            mapScope: mapScope,
            showingLayersMenu: $showingMapStyleMenu
        ) {
            dropPinButton
        }
    }

    private var dropPinButton: some View {
        Button {
            isDropPinMode.toggle()
        } label: {
            Image(systemName: isDropPinMode ? "mappin.slash" : "mappin")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isDropPinMode ? .blue : .primary)
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isDropPinMode ? "Cancel drop pin" : "Drop pin")
    }

    // MARK: - Analysis Sheet

    private var analysisSheet: some View {
        NavigationStack {
            ScrollView {
                analysisSheetContent
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationBarHidden(true)
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

            if case .loading = viewModel.analysisStatus {
                loadingSection
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
                Text("Points")
                    .font(.headline)

                Spacer()

                if isRelocating {
                    Button("Cancel") {
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
                    Text("Tap the pin button on the map to select points")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if viewModel.elevationFetchFailed {
                    Label(
                        "Elevation data unavailable. Using sea level (0m) as approximation.",
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
        case .pointA: "Point A"
        case .pointB: "Point B"
        case .repeater: "Repeater"
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("Relocating \(pointName)...")
                .font(.subheadline)
                .bold()

            Text("Tap the map to set a new location")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Relocating \(pointName). Tap the map to set a new location.")
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
                                Text("Loading elevation...")
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
                    Text("Not selected")
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
                Button("Open in Maps", systemImage: "map") {
                    let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coord))
                    mapItem.name = pointID == .pointA ? "Point A" : "Point B"
                    mapItem.openInMaps()
                }

                Button("Copy Coordinates", systemImage: "doc.on.doc") {
                    let coordText = "\(coord.latitude.formatted(.number.precision(.fractionLength(6)))), \(coord.longitude.formatted(.number.precision(.fractionLength(6))))"
                    UIPasteboard.general.string = coordText
                }

                let coordText = "\(coord.latitude.formatted(.number.precision(.fractionLength(6)))), \(coord.longitude.formatted(.number.precision(.fractionLength(6))))"
                ShareLink(item: coordText) {
                    Label("Share...", systemImage: "square.and.arrow.up")
                }
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
                .labelStyle(.iconOnly)
        }
        .glassButtonStyle()
        .controlSize(.small)

        // Relocate button (toggles on/off)
        Button("Relocate", systemImage: "mappin") {
            if viewModel.relocatingPoint == pointID {
                viewModel.relocatingPoint = nil
            } else {
                viewModel.relocatingPoint = pointID
                withAnimation {
                    sheetDetent = analysisSheetDetentCollapsed
                }
            }
        }
        .labelStyle(.iconOnly)
        .glassButtonStyle()
        .controlSize(.small)
        .disabled(viewModel.relocatingPoint != nil && viewModel.relocatingPoint != pointID)

        // Edit/Done toggle
        Button(isEditing ? "Done" : "Edit", systemImage: isEditing ? "checkmark" : "pencil") {
            withAnimation {
                editingPoint = isEditing ? nil : pointID
            }
        }
        .labelStyle(.iconOnly)
        .glassButtonStyle()
        .controlSize(.small)

        // Clear button
        Button("Clear", systemImage: "xmark", action: onClear)
            .labelStyle(.iconOnly)
            .glassButtonStyle()
            .controlSize(.small)
    }

    @ViewBuilder
    private func pointHeightEditor(point: SelectedPoint, pointID: PointID) -> some View {
        Grid(alignment: .leading, verticalSpacing: 8) {
            // Ground elevation row
            GridRow {
                Text("Ground elevation")
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
                Text("Additional height")
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
                    Text("Total height")
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
                    Text("Repeater")
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
                        Button("Open in Maps", systemImage: "map") {
                            let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coord))
                            mapItem.name = "Repeater Location"
                            mapItem.openInMaps()
                        }

                        Button("Copy Coordinates", systemImage: "doc.on.doc") {
                            let coordText = "\(coord.latitude.formatted(.number.precision(.fractionLength(6)))), \(coord.longitude.formatted(.number.precision(.fractionLength(6))))"
                            UIPasteboard.general.string = coordText
                        }

                        let coordText = "\(coord.latitude.formatted(.number.precision(.fractionLength(6)))), \(coord.longitude.formatted(.number.precision(.fractionLength(6))))"
                        ShareLink(item: coordText) {
                            Label("Share...", systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .labelStyle(.iconOnly)
                }
                .glassButtonStyle()
                .controlSize(.small)

                // Relocate button (toggles on/off)
                Button("Relocate", systemImage: "mappin") {
                    if viewModel.relocatingPoint == .repeater {
                        viewModel.relocatingPoint = nil
                    } else {
                        viewModel.relocatingPoint = .repeater
                        withAnimation {
                            sheetDetent = analysisSheetDetentCollapsed
                        }
                    }
                }
                .labelStyle(.iconOnly)
                .glassButtonStyle()
                .controlSize(.small)
                .disabled(viewModel.relocatingPoint != nil && viewModel.relocatingPoint != .repeater)

                // Edit/Done toggle
                Button(isEditing ? "Done" : "Edit", systemImage: isEditing ? "checkmark" : "pencil") {
                    withAnimation {
                        editingPoint = isEditing ? nil : .repeater
                    }
                }
                .labelStyle(.iconOnly)
                .glassButtonStyle()
                .controlSize(.small)

                // Clear button
                Button("Clear", systemImage: "xmark") {
                    viewModel.clearRepeater()
                }
                .labelStyle(.iconOnly)
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
                    Text("Ground elevation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(groundElevation)) m")
                        .font(.caption)
                        .monospacedDigit()
                }
            }

            GridRow {
                Text("Additional height")
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
                    Text("Total height")
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

                Text("Add Repeater")
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
            Label("Analyze Line of Sight", systemImage: "waveform.path")
                .frame(maxWidth: .infinity)
        }
        .glassProminentButtonStyle()
        .controlSize(.large)
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
                Text("Terrain Profile")
                    .font(.headline)

                Spacer()

                Label(
                    "Adjusted for earth curvature (\(LOSFormatters.formatKFactor(viewModel.refractionK)))",
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
                    Text("Drag to adjust")
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
                    Label("Refraction", systemImage: "globe")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { viewModel.refractionK },
                        set: { viewModel.refractionK = $0 }
                    )) {
                        Text("None").tag(1.0)
                        Text("Standard (k=1.33)").tag(4.0 / 3.0)
                        Text("Ducting (k=4)").tag(4.0)
                    }
                    .pickerStyle(.menu)
                }
            }
            .padding(.top, 8)
        } label: {
            Label("RF Settings", systemImage: "antenna.radiowaves.left.and.right")
                .font(.headline)
        }
        .tint(.primary)
    }

    // MARK: - Loading Section

    private var loadingSection: some View {
        HStack {
            Spacer()
            ProgressView("Analyzing path...")
            Spacer()
        }
        .padding()
    }

    // MARK: - Error Section

    private func errorSection(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)

            Text("Analysis Failed")
                .font(.headline)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Retry") {
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

    private func updateSheetBottomInset() {
        let fraction: CGFloat
        if sheetDetent == analysisSheetDetentExpanded {
            // When fullscreen, map is covered - cap inset at 0.9 to avoid layout issues
            fraction = 0.9
        } else if sheetDetent == analysisSheetDetentHalf {
            fraction = 0.5
        } else {
            fraction = 0.25
        }

        let referenceHeight = baseScreenHeight > 0 ? baseScreenHeight : screenHeight
        guard referenceHeight > 0 else { return }

        sheetBottomInset = referenceHeight * fraction + analysisSheetBottomInsetPadding
    }

    private func handleMapTap(at position: CGPoint) {
        guard let proxy = mapProxy,
              let coordinate = proxy.convert(position, from: .local) else { return }

        // Handle relocation mode
        if let relocating = viewModel.relocatingPoint {
            handleRelocation(to: coordinate, for: relocating)
            return
        }

        // Handle drop pin mode (existing behavior)
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
        withAnimation {
            sheetDetent = analysisSheetDetentHalf
        }
    }

    private func centerOnAllRepeaters() {
        let repeaters = viewModel.repeatersWithLocation
        guard !repeaters.isEmpty else {
            cameraPosition = .automatic
            return
        }

        // Calculate bounding region
        var minLat = Double.greatestFiniteMagnitude
        var maxLat = -Double.greatestFiniteMagnitude
        var minLon = Double.greatestFiniteMagnitude
        var maxLon = -Double.greatestFiniteMagnitude

        for contact in repeaters {
            let lat = contact.latitude
            let lon = contact.longitude
            minLat = min(minLat, lat)
            maxLat = max(maxLat, lat)
            minLon = min(minLon, lon)
            maxLon = max(maxLon, lon)
        }

        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2
        let latDelta = max(0.01, (maxLat - minLat) * 1.5)
        let lonDelta = max(0.01, (maxLon - minLon) * 1.5)

        let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
        let span = MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
        let region = MKCoordinateRegion(center: center, span: span)

        cameraPosition = .region(region)
    }

    private func handleAnalysisStatusChange(_ status: AnalysisStatus, showSheet: Bool) {
        switch status {
        case .result:
            if showSheet {
                withAnimation {
                    sheetDetent = analysisSheetDetentExpanded
                }
            }
            if viewModel.shouldAutoZoomOnNextResult {
                viewModel.shouldAutoZoomOnNextResult = false
                zoomToShowBothPoints()
            }
        case .relayResult:
            if viewModel.shouldAutoZoomOnNextResult {
                viewModel.shouldAutoZoomOnNextResult = false
                zoomToShowBothPoints()
            }
        default:
            break
        }
    }

    /// Zooms the map to show both points A and B with comfortable padding.
    /// Uses Task.yield() to wait for SwiftUI layout updates (sheet resizing) to complete
    /// before calculating the visible region, ensuring accurate zoom positioning.
    private func zoomToShowBothPoints() {
        Task { @MainActor in
            await Task.yield()
            if Task.isCancelled { return }

            guard let pointA = viewModel.pointA, let pointB = viewModel.pointB else { return }

            let minLat = min(pointA.coordinate.latitude, pointB.coordinate.latitude)
            let maxLat = max(pointA.coordinate.latitude, pointB.coordinate.latitude)
            let minLon = min(pointA.coordinate.longitude, pointB.coordinate.longitude)
            let maxLon = max(pointA.coordinate.longitude, pointB.coordinate.longitude)

            let centerLat = (minLat + maxLat) / 2
            let centerLon = (minLon + maxLon) / 2

            // Add padding for comfortable viewing (1.5x the span)
            let paddingMultiplier = 1.5
            let latDelta = max(0.01, (maxLat - minLat) * paddingMultiplier)
            let lonDelta = max(0.01, (maxLon - minLon) * paddingMultiplier)

            // safeAreaPadding on the Map handles the sheet offset automatically
            let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
            let span = MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
            let region = MKCoordinateRegion(center: center, span: span)

            var transaction = Transaction(animation: .easeInOut(duration: 1.0))
            transaction.disablesAnimations = false
            withTransaction(transaction) {
                cameraPosition = .region(region)
            }
        }
    }

    private func handleRepeaterTap(_ contact: ContactDTO) {
        viewModel.toggleContact(contact)
    }
}

// MARK: - Point Marker View

/// Circle marker with a label for map annotations
private struct PointMarker: View {
    let label: String
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 32, height: 32)

            Text(label)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
        }
        .shadow(color: .black.opacity(0.3), radius: 2, y: 2)
    }
}

// MARK: - Repeater Annotation View

/// Annotation view for repeaters that shows selection state
private struct RepeaterAnnotationView: View {
    let contact: ContactDTO
    let selectedAs: PointID?
    var opacity: Double = 1.0

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Background circle
                Circle()
                    .fill(.green)
                    .frame(width: circleSize, height: circleSize)

                // Selection ring with point label
                if let selectedAs {
                    Circle()
                        .stroke(ringColor(for: selectedAs), lineWidth: 3)
                        .frame(width: circleSize, height: circleSize)
                }

                // Icon
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.3), radius: 2, y: 2)

            // Point label when selected
            if let selectedAs {
                Text(selectedAs == .pointA ? "A" : "B")
                    .font(.caption2)
                    .bold()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(ringColor(for: selectedAs), in: .capsule)
                    .offset(y: 4)
            }
        }
        .opacity(opacity)
        .animation(.easeInOut(duration: 0.2), value: selectedAs)
    }

    private var circleSize: CGFloat {
        selectedAs != nil ? 40 : 32
    }

    private var iconSize: CGFloat {
        selectedAs != nil ? 18 : 14
    }

    private func ringColor(for pointID: PointID) -> Color {
        pointID == .pointA ? .blue : .green
    }
}

// MARK: - Repeater Target Marker

/// Crosshairs marker for simulated repeater placement on the map.
/// The coordinate anchor is at the center of the crosshairs.
private struct RepeaterTargetMarker: View {
    private let size: CGFloat = 32
    private let crosshairExtension: CGFloat = 6

    var body: some View {
        crosshairs
            .frame(width: size + crosshairExtension * 2, height: size + crosshairExtension * 2)
            .shadow(color: .black.opacity(0.3), radius: 2, y: 2)
            .overlay(alignment: .bottom) {
                // Label below crosshairs
                Text("R")
                    .font(.caption2)
                    .bold()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.purple, in: .capsule)
                    .offset(y: 24)
            }
    }

    private var crosshairs: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let gapRadius: CGFloat = 4
            let outerRadius = size / 2 + crosshairExtension

            var path = Path()

            // Top
            path.move(to: CGPoint(x: center.x, y: center.y - outerRadius))
            path.addLine(to: CGPoint(x: center.x, y: center.y - gapRadius))

            // Bottom
            path.move(to: CGPoint(x: center.x, y: center.y + gapRadius))
            path.addLine(to: CGPoint(x: center.x, y: center.y + outerRadius))

            // Left
            path.move(to: CGPoint(x: center.x - outerRadius, y: center.y))
            path.addLine(to: CGPoint(x: center.x - gapRadius, y: center.y))

            // Right
            path.move(to: CGPoint(x: center.x + gapRadius, y: center.y))
            path.addLine(to: CGPoint(x: center.x + outerRadius, y: center.y))

            context.stroke(path, with: .color(.purple), lineWidth: 2)
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
            Label("Frequency", systemImage: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.secondary)
            Spacer()
            TextField("MHz", text: $text)
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

            Text("MHz")
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

// MARK: - Glass Button Style Helpers

extension View {
    @ViewBuilder
    func glassButtonStyle() -> some View {
        if #available(iOS 26, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    func glassProminentButtonStyle() -> some View {
        if #available(iOS 26, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
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
        outPathLength: -1,
        outPath: Data(),
        lastAdvertTimestamp: 0,
        latitude: 37.7749,
        longitude: -122.4194,
        lastModified: 0,
        nickname: nil,
        isBlocked: false,
        isMuted: false,
        isFavorite: false,
        isDiscovered: false,
        lastMessageDate: nil,
        unreadCount: 0
    )

    LineOfSightView(preselectedContact: contact)
        .environment(\.appState, AppState())
}
