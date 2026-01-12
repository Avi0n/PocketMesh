import CoreLocation
import OSLog

/// App-wide location service for managing location permissions and access.
/// Used by MapView, LineOfSightView, ContactsListView, and other location-dependent features.
@MainActor
@Observable
public final class LocationService: NSObject, CLLocationManagerDelegate {

    // MARK: - Properties

    private let logger = Logger(subsystem: "com.pocketmesh", category: "LocationService")
    private let locationManager: CLLocationManager

    /// Current authorization status
    public private(set) var authorizationStatus: CLAuthorizationStatus

    /// Current device location (nil if unavailable or not yet determined)
    public private(set) var currentLocation: CLLocation?

    /// Whether a location request is in progress
    public private(set) var isRequestingLocation = false

    /// Whether location services are authorized for use
    public var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    /// Whether permission has been determined (not .notDetermined)
    public var hasRequestedPermission: Bool {
        authorizationStatus != .notDetermined
    }

    /// Whether location is denied or restricted
    public var isLocationDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    // MARK: - Initialization

    public override init() {
        locationManager = CLLocationManager()
        authorizationStatus = locationManager.authorizationStatus
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
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

    /// Request a one-shot location update.
    /// Call this when you need the current location (e.g., for distance sorting).
    public func requestLocation() {
        guard isAuthorized else {
            logger.debug("Cannot request location: not authorized")
            requestPermissionIfNeeded()
            return
        }

        guard !isRequestingLocation else {
            logger.debug("Location request already in progress")
            return
        }

        logger.info("Requesting one-shot location update")
        isRequestingLocation = true
        locationManager.requestLocation()
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            self.logger.info("Location authorization changed: \(String(describing: status.rawValue))")
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = location
            self.isRequestingLocation = false
            self.logger.info("Location updated: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        }
    }

    nonisolated public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.isRequestingLocation = false
            self.logger.error("Location request failed: \(error.localizedDescription)")
        }
    }
}
