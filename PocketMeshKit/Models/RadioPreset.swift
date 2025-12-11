import Foundation

/// Radio configuration preset for common regional settings
public struct RadioPreset: Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let region: RadioRegion
    public let frequencyMHz: Double
    public let spreadingFactor: UInt8
    public let bandwidthKHz: Double
    public let codingRate: UInt8

    /// Frequency in kHz for protocol encoding
    public var frequencyKHz: UInt32 {
        UInt32(frequencyMHz * 1000)
    }

    /// Bandwidth in Hz for protocol encoding
    public var bandwidthHz: UInt32 {
        UInt32(bandwidthKHz * 1000)
    }

    public init(
        id: String,
        name: String,
        region: RadioRegion,
        frequencyMHz: Double,
        spreadingFactor: UInt8,
        bandwidthKHz: Double,
        codingRate: UInt8
    ) {
        self.id = id
        self.name = name
        self.region = region
        self.frequencyMHz = frequencyMHz
        self.spreadingFactor = spreadingFactor
        self.bandwidthKHz = bandwidthKHz
        self.codingRate = codingRate
    }
}

/// Geographic regions for radio preset filtering
public enum RadioRegion: String, CaseIterable, Sendable {
    case northAmerica = "North America"
    case europe = "Europe"
    case oceania = "Oceania"
    case asia = "Asia"

    /// Regions that should be shown for a given locale
    public static func regionsForLocale(_ locale: Locale = .current) -> [RadioRegion] {
        guard let regionCode = locale.region?.identifier else {
            return RadioRegion.allCases
        }

        switch regionCode {
        case "US", "CA":
            return [.northAmerica, .europe, .oceania, .asia]
        case "AU", "NZ":
            return [.oceania, .northAmerica, .europe, .asia]
        case "GB", "DE", "FR", "IT", "ES", "PT", "CH", "CZ", "IE", "NL", "BE", "AT":
            return [.europe, .northAmerica, .oceania, .asia]
        case "VN", "TH", "MY", "SG", "PH", "ID":
            return [.asia, .oceania, .europe, .northAmerica]
        default:
            return RadioRegion.allCases
        }
    }
}

/// Static collection of all available radio presets
public enum RadioPresets {
    public static let all: [RadioPreset] = [
        // Oceania
        RadioPreset(
            id: "au-915",
            name: "Australia",
            region: .oceania,
            frequencyMHz: 915.800,
            spreadingFactor: 10,
            bandwidthKHz: 250,
            codingRate: 5
        ),
        RadioPreset(
            id: "au-vic",
            name: "Australia (Victoria)",
            region: .oceania,
            frequencyMHz: 916.575,
            spreadingFactor: 7,
            bandwidthKHz: 62.5,
            codingRate: 8
        ),
        RadioPreset(
            id: "nz-lr",
            name: "New Zealand",
            region: .oceania,
            frequencyMHz: 917.375,
            spreadingFactor: 11,
            bandwidthKHz: 250,
            codingRate: 5
        ),
        RadioPreset(
            id: "nz-narrow",
            name: "New Zealand (Narrow)",
            region: .oceania,
            frequencyMHz: 917.375,
            spreadingFactor: 7,
            bandwidthKHz: 62.5,
            codingRate: 5
        ),

        // Europe
        RadioPreset(
            id: "eu-narrow",
            name: "EU/UK (Narrow)",
            region: .europe,
            frequencyMHz: 869.618,
            spreadingFactor: 8,
            bandwidthKHz: 62.5,
            codingRate: 8
        ),
        RadioPreset(
            id: "eu-lr",
            name: "EU/UK (Long Range)",
            region: .europe,
            frequencyMHz: 869.525,
            spreadingFactor: 11,
            bandwidthKHz: 250,
            codingRate: 5
        ),
        RadioPreset(
            id: "eu-mr",
            name: "EU/UK (Medium Range)",
            region: .europe,
            frequencyMHz: 869.525,
            spreadingFactor: 10,
            bandwidthKHz: 250,
            codingRate: 5
        ),
        RadioPreset(
            id: "cz-narrow",
            name: "Czech Republic (Narrow)",
            region: .europe,
            frequencyMHz: 869.525,
            spreadingFactor: 7,
            bandwidthKHz: 62.5,
            codingRate: 5
        ),
        RadioPreset(
            id: "eu-433-lr",
            name: "EU 433MHz (Long Range)",
            region: .europe,
            frequencyMHz: 433.650,
            spreadingFactor: 11,
            bandwidthKHz: 250,
            codingRate: 5
        ),
        RadioPreset(
            id: "pt-433",
            name: "Portugal 433",
            region: .europe,
            frequencyMHz: 433.375,
            spreadingFactor: 9,
            bandwidthKHz: 62.5,
            codingRate: 6
        ),
        RadioPreset(
            id: "pt-868",
            name: "Portugal 868",
            region: .europe,
            frequencyMHz: 869.618,
            spreadingFactor: 7,
            bandwidthKHz: 62.5,
            codingRate: 6
        ),
        RadioPreset(
            id: "ch",
            name: "Switzerland",
            region: .europe,
            frequencyMHz: 869.618,
            spreadingFactor: 8,
            bandwidthKHz: 62.5,
            codingRate: 8
        ),

        // North America
        RadioPreset(
            id: "us-ca",
            name: "USA/Canada",
            region: .northAmerica,
            frequencyMHz: 910.525,
            spreadingFactor: 7,
            bandwidthKHz: 62.5,
            codingRate: 5
        ),

        // Asia
        RadioPreset(
            id: "vn",
            name: "Vietnam",
            region: .asia,
            frequencyMHz: 920.250,
            spreadingFactor: 11,
            bandwidthKHz: 250,
            codingRate: 5
        ),
    ]

    /// Get presets filtered and sorted by user's locale
    public static func presetsForLocale(_ locale: Locale = .current) -> [RadioPreset] {
        let preferredRegions = RadioRegion.regionsForLocale(locale)

        return all.sorted { a, b in
            let aIndex = preferredRegions.firstIndex(of: a.region) ?? preferredRegions.count
            let bIndex = preferredRegions.firstIndex(of: b.region) ?? preferredRegions.count
            if aIndex != bIndex {
                return aIndex < bIndex
            }
            return a.name < b.name
        }
    }

    /// Find preset matching current device settings (approximate match)
    public static func matchingPreset(
        frequencyKHz: UInt32,
        bandwidthKHz: UInt32,
        spreadingFactor: UInt8,
        codingRate: UInt8
    ) -> RadioPreset? {
        let freqMHz = Double(frequencyKHz) / 1000.0
        let bwKHz = Double(bandwidthKHz) / 1000.0

        return all.first { preset in
            abs(preset.frequencyMHz - freqMHz) < 0.1 &&
            abs(preset.bandwidthKHz - bwKHz) < 1.0 &&
            preset.spreadingFactor == spreadingFactor &&
            preset.codingRate == codingRate
        }
    }
}
