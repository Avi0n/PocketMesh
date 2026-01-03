import CoreLocation
import OSLog

/// App-wide location service for managing location permissions and access.
/// Used by MapView, LineOfSightView, and other location-dependent features.
@MainActor
@Observable
public final class LocationService: NSObject, CLLocationManagerDelegate {

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.pocketmesh", category: "LocationService")
    private let locationManager: CLLocationManager

    /// Current authorization status
    public private(set) var authorizationStatus: CLAuthorizationStatus

    /// Whether location services are authorized for use
    public var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    /// Whether permission has been determined (not .notDetermined)
    public var hasRequestedPermission: Bool {
        authorizationStatus != .notDetermined
    }

    // MARK: - Initialization

    public override init() {
        locationManager = CLLocationManager()
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
    }

    // MARK: - Public Methods

    /// Request location permission if not already determined.
    /// Call this when a location-dependent feature is accessed.
    public func requestPermissionIfNeeded() {
        guard authorizationStatus == .notDetermined else {
            logger.debug("Location permission already determined: \(String(describing: self.authorizationStatus.rawValue))")
            return
        }

        logger.info("Requesting location permission")
        locationManager.requestWhenInUseAuthorization()
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            self.logger.info("Location authorization changed: \(String(describing: status.rawValue))")
        }
    }
}
