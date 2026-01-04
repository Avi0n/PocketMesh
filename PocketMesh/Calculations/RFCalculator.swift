import CoreLocation
import Foundation

// MARK: - Path Analysis Types

/// Clearance status at worst point along path
enum ClearanceStatus: String {
    case clear = "Clear"
    case marginal = "Marginal"
    case partialObstruction = "Partial obstruction"
    case blocked = "Blocked"
}

/// Point where obstruction affects the path
struct ObstructionPoint: Identifiable, Equatable {
    let id = UUID()
    let distanceFromAMeters: Double
    let obstructionHeightMeters: Double
    let fresnelClearancePercent: Double

    static func == (lhs: ObstructionPoint, rhs: ObstructionPoint) -> Bool {
        lhs.distanceFromAMeters == rhs.distanceFromAMeters
            && lhs.obstructionHeightMeters == rhs.obstructionHeightMeters
            && lhs.fresnelClearancePercent == rhs.fresnelClearancePercent
    }
}

/// Complete analysis result for a path
struct PathAnalysisResult: Equatable {
    let distanceMeters: Double
    let freeSpacePathLoss: Double
    let additionalDiffractionLoss: Double
    let totalPathLoss: Double
    let clearanceStatus: ClearanceStatus
    let worstClearancePercent: Double
    let obstructionPoints: [ObstructionPoint]
    let frequencyMHz: Double
    let refractionK: Double

    var distanceKm: Double { distanceMeters / 1000 }
}

/// Elevation sample along the path
struct ElevationSample: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let elevation: Double  // meters above sea level
    let distanceFromAMeters: Double
}

/// RF propagation calculator for line-of-sight analysis.
///
/// Provides functions for calculating wavelength, Fresnel zones, earth bulge,
/// path loss, and diffraction loss for radio frequency propagation analysis.
enum RFCalculator {

    // MARK: - Constants

    /// Speed of light in meters per second
    static let speedOfLight: Double = 299_792_458

    /// Earth's radius in kilometers
    static let earthRadiusKm: Double = 6371

    // MARK: - Wavelength

    /// Calculates the wavelength in meters for a given frequency.
    /// - Parameter frequencyMHz: The frequency in megahertz.
    /// - Returns: The wavelength in meters.
    static func wavelength(frequencyMHz: Double) -> Double {
        guard frequencyMHz > 0 else { return 0 }
        let frequencyHz = frequencyMHz * 1_000_000
        return speedOfLight / frequencyHz
    }

    // MARK: - Fresnel Zone

    /// Calculates the first Fresnel zone radius at a point along the path.
    ///
    /// The Fresnel zone represents the ellipsoidal region around the direct
    /// line-of-sight path where radio waves propagate. For best reception,
    /// at least 60% of the first Fresnel zone should be clear of obstructions.
    ///
    /// - Parameters:
    ///   - frequencyMHz: The frequency in megahertz.
    ///   - distanceToAMeters: Distance from point A to the calculation point in meters.
    ///   - distanceToBMeters: Distance from the calculation point to point B in meters.
    /// - Returns: The first Fresnel zone radius in meters.
    static func fresnelRadius(
        frequencyMHz: Double,
        distanceToAMeters: Double,
        distanceToBMeters: Double
    ) -> Double {
        guard frequencyMHz > 0, distanceToAMeters > 0, distanceToBMeters > 0 else { return 0 }

        let lambda = wavelength(frequencyMHz: frequencyMHz)
        let totalDistance = distanceToAMeters + distanceToBMeters

        // First Fresnel zone radius: r = sqrt((lambda * d1 * d2) / (d1 + d2))
        return sqrt((lambda * distanceToAMeters * distanceToBMeters) / totalDistance)
    }

    // MARK: - Earth Bulge

    /// Calculates the earth bulge (curvature correction) at a point along the path.
    ///
    /// Earth bulge represents how much the curved surface of the Earth rises
    /// above a straight line between two points. This is critical for long-distance
    /// radio links where the curvature can obstruct the signal path.
    ///
    /// - Parameters:
    ///   - distanceToAMeters: Distance from point A to the calculation point in meters.
    ///   - distanceToBMeters: Distance from the calculation point to point B in meters.
    ///   - k: The effective earth radius factor. Use 1.0 for no adjustment,
    ///        1.33 (4/3) for standard atmosphere, or 4.0 for ducting conditions.
    /// - Returns: The earth bulge in meters.
    static func earthBulge(
        distanceToAMeters: Double,
        distanceToBMeters: Double,
        k: Double
    ) -> Double {
        guard distanceToAMeters > 0, distanceToBMeters > 0, k > 0 else { return 0 }

        let earthRadiusMeters = earthRadiusKm * 1000
        let effectiveEarthRadius = k * earthRadiusMeters

        // Earth bulge: h = (d1 * d2) / (2 * Re_effective)
        return (distanceToAMeters * distanceToBMeters) / (2 * effectiveEarthRadius)
    }

    // MARK: - Path Loss

    /// Calculates the free-space path loss in decibels.
    ///
    /// Free-space path loss represents the attenuation of radio signal
    /// as it travels through free space (vacuum). Real-world losses are
    /// typically higher due to atmospheric absorption and other factors.
    ///
    /// - Parameters:
    ///   - distanceMeters: The distance in meters.
    ///   - frequencyMHz: The frequency in megahertz.
    /// - Returns: The free-space path loss in dB.
    static func pathLoss(distanceMeters: Double, frequencyMHz: Double) -> Double {
        guard distanceMeters > 0, frequencyMHz > 0 else { return 0 }

        // FSPL (dB) = 20*log10(d) + 20*log10(f) + 20*log10(4*pi/c)
        // Simplified: FSPL = 20*log10(d_m) + 20*log10(f_MHz) + 20*log10(4*pi*1e6/c)
        // The constant = 20*log10(4*pi*1e6/299792458) ≈ -27.55
        let distanceComponent = 20 * log10(distanceMeters)
        let frequencyComponent = 20 * log10(frequencyMHz)
        let constant = -27.55

        return distanceComponent + frequencyComponent + constant
    }

    // MARK: - Diffraction Loss

    /// Calculates the knife-edge diffraction loss for an obstruction.
    ///
    /// Uses the Fresnel-Kirchhoff diffraction parameter (v) to estimate
    /// the loss caused by a single knife-edge obstruction in the path.
    ///
    /// - Parameters:
    ///   - obstructionHeightMeters: The height of the obstruction above the line-of-sight
    ///                              (positive = blocked, negative = clearance).
    ///   - distanceToAMeters: Distance from point A to the obstruction in meters.
    ///   - distanceToBMeters: Distance from the obstruction to point B in meters.
    ///   - frequencyMHz: The frequency in megahertz.
    /// - Returns: The diffraction loss in dB (positive value represents loss).
    static func diffractionLoss(
        obstructionHeightMeters: Double,
        distanceToAMeters: Double,
        distanceToBMeters: Double,
        frequencyMHz: Double
    ) -> Double {
        guard distanceToAMeters > 0, distanceToBMeters > 0, frequencyMHz > 0 else { return 0 }

        let lambda = wavelength(frequencyMHz: frequencyMHz)
        let totalDistance = distanceToAMeters + distanceToBMeters

        // Fresnel-Kirchhoff diffraction parameter:
        // v = h * sqrt(2 * (d1 + d2) / (lambda * d1 * d2))
        let v = obstructionHeightMeters * sqrt(
            2 * totalDistance / (lambda * distanceToAMeters * distanceToBMeters)
        )

        // Approximate diffraction loss based on v parameter
        // Using ITU-R P.526 approximation
        return diffractionLossFromV(v)
    }

    /// Calculates diffraction loss from the Fresnel-Kirchhoff v parameter.
    ///
    /// Uses a polynomial approximation of the ITU-R P.526 knife-edge diffraction model.
    ///
    /// - Parameter v: The Fresnel-Kirchhoff diffraction parameter.
    /// - Returns: The diffraction loss in dB.
    private static func diffractionLossFromV(_ v: Double) -> Double {
        if v < -1 {
            // Clear line-of-sight with good clearance
            // Negligible loss (small gain possible)
            return 0
        } else if v <= 0 {
            // Grazing or slight clearance
            // Approximately: L = 6.02 + 9.11*v + 1.27*v^2
            return max(0, 6.02 + 9.11 * v + 1.27 * v * v)
        } else if v <= 2.4 {
            // Moderate obstruction
            // Approximately: L = 6.02 + 9.11*v + 1.27*v^2
            return 6.02 + 9.11 * v + 1.27 * v * v
        } else {
            // Severe obstruction
            // Approximately: L = 12.95 + 20*log10(v)
            return 12.95 + 20 * log10(v)
        }
    }

    // MARK: - Distance Calculation

    /// Calculates the great-circle distance between two coordinates using the Haversine formula.
    ///
    /// - Parameters:
    ///   - from: The starting coordinate.
    ///   - to: The ending coordinate.
    /// - Returns: The distance in meters.
    static func distance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let earthRadiusMeters = earthRadiusKm * 1000

        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let deltaLat = (to.latitude - from.latitude) * .pi / 180
        let deltaLon = (to.longitude - from.longitude) * .pi / 180

        // Haversine formula
        let a = sin(deltaLat / 2) * sin(deltaLat / 2) +
                cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))

        return earthRadiusMeters * c
    }

    // MARK: - Path Analysis

    /// Analyze full path for clearance and signal propagation.
    ///
    /// This function evaluates an elevation profile between two points to determine:
    /// - Free-space path loss (FSPL)
    /// - Additional loss from diffraction over obstructions
    /// - Fresnel zone clearance at each point
    /// - Overall clearance status of the path
    ///
    /// - Parameters:
    ///   - elevationProfile: Array of elevation samples along the path from A to B.
    ///   - pointAHeightMeters: Antenna height at point A in meters above ground.
    ///   - pointBHeightMeters: Antenna height at point B in meters above ground.
    ///   - frequencyMHz: The operating frequency in megahertz.
    ///   - k: The effective earth radius factor. Use 1.0 for no adjustment,
    ///        1.33 (4/3) for standard atmosphere, or 4.0 for ducting conditions.
    /// - Returns: A PathAnalysisResult containing loss calculations and clearance status.
    static func analyzePath(
        elevationProfile: [ElevationSample],
        pointAHeightMeters: Double,
        pointBHeightMeters: Double,
        frequencyMHz: Double,
        k: Double
    ) -> PathAnalysisResult {
        guard elevationProfile.count >= 2 else {
            return PathAnalysisResult(
                distanceMeters: 0,
                freeSpacePathLoss: 0,
                additionalDiffractionLoss: 0,
                totalPathLoss: 0,
                clearanceStatus: .blocked,
                worstClearancePercent: 0,
                obstructionPoints: [],
                frequencyMHz: frequencyMHz,
                refractionK: k
            )
        }

        // Get first and last samples for total distance and endpoint elevations
        let firstSample = elevationProfile.first!
        let lastSample = elevationProfile.last!
        let totalDistanceMeters = lastSample.distanceFromAMeters

        guard totalDistanceMeters > 0 else {
            return PathAnalysisResult(
                distanceMeters: 0,
                freeSpacePathLoss: 0,
                additionalDiffractionLoss: 0,
                totalPathLoss: 0,
                clearanceStatus: .blocked,
                worstClearancePercent: 0,
                obstructionPoints: [],
                frequencyMHz: frequencyMHz,
                refractionK: k
            )
        }

        // Antenna heights above sea level
        let antennaAHeight = firstSample.elevation + pointAHeightMeters
        let antennaBHeight = lastSample.elevation + pointBHeightMeters

        // Calculate free-space path loss
        let fspl = pathLoss(distanceMeters: totalDistanceMeters, frequencyMHz: frequencyMHz)

        var worstClearancePercent = Double.infinity
        var maxDiffractionLoss = 0.0
        var obstructionPoints: [ObstructionPoint] = []

        // Analyze each intermediate sample point (skip endpoints)
        for sample in elevationProfile {
            let distanceFromA = sample.distanceFromAMeters
            let distanceToB = totalDistanceMeters - distanceFromA

            // Skip points at or very near the endpoints
            guard distanceFromA > 1, distanceToB > 1 else { continue }

            // Line of sight height at this point (linear interpolation)
            let fraction = distanceFromA / totalDistanceMeters
            let losHeight = antennaAHeight + fraction * (antennaBHeight - antennaAHeight)

            // Effective terrain height including earth bulge
            let bulge = earthBulge(
                distanceToAMeters: distanceFromA,
                distanceToBMeters: distanceToB,
                k: k
            )
            let effectiveTerrainHeight = sample.elevation + bulge

            // Calculate Fresnel zone radius at this point
            let fresnelZoneRadius = fresnelRadius(
                frequencyMHz: frequencyMHz,
                distanceToAMeters: distanceFromA,
                distanceToBMeters: distanceToB
            )

            // Clearance: distance from terrain to line of sight
            let clearance = losHeight - effectiveTerrainHeight

            // Fresnel clearance percentage
            // 100% = terrain clears full first Fresnel zone
            // 0% = terrain touches line of sight
            // <0% = terrain blocks line of sight
            let clearancePercent: Double
            if fresnelZoneRadius > 0 {
                clearancePercent = (clearance / fresnelZoneRadius) * 100
            } else {
                clearancePercent = clearance > 0 ? 100 : 0
            }

            // Track worst clearance
            if clearancePercent < worstClearancePercent {
                worstClearancePercent = clearancePercent
            }

            // Calculate diffraction loss if there's an obstruction
            // Obstruction height is negative clearance (positive = blocked)
            let obstructionHeight = effectiveTerrainHeight - losHeight
            if obstructionHeight > -fresnelZoneRadius {
                let diffLoss = diffractionLoss(
                    obstructionHeightMeters: obstructionHeight,
                    distanceToAMeters: distanceFromA,
                    distanceToBMeters: distanceToB,
                    frequencyMHz: frequencyMHz
                )
                if diffLoss > maxDiffractionLoss {
                    maxDiffractionLoss = diffLoss
                }
            }

            // Record obstruction points where clearance < 60%
            if clearancePercent < 60 {
                let obstruction = ObstructionPoint(
                    distanceFromAMeters: distanceFromA,
                    obstructionHeightMeters: obstructionHeight,
                    fresnelClearancePercent: clearancePercent
                )
                obstructionPoints.append(obstruction)
            }
        }

        // If no samples were analyzed, set default clearance
        if worstClearancePercent == .infinity {
            worstClearancePercent = 100
        }

        // Determine clearance status
        let clearanceStatus: ClearanceStatus
        if worstClearancePercent >= 80 {
            clearanceStatus = .clear
        } else if worstClearancePercent >= 60 {
            clearanceStatus = .marginal
        } else if worstClearancePercent >= 0 {
            clearanceStatus = .partialObstruction
        } else {
            clearanceStatus = .blocked
        }

        let totalPathLoss = fspl + maxDiffractionLoss

        return PathAnalysisResult(
            distanceMeters: totalDistanceMeters,
            freeSpacePathLoss: fspl,
            additionalDiffractionLoss: maxDiffractionLoss,
            totalPathLoss: totalPathLoss,
            clearanceStatus: clearanceStatus,
            worstClearancePercent: worstClearancePercent,
            obstructionPoints: obstructionPoints,
            frequencyMHz: frequencyMHz,
            refractionK: k
        )
    }
}
