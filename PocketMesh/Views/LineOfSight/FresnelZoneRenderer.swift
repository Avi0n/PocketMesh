import SwiftUI

/// A segment of the Fresnel zone with uniform obstruction state
struct FresnelSegment {
    let xStart: Double
    let xEnd: Double
    let isObstructed: Bool
}

enum FresnelZoneRenderer {

    /// Calculate LOS height at a given distance along the path
    /// - Parameters:
    ///   - atDistance: Distance from point A in meters
    ///   - totalDistance: Total path distance in meters
    ///   - heightA: Antenna height at A (ground + antenna) in meters
    ///   - heightB: Antenna height at B (ground + antenna) in meters
    /// - Returns: LOS height in meters above sea level
    static func losHeight(
        atDistance: Double,
        totalDistance: Double,
        heightA: Double,
        heightB: Double
    ) -> Double {
        guard totalDistance > 0 else { return heightA }
        let fraction = atDistance / totalDistance
        return heightA + fraction * (heightB - heightA)
    }

    /// Build profile samples from elevation data
    /// - Parameters:
    ///   - elevationProfile: Array of elevation samples from terrain API
    ///   - pointAHeight: Antenna height at point A in meters above ground
    ///   - pointBHeight: Antenna height at point B in meters above ground
    ///   - frequencyMHz: Operating frequency for Fresnel zone calculation
    ///   - refractionK: Effective earth radius factor for earth bulge calculation
    /// - Returns: Array of ProfileSample with computed LOS heights and Fresnel radii
    static func buildProfileSamples(
        from elevationProfile: [ElevationSample],
        pointAHeight: Double,
        pointBHeight: Double,
        frequencyMHz: Double,
        refractionK: Double
    ) -> [ProfileSample] {
        guard let first = elevationProfile.first,
              let last = elevationProfile.last else { return [] }

        let totalDistance = last.distanceFromAMeters
        let heightA = first.elevation + pointAHeight
        let heightB = last.elevation + pointBHeight

        return elevationProfile.map { sample in
            let distanceFromA = sample.distanceFromAMeters
            let distanceToB = totalDistance - distanceFromA

            let yLOS = losHeight(
                atDistance: distanceFromA,
                totalDistance: totalDistance,
                heightA: heightA,
                heightB: heightB
            )

            let radius = RFCalculator.fresnelRadius(
                frequencyMHz: frequencyMHz,
                distanceToAMeters: distanceFromA,
                distanceToBMeters: distanceToB
            )

            let earthBulge = RFCalculator.earthBulge(
                distanceToAMeters: distanceFromA,
                distanceToBMeters: distanceToB,
                k: refractionK
            )

            return ProfileSample(
                x: distanceFromA,
                yTerrain: sample.elevation + earthBulge,
                yLOS: yLOS,
                fresnelRadius: radius
            )
        }
    }

    /// Find segments where obstruction state is uniform
    /// Interpolates boundary crossings for smooth color transitions
    static func findSegments(samples: [ProfileSample]) -> [FresnelSegment] {
        guard let first = samples.first, let last = samples.last else { return [] }
        guard samples.count >= 2 else {
            return [FresnelSegment(xStart: first.x, xEnd: first.x, isObstructed: first.isObstructed)]
        }

        var segments: [FresnelSegment] = []
        var segmentStart = first.x
        var currentlyObstructed = first.isObstructed

        for i in 1..<samples.count {
            let prev = samples[i - 1]
            let curr = samples[i]

            if curr.isObstructed != currentlyObstructed {
                // Interpolate crossing point where yTerrain == yBottom
                let prevDelta = prev.yBottom - prev.yTerrain
                let currDelta = curr.yBottom - curr.yTerrain
                let t = prevDelta / (prevDelta - currDelta)
                let xCross = prev.x + t * (curr.x - prev.x)

                segments.append(FresnelSegment(
                    xStart: segmentStart,
                    xEnd: xCross,
                    isObstructed: currentlyObstructed
                ))
                segmentStart = xCross
                currentlyObstructed = curr.isObstructed
            }
        }

        // Final segment
        segments.append(FresnelSegment(
            xStart: segmentStart,
            xEnd: last.x,
            isObstructed: currentlyObstructed
        ))

        return segments
    }
}

/// Sample point with all computed values for rendering
struct ProfileSample {
    let x: Double           // distance from A in meters
    let yTerrain: Double    // terrain elevation in meters
    let yLOS: Double        // line of sight height in meters
    let fresnelRadius: Double

    var yTop: Double { yLOS + fresnelRadius }
    var yBottom: Double { yLOS - fresnelRadius }

    /// Whether terrain intrudes into the Fresnel zone at this point
    var isObstructed: Bool { yTerrain > yBottom }

    /// Visible bottom of Fresnel zone (clamped to avoid path inversion)
    var yVisibleBottom: Double {
        min(max(yTerrain, yBottom), yTop)
    }
}
