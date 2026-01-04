import CoreLocation
import MapKit
import PocketMeshServices
import SwiftUI

private let analysisSheetDetentCollapsed: PresentationDetent = .fraction(0.25)
private let analysisSheetDetentHalf: PresentationDetent = .fraction(0.5)
private let analysisSheetDetentExpanded: PresentationDetent = .large
private let analysisSheetBottomInsetPadding: CGFloat = 16

// MARK: - PointID Identifiable Conformance

extension PointID: Identifiable {
    var id: Self { self }
}

// MARK: - Map Style Selection

/// Wrapper enum for MapStyle that conforms to Hashable for use with Picker
private enum MapStyleSelection: String, CaseIterable, Hashable {
    case standard
    case satellite
    case hybrid

    var mapStyle: MapStyle {
        switch self {
        case .standard: .standard
        case .satellite: .imagery
        case .hybrid: .hybrid
        }
    }

    var label: String {
        switch self {
        case .standard: "Standard"
        case .satellite: "Satellite"
        case .hybrid: "Hybrid"
        }
    }

    var icon: String {
        switch self {
        case .standard: "map"
        case .satellite: "globe"
        case .hybrid: "square.stack.3d.up"
        }
    }
}

// MARK: - Line of Sight View

/// Full-screen map view for analyzing line-of-sight between two points
struct LineOfSightView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var viewModel: LineOfSightViewModel
    @State private var sheetDetent: PresentationDetent = analysisSheetDetentCollapsed
    @State private var screenHeight: CGFloat = 0
    @State private var showAnalysisSheet = true
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var editingPoint: PointID?
    @State private var isDropPinMode = false
    @State private var mapStyleSelection: MapStyleSelection = .standard
    @State private var sheetBottomInset: CGFloat = 220
    @State private var isResultsExpanded = false
    @State private var isInitialPointBZoom = false
    @Namespace private var mapScope

    // MARK: - Initialization

    init(preselectedContact: ContactDTO? = nil) {
        _viewModel = State(initialValue: LineOfSightViewModel(preselectedContact: preselectedContact))
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            mapLayer

            // Dismiss button (top-left)
            VStack {
                HStack {
                    dismissButton
                    Spacer()
                }
                Spacer()
            }

            // Scale view (bottom-left, above sheet)
            VStack {
                Spacer()
                HStack {
                    MapScaleView(scope: mapScope)
                        .padding()
                    Spacer()
                }
            }
            .padding(.bottom, sheetBottomInset)

            // Map controls (bottom-right, above sheet)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    mapControlsStack
                }
            }
            .padding(.bottom, sheetBottomInset)
        }
        .mapScope(mapScope)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            screenHeight = height
            updateSheetBottomInset()
        }
        .onChange(of: sheetDetent) { _, _ in
            updateSheetBottomInset()
        }
        .sheet(isPresented: $showAnalysisSheet) {
            analysisSheet
                .presentationDetents(
                    [analysisSheetDetentCollapsed, analysisSheetDetentHalf, analysisSheetDetentExpanded],
                    selection: $sheetDetent
                )
                .presentationDragIndicator(.visible)
                .presentationBackgroundInteraction(.enabled)
                .interactiveDismissDisabled()
        }
        .onChange(of: viewModel.pointA) { oldValue, newValue in
            // Zoom when both points become set (A was just added while B exists)
            if oldValue == nil, newValue != nil, viewModel.pointB != nil {
                isInitialPointBZoom = true
                withAnimation {
                    sheetDetent = analysisSheetDetentHalf
                }
                zoomToShowBothPoints()
            }
            // Collapse sheet when both points cleared
            if newValue == nil, viewModel.pointB == nil {
                withAnimation {
                    sheetDetent = analysisSheetDetentCollapsed
                }
            }
        }
        .onChange(of: viewModel.pointB) { oldValue, newValue in
            // Zoom when both points become set (B was just added while A exists)
            if oldValue == nil, newValue != nil, viewModel.pointA != nil {
                isInitialPointBZoom = true
                withAnimation {
                    sheetDetent = analysisSheetDetentHalf
                }
                zoomToShowBothPoints()
            }
            // Collapse sheet when both points cleared
            if newValue == nil, viewModel.pointA == nil {
                withAnimation {
                    sheetDetent = analysisSheetDetentCollapsed
                }
            }
        }
        .onChange(of: sheetDetent) { oldValue, newValue in
            // Clear zoom padding when user changes sheet after initial zoom
            if isInitialPointBZoom, oldValue == analysisSheetDetentHalf, newValue != analysisSheetDetentHalf {
                isInitialPointBZoom = false
            }
        }
        .onChange(of: viewModel.analysisStatus) { _, newStatus in
            handleAnalysisStatusChange(newStatus)
        }
        .task {
            appState.locationService.requestPermissionIfNeeded()
            viewModel.configure(appState: appState)
            await viewModel.loadRepeaters()
            centerOnAllRepeaters()
        }
    }

    // MARK: - Map Layer

    @State private var mapProxy: MapProxy?

    private var mapLayer: some View {
        MapReader { proxy in
            Map(position: $cameraPosition, scope: mapScope) {
                // Repeater annotations
                ForEach(viewModel.repeatersWithLocation) { contact in
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
                                selectedAs: viewModel.isContactSelected(contact)
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
                    }
                    .annotationTitles(.hidden)
                }

                // Point B annotation (only if dropped pin, not contact)
                if let pointB = viewModel.pointB, pointB.contact == nil {
                    Annotation("Point B", coordinate: pointB.coordinate) {
                        PointMarker(label: "B", color: .green)
                    }
                    .annotationTitles(.hidden)
                }

                // Path line connecting A and B
                if let pointA = viewModel.pointA, let pointB = viewModel.pointB {
                    MapPolyline(coordinates: [pointA.coordinate, pointB.coordinate])
                        .stroke(.blue.opacity(0.7), style: StrokeStyle(lineWidth: 3, dash: [8, 4]))
                }
            }
            .mapStyle(mapStyleSelection.mapStyle)
            .mapControls {
                MapCompass(scope: mapScope)
            }
            .safeAreaPadding(.bottom, isInitialPointBZoom ? sheetBottomInset : 0)
            .onAppear { mapProxy = proxy }
            .onTapGesture { position in
                if isDropPinMode {
                    handleMapTap(at: position)
                }
            }
        }
    }

    // MARK: - Dismiss Button

    private var dismissButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(.regularMaterial, in: .circle)
        }
        .padding()
    }

    // MARK: - Map Controls Stack

    private var mapControlsStack: some View {
        VStack(spacing: 0) {
            // User location button
            MapUserLocationButton(scope: mapScope)

            Divider()
                .frame(width: 36)

            // Map style picker
            mapStyleButton

            Divider()
                .frame(width: 36)

            // Drop pin toggle
            dropPinButton
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: .rect(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        .padding()
    }

    private var mapStyleButton: some View {
        Menu {
            Picker("Map Style", selection: $mapStyleSelection) {
                ForEach(MapStyleSelection.allCases, id: \.self) { style in
                    Label(style.label, systemImage: style.icon).tag(style)
                }
            }
        } label: {
            Image(systemName: "square.3.layers.3d.down.right")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel("Map style")
    }

    private var dropPinButton: some View {
        Button {
            isDropPinMode.toggle()
        } label: {
            Image(systemName: isDropPinMode ? "mappin.slash" : "mappin")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isDropPinMode ? .blue : .primary)
                .frame(width: 44, height: 44)
        }
        .accessibilityLabel(isDropPinMode ? "Cancel drop pin" : "Drop pin")
    }

    // MARK: - Analysis Sheet

    private var analysisSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    pointsSummarySection

                    // Before analysis: show RF settings, then analyze button
                    if viewModel.canAnalyze, !hasAnalysisResult {
                        rfSettingsSection
                        analyzeButtonSection
                    }

                    // After analysis: show button, results, terrain, then RF settings
                    if case .result(let result) = viewModel.analysisStatus {
                        analyzeButtonSection

                        resultSummarySection(result)

                        if sheetDetent != analysisSheetDetentCollapsed {
                            terrainProfileSection
                        }

                        if sheetDetent == analysisSheetDetentExpanded {
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
                .padding()
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationBarHidden(true)
        }
    }

    // MARK: - Points Summary Section

    private var pointsSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Points")
                .font(.headline)

            // Point A row
            pointRow(
                label: "A",
                color: .blue,
                point: viewModel.pointA,
                pointID: .pointA,
                onClear: { viewModel.clearPointA() }
            )

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

                    // Edit/Done toggle button
                    Button(isEditing ? "Done" : "Edit", systemImage: isEditing ? "checkmark" : "pencil") {
                        withAnimation {
                            editingPoint = isEditing ? nil : pointID
                        }
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    // Clear button
                    Button("Clear", systemImage: "xmark") {
                        onClear()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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
        .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
        .animation(.easeInOut(duration: 0.2), value: isEditing)
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

    // MARK: - Analyze Button Section

    private var analyzeButtonSection: some View {
        Button {
            withAnimation {
                sheetDetent = analysisSheetDetentExpanded
            }
            viewModel.analyze()
        } label: {
            Label("Analyze Path", systemImage: "waveform.path")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
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
                elevationProfile: viewModel.elevationProfile,
                pointAHeight: Double(viewModel.pointA?.additionalHeight ?? 0),
                pointBHeight: Double(viewModel.pointB?.additionalHeight ?? 0),
                frequencyMHz: viewModel.frequencyMHz,
                refractionK: viewModel.refractionK
            )
        }
    }

    // MARK: - RF Settings Section

    private var rfSettingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RF Settings")
                .font(.headline)

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
            .padding()
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 8))
        }
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
                viewModel.analyze()
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
        analysisResult != nil
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

        sheetBottomInset = screenHeight * fraction + analysisSheetBottomInsetPadding
    }

    private func handleMapTap(at position: CGPoint) {
        guard let proxy = mapProxy,
              let coordinate = proxy.convert(position, from: .local) else { return }

        // Provide haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // Select the point and exit drop pin mode
        viewModel.selectPoint(at: coordinate)
        isDropPinMode = false
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

    private func handleAnalysisStatusChange(_ status: AnalysisStatus) {
        if case .result = status {
            withAnimation {
                sheetDetent = analysisSheetDetentExpanded
            }
            zoomToShowBothPoints()
        }
    }

    private func zoomToShowBothPoints() {
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

        cameraPosition = .region(region)
    }

    private func handleRepeaterTap(_ contact: ContactDTO) {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()

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

// MARK: - Preview

#Preview("Empty") {
    LineOfSightView()
        .environment(AppState())
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
        isFavorite: false,
        isDiscovered: false,
        lastMessageDate: nil,
        unreadCount: 0
    )

    return LineOfSightView(preselectedContact: contact)
        .environment(AppState())
}
