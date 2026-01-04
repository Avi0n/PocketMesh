import CoreLocation
import PocketMeshServices
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.pocketmesh", category: "LineOfSight")

// MARK: - Point Identification

/// Identifies which point (A or B) for line of sight analysis
enum PointID {
    case pointA
    case pointB
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
        contact?.displayName ?? "Dropped pin"
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
    case error(String)
}

// MARK: - View Model

@MainActor @Observable
final class LineOfSightViewModel {

    // MARK: - Point Selection State

    var pointA: SelectedPoint?
    var pointB: SelectedPoint?

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

    // MARK: - Analysis State

    private(set) var analysisStatus: AnalysisStatus = .idle
    private(set) var elevationProfile: [ElevationSample] = []

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
        self.dataStore = appState.services?.dataStore
        self.deviceID = appState.connectedDevice?.id

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
        analysisStatus = .idle
        elevationProfile = []
    }

    func clearPointA() {
        pointAElevationTask?.cancel()
        pointAElevationTask = nil

        pointA = nil
        invalidateAnalysis()
    }

    func clearPointB() {
        pointBElevationTask?.cancel()
        pointBElevationTask = nil

        pointB = nil
        invalidateAnalysis()
    }

    // MARK: - Analysis

    func analyze() {
        guard let pointA = pointA,
              let pointB = pointB,
              let elevationA = pointA.groundElevation,
              let elevationB = pointB.groundElevation else {
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
                        k: k
                    )
                }.value

                if Task.isCancelled { return }

                // Update state on MainActor
                elevationProfile = profile
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
    }

    /// Invalidates analysis and clears cached elevation profile
    /// Use when points change (requires new elevation data)
    private func invalidateAnalysis() {
        invalidateAnalysisOnly()
        elevationProfile = []
        elevationFetchFailed = false
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
                    k: k
                )
            }.value

            if Task.isCancelled { return }

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
}
