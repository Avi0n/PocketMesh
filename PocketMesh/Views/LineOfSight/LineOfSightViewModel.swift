import CoreLocation
import PocketMeshServices
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.pocketmesh", category: "LineOfSight")

// MARK: - Point Identification

/// Identifies which point for editing in the UI
enum PointID: Hashable {
    case pointA
    case pointB
    case repeater
}

// MARK: - Repeater Point

/// A repeater point for relay analysis.
/// Can be on-path (from slider, uses cached profile) or off-path (relocated, needs fresh profiles).
struct RepeaterPoint: Equatable {
    /// The repeater's location
    var coordinate: CLLocationCoordinate2D

    /// Ground elevation at coordinate (fetched async)
    var groundElevation: Double?

    /// Additional height above ground in meters
    var additionalHeight: Int

    /// True if repeater is on the A-B path (from slider), false if relocated off-path
    var isOnPath: Bool

    /// Path fraction (only meaningful when isOnPath is true)
    /// Used for terrain profile slider positioning
    var pathFraction: Double {
        didSet {
            let clamped = pathFraction.clamped(to: 0.05...0.95)
            if clamped != pathFraction { pathFraction = clamped }
        }
    }

    init(coordinate: CLLocationCoordinate2D, groundElevation: Double? = nil, additionalHeight: Int = 10, isOnPath: Bool = true, pathFraction: Double = 0.5) {
        self.coordinate = coordinate
        self.groundElevation = groundElevation
        self.additionalHeight = additionalHeight
        self.isOnPath = isOnPath
        self.pathFraction = pathFraction.clamped(to: 0.05...0.95)
    }

    static func == (lhs: RepeaterPoint, rhs: RepeaterPoint) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude &&
        lhs.groundElevation == rhs.groundElevation &&
        lhs.additionalHeight == rhs.additionalHeight &&
        lhs.isOnPath == rhs.isOnPath &&
        lhs.pathFraction == rhs.pathFraction
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Selected Point

/// A selected point for line of sight analysis
struct SelectedPoint: Identifiable, Equatable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let contact: ContactDTO?
    var groundElevation: Double?
    var additionalHeight: Int = 7

    var totalHeight: Double? {
        groundElevation.map { $0 + Double(additionalHeight) }
    }

    var displayName: String {
        contact?.displayName ?? L10n.Tools.Tools.LineOfSight.droppedPin
    }

    var isLoadingElevation: Bool {
        groundElevation == nil
    }

    static func == (lhs: SelectedPoint, rhs: SelectedPoint) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Analysis Status

/// Current status of path analysis
enum AnalysisStatus: Equatable {
    case idle
    case loading
    case result(PathAnalysisResult)
    case relayResult(RelayPathAnalysisResult)
    case error(String)
}

// MARK: - View Model

@MainActor @Observable
final class LineOfSightViewModel {

    // MARK: - Point Selection State

    var pointA: SelectedPoint?
    var pointB: SelectedPoint?
    var relocatingPoint: PointID?
    var shouldAutoZoomOnNextResult = false

    // MARK: - RF Parameters

    /// Operating frequency in MHz - call `commitFrequencyChange()` after editing
    var frequencyMHz: Double = 906.0

    /// Refraction k-factor - auto-triggers re-analysis on change
    var refractionK: Double = 1.0 {
        didSet {
            if oldValue != refractionK {
                reanalyzeWithCachedProfileIfNeeded()
            }
        }
    }

    /// Commits frequency change and triggers re-analysis with cached profile
    func commitFrequencyChange() {
        reanalyzeWithCachedProfileIfNeeded()
    }

    // MARK: - Repeaters State

    private(set) var repeatersWithLocation: [ContactDTO] = []

    // MARK: - Repeater State

    /// The active repeater point (nil when not in use)
    var repeaterPoint: RepeaterPoint?

    /// Whether repeater row should be visible (analysis shows marginal or worse)
    var shouldShowRepeaterRow: Bool {
        // Always show if repeater exists (even after relocation clears results)
        if repeaterPoint != nil {
            return true
        }
        // Show placeholder when direct analysis is marginal or worse
        return shouldShowRepeaterPlaceholder
    }

    /// Whether to show the "Add Repeater" placeholder (no repeater exists, but analysis suggests one would help)
    var shouldShowRepeaterPlaceholder: Bool {
        guard case .result(let result) = analysisStatus else {
            return false
        }
        // Only show if there are obstruction points (required by addRepeater())
        return result.clearanceStatus != .clear && !result.obstructionPoints.isEmpty
    }

    /// Ground elevation at repeater position.
    /// For on-path: interpolated from cached A→B profile.
    /// For off-path: uses the fetched elevation stored in repeaterPoint.
    var repeaterGroundElevation: Double? {
        guard let repeaterPoint else { return nil }
        if repeaterPoint.isOnPath {
            return elevationAt(pathFraction: repeaterPoint.pathFraction)
        } else {
            return repeaterPoint.groundElevation
        }
    }

    /// Path fraction for repeater visualization in terrain profile
    /// For on-path: uses pathFraction directly
    /// For off-path: computes from A→R distance / total distance
    var repeaterVisualizationPathFraction: Double? {
        guard let repeaterPoint else { return nil }
        if repeaterPoint.isOnPath {
            return repeaterPoint.pathFraction
        }
        // For off-path, compute from stored profiles
        guard let arLast = elevationProfileAR.last,
              let rbLast = elevationProfileRB.last,
              rbLast.distanceFromAMeters > 0 else { return nil }
        return arLast.distanceFromAMeters / rbLast.distanceFromAMeters
    }

    /// Segment A→R distance in meters (nil when on-path or no repeater)
    var segmentARDistanceMeters: Double? {
        guard let repeaterPoint, !repeaterPoint.isOnPath else { return nil }
        guard case .relayResult(let result) = analysisStatus else { return nil }
        return result.segmentAR.distanceMeters
    }

    /// Segment R→B distance in meters (nil when on-path or no repeater)
    var segmentRBDistanceMeters: Double? {
        guard let repeaterPoint, !repeaterPoint.isOnPath else { return nil }
        guard case .relayResult(let result) = analysisStatus else { return nil }
        return result.segmentRB.distanceMeters
    }

    // MARK: - Analysis State

    private(set) var analysisStatus: AnalysisStatus = .idle
    private(set) var elevationProfile: [ElevationSample] = []

    /// Profile samples for primary segment (A→B or A→R when repeater active)
    private(set) var profileSamples: [ProfileSample] = []

    /// Profile samples for R→B segment (empty when no repeater)
    private(set) var profileSamplesRB: [ProfileSample] = []

    /// Elevation profile A→R for off-path repeater
    private(set) var elevationProfileAR: [ElevationSample] = []

    /// Elevation profile R→B for off-path repeater
    private(set) var elevationProfileRB: [ElevationSample] = []

    /// Tracks whether any point elevation fetch failed (using sea level fallback)
    private(set) var elevationFetchFailed = false

    // MARK: - Task Management

    private var analysisTask: Task<Void, Never>?
    private var pointAElevationTask: Task<Void, Never>?
    private var pointBElevationTask: Task<Void, Never>?

    // MARK: - Dependencies

    private let elevationService: ElevationServiceProtocol
    private var dataStore: (any PersistenceStoreProtocol)?
    private var deviceID: UUID?

    // MARK: - Computed Properties

    var canAnalyze: Bool {
        pointA?.groundElevation != nil && pointB?.groundElevation != nil
    }

    /// Returns the elevation profile to display in terrain visualization.
    /// For on-path or no repeater: returns cached A-B profile.
    /// For off-path: returns concatenated A→R→B profiles.
    var terrainElevationProfile: [ElevationSample] {
        guard let repeaterPoint, !repeaterPoint.isOnPath else {
            return elevationProfile
        }

        // For off-path repeater, concatenate A→R and R→B profiles
        // Note: elevationProfileRB already has distances adjusted (offset by AR distance)
        // from analyzeWithRepeaterOffPath(), so we use it directly without re-adjusting
        guard !elevationProfileAR.isEmpty, !elevationProfileRB.isEmpty else {
            return elevationProfile  // Fallback if off-path profiles not yet loaded
        }

        // dropFirst() removes the duplicate point at R (already in elevationProfileAR)
        return elevationProfileAR + Array(elevationProfileRB.dropFirst())
    }

    // MARK: - Initialization

    init(elevationService: ElevationServiceProtocol = ElevationService()) {
        self.elevationService = elevationService
    }

    convenience init(preselectedContact: ContactDTO?) {
        self.init()
        if let contact = preselectedContact, contact.hasLocation {
            let coordinate = CLLocationCoordinate2D(
                latitude: contact.latitude,
                longitude: contact.longitude
            )
            setPointA(coordinate: coordinate, contact: contact)
        }
    }

    // MARK: - Configuration

    func configure(appState: AppState) {
        // Use offline-capable data store and device ID to support browsing cached data when disconnected
        self.dataStore = appState.offlineDataStore
        self.deviceID = appState.currentDeviceID

        // Initialize frequency from connected device (stored in kHz, convert to MHz)
        if let deviceFrequencyKHz = appState.connectedDevice?.frequency {
            self.frequencyMHz = Double(deviceFrequencyKHz) / 1000.0
        }
    }

    func configure(dataStore: any PersistenceStoreProtocol, deviceID: UUID?) {
        self.dataStore = dataStore
        self.deviceID = deviceID
    }

    // MARK: - Load Repeaters

    func loadRepeaters() async {
        guard let dataStore, let deviceID else { return }

        do {
            let allContacts = try await dataStore.fetchContacts(deviceID: deviceID)
            repeatersWithLocation = allContacts.filter { $0.hasLocation && $0.type == .repeater }
        } catch {
            logger.error("Failed to load repeaters: \(error.localizedDescription)")
        }
    }

    // MARK: - Point Selection

    /// Auto-assigns coordinate to A if empty, then B if A exists
    func selectPoint(at coordinate: CLLocationCoordinate2D, from contact: ContactDTO? = nil) {
        if pointA == nil {
            setPointA(coordinate: coordinate, contact: contact)
        } else if pointB == nil {
            setPointB(coordinate: coordinate, contact: contact)
        } else {
            // Both points set, replace B
            setPointB(coordinate: coordinate, contact: contact)
        }
    }

    func setPointA(coordinate: CLLocationCoordinate2D, contact: ContactDTO? = nil) {
        // Cancel any pending elevation fetch for point A
        pointAElevationTask?.cancel()
        pointAElevationTask = nil

        // Reset analysis when points change
        invalidateAnalysis()

        pointA = SelectedPoint(
            coordinate: coordinate,
            contact: contact,
            groundElevation: nil
        )

        // Fetch elevation asynchronously
        pointAElevationTask = Task { @MainActor in
            await fetchElevationForPointA()
        }
    }

    func setPointB(coordinate: CLLocationCoordinate2D, contact: ContactDTO? = nil) {
        // Check if B is same location as A
        if let pointA = pointA,
           pointA.coordinate.latitude == coordinate.latitude,
           pointA.coordinate.longitude == coordinate.longitude {
            logger.warning("Cannot set point B to same location as point A")
            return
        }

        // Cancel any pending elevation fetch for point B
        pointBElevationTask?.cancel()
        pointBElevationTask = nil

        // Reset analysis when points change
        invalidateAnalysis()

        pointB = SelectedPoint(
            coordinate: coordinate,
            contact: contact,
            groundElevation: nil
        )

        // Fetch elevation asynchronously
        pointBElevationTask = Task { @MainActor in
            await fetchElevationForPointB()
        }
    }

    // MARK: - Height Adjustment

    func updateAdditionalHeight(for point: PointID, meters: Int) {
        let clampedHeight = max(0, meters)

        switch point {
        case .pointA:
            guard pointA != nil else { return }
            pointA?.additionalHeight = clampedHeight
        case .pointB:
            guard pointB != nil else { return }
            pointB?.additionalHeight = clampedHeight
        case .repeater:
            // Repeater height is handled separately via updateRepeaterHeight
            updateRepeaterHeight(meters: clampedHeight)
            return
        }

        // Height change invalidates analysis
        invalidateAnalysis()
    }

    // MARK: - Contact Toggle Selection

    /// Toggle a contact as a selected point
    /// - If contact is already selected as A or B, clear that point
    /// - Otherwise, auto-assign to A (if empty) or B
    func toggleContact(_ contact: ContactDTO) {
        let coordinate = CLLocationCoordinate2D(latitude: contact.latitude, longitude: contact.longitude)

        // Check if already selected as point A
        if let pointA, pointA.contact?.id == contact.id {
            clearPointA()
            return
        }

        // Check if already selected as point B
        if let pointB, pointB.contact?.id == contact.id {
            clearPointB()
            return
        }

        // Auto-assign using existing logic
        selectPoint(at: coordinate, from: contact)
    }

    /// Check if a contact is currently selected
    /// - Returns: .pointA, .pointB, or nil if not selected
    func isContactSelected(_ contact: ContactDTO) -> PointID? {
        if let pointA, pointA.contact?.id == contact.id {
            return .pointA
        }
        if let pointB, pointB.contact?.id == contact.id {
            return .pointB
        }
        return nil
    }

    // MARK: - Clear Methods

    func clear() {
        pointAElevationTask?.cancel()
        pointBElevationTask?.cancel()
        analysisTask?.cancel()

        pointAElevationTask = nil
        pointBElevationTask = nil
        analysisTask = nil

        pointA = nil
        pointB = nil
        repeaterPoint = nil
        elevationFetchFailed = false
        analysisStatus = .idle
        elevationProfile = []
    }

    func clearPointA() {
        pointAElevationTask?.cancel()
        pointAElevationTask = nil

        pointA = nil
        repeaterPoint = nil
        invalidateAnalysis()
    }

    func clearPointB() {
        pointBElevationTask?.cancel()
        pointBElevationTask = nil

        pointB = nil
        repeaterPoint = nil
        invalidateAnalysis()
    }

    // MARK: - Repeater Methods

    /// Adds repeater at the worst obstruction point
    func addRepeater() {
        guard case .result(let result) = analysisStatus,
              !result.obstructionPoints.isEmpty,
              let worstPoint = result.obstructionPoints.min(by: { $0.fresnelClearancePercent < $1.fresnelClearancePercent }) else {
            return
        }

        // Convert distance to path fraction
        let pathFraction = worstPoint.distanceFromAMeters / result.distanceMeters

        // Get coordinate and elevation from cached profile
        guard let coordinate = coordinateAt(pathFraction: pathFraction),
              let elevation = elevationAt(pathFraction: pathFraction) else { return }

        repeaterPoint = RepeaterPoint(
            coordinate: coordinate,
            groundElevation: elevation,
            additionalHeight: 10,
            isOnPath: true,
            pathFraction: pathFraction
        )
    }

    /// Updates repeater position along the path (for on-path repeaters)
    func updateRepeaterPosition(pathFraction: Double) {
        guard var repeater = repeaterPoint, repeater.isOnPath else { return }

        // Update path fraction and derive coordinate/elevation from cached profile
        repeater.pathFraction = pathFraction
        if let coordinate = coordinateAt(pathFraction: pathFraction) {
            repeater.coordinate = coordinate
        }
        if let elevation = elevationAt(pathFraction: pathFraction) {
            repeater.groundElevation = elevation
        }

        repeaterPoint = repeater
    }

    /// Updates repeater height above ground
    func updateRepeaterHeight(meters: Int) {
        guard repeaterPoint != nil else { return }
        repeaterPoint?.additionalHeight = max(0, meters)
    }

    /// Sets repeater to an off-path location
    /// - Parameter coordinate: The new coordinate for the repeater
    func setRepeaterOffPath(coordinate: CLLocationCoordinate2D) {
        let existingHeight = repeaterPoint?.additionalHeight ?? 10

        repeaterPoint = RepeaterPoint(
            coordinate: coordinate,
            groundElevation: nil,  // Will be fetched
            additionalHeight: existingHeight,
            isOnPath: false,
            pathFraction: 0.5  // Not used for off-path
        )

        // Fetch elevation for the new coordinate
        Task {
            do {
                let elevation = try await elevationService.fetchElevation(at: coordinate)
                repeaterPoint?.groundElevation = elevation
            } catch {
                logger.error("Failed to fetch repeater elevation: \(error.localizedDescription)")
            }
        }
    }

    /// Removes repeater and reverts to single-path analysis
    func clearRepeater() {
        repeaterPoint = nil
        reanalyzeWithCachedProfileIfNeeded()
    }

    /// Analyzes the path with the current repeater position
    func analyzeWithRepeater() {
        guard let repeaterPoint,
              pointA != nil,
              pointB != nil else { return }

        if repeaterPoint.isOnPath {
            // On-path: use cached profile (existing logic)
            analyzeWithRepeaterOnPath()
        } else {
            // Off-path: fetch fresh profiles
            Task {
                await analyzeWithRepeaterOffPath()
            }
        }
    }

    /// On-path analysis using cached elevation profile
    private func analyzeWithRepeaterOnPath() {
        guard let repeaterPoint,
              let pointA,
              let pointB,
              elevationProfile.count >= 2 else { return }

        let profile = elevationProfile
        let pointAHeight = Double(pointA.additionalHeight)
        let pointBHeight = Double(pointB.additionalHeight)
        let repeaterHeight = Double(repeaterPoint.additionalHeight)
        let freq = frequencyMHz
        let k = refractionK
        let pathFraction = repeaterPoint.pathFraction

        // Calculate split index
        let splitIndex = Int(pathFraction * Double(profile.count - 1))
        guard splitIndex > 0, splitIndex < profile.count - 1 else { return }

        // Create segments using ArraySlice (zero allocation)
        let segmentARSlice = profile[0...splitIndex]
        let segmentRBSlice = profile[splitIndex...]

        // Analyze both segments
        let arResult = RFCalculator.analyzePathSegment(
            elevationProfile: segmentARSlice,
            startHeightMeters: pointAHeight,
            endHeightMeters: repeaterHeight,
            frequencyMHz: freq,
            kFactor: k
        )

        let rbResult = RFCalculator.analyzePathSegment(
            elevationProfile: segmentRBSlice,
            startHeightMeters: repeaterHeight,
            endHeightMeters: pointBHeight,
            frequencyMHz: freq,
            kFactor: k
        )

        // Create segment results
        let segmentAR = SegmentAnalysisResult(
            startLabel: "A",
            endLabel: "R",
            clearanceStatus: arResult.clearanceStatus,
            distanceMeters: arResult.distanceMeters,
            worstClearancePercent: arResult.worstClearancePercent
        )

        let segmentRB = SegmentAnalysisResult(
            startLabel: "R",
            endLabel: "B",
            clearanceStatus: rbResult.clearanceStatus,
            distanceMeters: rbResult.distanceMeters,
            worstClearancePercent: rbResult.worstClearancePercent
        )

        let relayResult = RelayPathAnalysisResult(
            segmentAR: segmentAR,
            segmentRB: segmentRB
        )

        // Build profile samples for dual Fresnel zone rendering
        profileSamples = FresnelZoneRenderer.buildProfileSamples(
            from: Array(segmentARSlice),
            pointAHeight: pointAHeight,
            pointBHeight: repeaterHeight,
            frequencyMHz: freq,
            refractionK: k
        )
        profileSamplesRB = FresnelZoneRenderer.buildProfileSamples(
            from: Array(segmentRBSlice),
            pointAHeight: repeaterHeight,
            pointBHeight: pointBHeight,
            frequencyMHz: freq,
            refractionK: k
        )

        analysisStatus = .relayResult(relayResult)
    }

    /// Off-path analysis - fetches A→R and R→B profiles
    private func analyzeWithRepeaterOffPath() async {
        guard let repeaterPoint,
              let pointA,
              let pointB else { return }

        analysisStatus = .loading

        do {
            let pointACoord = pointA.coordinate
            let repeaterCoord = repeaterPoint.coordinate
            let pointBCoord = pointB.coordinate
            let pointAHeight = Double(pointA.additionalHeight)
            let pointBHeight = Double(pointB.additionalHeight)
            let repeaterHeight = Double(repeaterPoint.additionalHeight)
            let freq = frequencyMHz
            let k = refractionK

            // Fetch A→R profile
            let distanceAR = RFCalculator.distance(from: pointACoord, to: repeaterCoord)
            let sampleCountAR = ElevationService.optimalSampleCount(distanceMeters: distanceAR)
            let sampleCoordsAR = ElevationService.sampleCoordinates(
                from: pointACoord,
                to: repeaterCoord,
                sampleCount: sampleCountAR
            )
            let profileAR = try await elevationService.fetchElevations(along: sampleCoordsAR)

            // Fetch R→B profile
            let distanceRB = RFCalculator.distance(from: repeaterCoord, to: pointBCoord)
            let sampleCountRB = ElevationService.optimalSampleCount(distanceMeters: distanceRB)
            let sampleCoordsRB = ElevationService.sampleCoordinates(
                from: repeaterCoord,
                to: pointBCoord,
                sampleCount: sampleCountRB
            )
            let profileRB = try await elevationService.fetchElevations(along: sampleCoordsRB)

            // Analyze both segments
            let arResult = RFCalculator.analyzePathSegment(
                elevationProfile: profileAR[...],
                startHeightMeters: pointAHeight,
                endHeightMeters: repeaterHeight,
                frequencyMHz: freq,
                kFactor: k
            )

            let rbResult = RFCalculator.analyzePathSegment(
                elevationProfile: profileRB[...],
                startHeightMeters: repeaterHeight,
                endHeightMeters: pointBHeight,
                frequencyMHz: freq,
                kFactor: k
            )

            // Create segment results
            let segmentAR = SegmentAnalysisResult(
                startLabel: "A",
                endLabel: "R",
                clearanceStatus: arResult.clearanceStatus,
                distanceMeters: arResult.distanceMeters,
                worstClearancePercent: arResult.worstClearancePercent
            )

            let segmentRB = SegmentAnalysisResult(
                startLabel: "R",
                endLabel: "B",
                clearanceStatus: rbResult.clearanceStatus,
                distanceMeters: rbResult.distanceMeters,
                worstClearancePercent: rbResult.worstClearancePercent
            )

            let relayResult = RelayPathAnalysisResult(
                segmentAR: segmentAR,
                segmentRB: segmentRB
            )

            // Offset R→B profile distances to continue from A→R endpoint
            // (fetchElevations returns distances relative to segment start, not global A)
            let profileRBAdjusted = profileRB.map { sample in
                ElevationSample(
                    coordinate: sample.coordinate,
                    elevation: sample.elevation,
                    distanceFromAMeters: sample.distanceFromAMeters + distanceAR
                )
            }

            // Build profile samples for terrain visualization
            profileSamples = FresnelZoneRenderer.buildProfileSamples(
                from: profileAR,
                pointAHeight: pointAHeight,
                pointBHeight: repeaterHeight,
                frequencyMHz: freq,
                refractionK: k
            )
            profileSamplesRB = FresnelZoneRenderer.buildProfileSamples(
                from: profileRBAdjusted,
                pointAHeight: repeaterHeight,
                pointBHeight: pointBHeight,
                frequencyMHz: freq,
                refractionK: k
            )

            // Store profiles for terrain visualization
            elevationProfileAR = profileAR
            elevationProfileRB = profileRBAdjusted

            analysisStatus = .relayResult(relayResult)

        } catch {
            analysisStatus = .error(error.localizedDescription)
            logger.error("Off-path analysis failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Analysis

    /// Clears analysis results without clearing points
    func clearAnalysisResults() {
        analysisStatus = .idle
        shouldAutoZoomOnNextResult = false
    }

    func analyze() {
        guard let pointA = pointA,
              let pointB = pointB,
              let _ = pointA.groundElevation,
              let _ = pointB.groundElevation else {
            logger.warning("Cannot analyze: missing point elevations")
            return
        }

        // Cancel any existing analysis
        analysisTask?.cancel()

        analysisStatus = .loading

        // Capture values for use in task
        let pointACoord = pointA.coordinate
        let pointBCoord = pointB.coordinate
        let pointAHeight = Double(pointA.additionalHeight)
        let pointBHeight = Double(pointB.additionalHeight)
        let freq = frequencyMHz
        let k = refractionK

        analysisTask = Task {
            do {
                // Calculate optimal sample count based on distance
                let distance = RFCalculator.distance(from: pointACoord, to: pointBCoord)
                let sampleCount = ElevationService.optimalSampleCount(distanceMeters: distance)

                // Generate sample coordinates along the path
                let sampleCoordinates = ElevationService.sampleCoordinates(
                    from: pointACoord,
                    to: pointBCoord,
                    sampleCount: sampleCount
                )

                // Fetch elevation profile (async network call)
                let profile = try await elevationService.fetchElevations(along: sampleCoordinates)

                // Check for cancellation
                if Task.isCancelled { return }

                // Run path analysis off main actor to avoid UI hitching
                let result = await Task.detached {
                    RFCalculator.analyzePath(
                        elevationProfile: profile,
                        pointAHeightMeters: pointAHeight,
                        pointBHeightMeters: pointBHeight,
                        frequencyMHz: freq,
                        kFactor: k
                    )
                }.value

                if Task.isCancelled { return }

                // Update state on MainActor
                elevationProfile = profile
                profileSamples = FresnelZoneRenderer.buildProfileSamples(
                    from: profile,
                    pointAHeight: pointAHeight,
                    pointBHeight: pointBHeight,
                    frequencyMHz: freq,
                    refractionK: k
                )
                profileSamplesRB = []
                analysisStatus = .result(result)
                logger.info("Analysis complete: \(result.clearanceStatus.rawValue), \(result.distanceKm)km")

            } catch {
                if Task.isCancelled { return }
                analysisStatus = .error(error.localizedDescription)
                logger.error("Analysis failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Private Methods

    /// Invalidates analysis results but preserves cached elevation profile
    /// Use when RF settings change (frequency, k-factor)
    private func invalidateAnalysisOnly() {
        analysisTask?.cancel()
        analysisTask = nil
        analysisStatus = .idle
        shouldAutoZoomOnNextResult = false
    }

    /// Invalidates analysis and clears cached elevation profile
    /// Use when points change (requires new elevation data)
    private func invalidateAnalysis() {
        invalidateAnalysisOnly()
        elevationProfile = []
        profileSamples = []
        profileSamplesRB = []
        elevationFetchFailed = false
        repeaterPoint = nil  // Repeater is invalid without profile
    }

    /// Re-runs analysis using cached elevation profile when RF settings change
    private func reanalyzeWithCachedProfileIfNeeded() {
        // Only re-analyze if we have a cached profile and both points
        guard !elevationProfile.isEmpty,
              let pointA = pointA,
              let pointB = pointB,
              pointA.groundElevation != nil,
              pointB.groundElevation != nil else {
            return
        }

        // If repeater is active, use relay analysis to preserve mode
        if repeaterPoint != nil {
            analyzeWithRepeater()
            return
        }

        // Cancel any existing analysis
        analysisTask?.cancel()

        // Capture values for use in task
        let profile = elevationProfile
        let pointAHeight = Double(pointA.additionalHeight)
        let pointBHeight = Double(pointB.additionalHeight)
        let freq = frequencyMHz
        let k = refractionK

        analysisTask = Task {
            // Run path analysis off main actor
            let result = await Task.detached {
                RFCalculator.analyzePath(
                    elevationProfile: profile,
                    pointAHeightMeters: pointAHeight,
                    pointBHeightMeters: pointBHeight,
                    frequencyMHz: freq,
                    kFactor: k
                )
            }.value

            if Task.isCancelled { return }

            profileSamples = FresnelZoneRenderer.buildProfileSamples(
                from: profile,
                pointAHeight: pointAHeight,
                pointBHeight: pointBHeight,
                frequencyMHz: freq,
                refractionK: k
            )
            profileSamplesRB = []
            analysisStatus = .result(result)
            logger.debug("Re-analyzed with cached profile: \(freq) MHz, k=\(k)")
        }
    }

    private func fetchElevationForPointA() async {
        guard let coordinate = pointA?.coordinate else { return }

        do {
            let elevation = try await elevationService.fetchElevation(at: coordinate)
            if Task.isCancelled { return }
            pointA?.groundElevation = elevation
            logger.debug("Point A elevation: \(elevation)m")
        } catch {
            if Task.isCancelled { return }
            logger.error("Failed to fetch point A elevation: \(error.localizedDescription)")
            // Set to 0 as fallback so analysis can proceed (sea level approximation)
            pointA?.groundElevation = 0
            elevationFetchFailed = true
        }
    }

    private func fetchElevationForPointB() async {
        guard let coordinate = pointB?.coordinate else { return }

        do {
            let elevation = try await elevationService.fetchElevation(at: coordinate)
            if Task.isCancelled { return }
            pointB?.groundElevation = elevation
            logger.debug("Point B elevation: \(elevation)m")
        } catch {
            if Task.isCancelled { return }
            logger.error("Failed to fetch point B elevation: \(error.localizedDescription)")
            // Set to 0 as fallback so analysis can proceed (sea level approximation)
            pointB?.groundElevation = 0
            elevationFetchFailed = true
        }
    }

    // MARK: - Elevation Interpolation

    /// Returns interpolation indices and factor for a given path fraction
    /// - Parameter pathFraction: Position along path (0.0 = A, 1.0 = B), clamped to valid range
    /// - Returns: Tuple of (lowerIndex, upperIndex, interpolationFactor) or nil if profile has fewer than 2 samples
    private func interpolationIndices(for pathFraction: Double) -> (lower: Int, upper: Int, t: Double)? {
        guard elevationProfile.count >= 2 else { return nil }

        let clamped = pathFraction.clamped(to: 0.0...1.0)
        let index = clamped * Double(elevationProfile.count - 1)
        let lowerIndex = Int(index)
        let upperIndex = min(lowerIndex + 1, elevationProfile.count - 1)
        let t = index - Double(lowerIndex)

        return (lowerIndex, upperIndex, t)
    }

    /// Interpolates ground elevation at a given path fraction
    /// - Parameter pathFraction: Position along path (0.0 = A, 1.0 = B), clamped to valid range
    /// - Returns: Interpolated ground elevation in meters, or nil if profile has fewer than 2 samples
    func elevationAt(pathFraction: Double) -> Double? {
        guard let indices = interpolationIndices(for: pathFraction) else { return nil }

        let lowerElevation = elevationProfile[indices.lower].elevation
        let upperElevation = elevationProfile[indices.upper].elevation

        return lowerElevation + indices.t * (upperElevation - lowerElevation)
    }

    /// Interpolates coordinate at a given path fraction
    /// - Parameter pathFraction: Position along path (0.0 = A, 1.0 = B), clamped to valid range
    /// - Returns: Interpolated coordinate, or nil if profile has fewer than 2 samples
    func coordinateAt(pathFraction: Double) -> CLLocationCoordinate2D? {
        guard let indices = interpolationIndices(for: pathFraction) else { return nil }

        let lower = elevationProfile[indices.lower].coordinate
        let upper = elevationProfile[indices.upper].coordinate

        return CLLocationCoordinate2D(
            latitude: lower.latitude + indices.t * (upper.latitude - lower.latitude),
            longitude: lower.longitude + indices.t * (upper.longitude - lower.longitude)
        )
    }

    // MARK: - Testing Helpers

    #if DEBUG
    /// Testing helper to set analysis status directly
    func setAnalysisStatusForTesting(_ result: PathAnalysisResult) {
        analysisStatus = .result(result)
    }

    /// Testing helper to set elevation profile directly
    func setElevationProfileForTesting(_ profile: [ElevationSample]) {
        elevationProfile = profile
    }
    #endif
}
