import Foundation

/// Categories for OCV presets
public enum OCVPresetCategory: Sendable {
    /// Generic battery chemistry (Li-Ion, LiFePO4, etc.)
    case batteryChemistry
    /// Specific commercial device
    case deviceSpecific
}

/// Battery OCV (Open Circuit Voltage) presets for accurate percentage calculation.
/// Each preset contains 11 millivolt values mapping to 100%, 90%, 80%... 0%.
///
/// Reference: https://github.com/meshtastic/firmware
public enum OCVPreset: String, CaseIterable, Codable, Sendable {
    case liIon
    case liFePO4
    case leadAcid
    case alkaline
    case niMH
    case lto
    case trackerT1000E
    case heltecPocket5000
    case heltecPocket10000
    case seeedWioTracker
    case seeedSolarNode
    case r1Neo
    case wisMeshTag
    case custom

    /// The 11-point OCV array in millivolts (100% to 0% in 10% steps)
    public var ocvArray: [Int] {
        switch self {
        case .liIon:
            [4190, 4050, 3990, 3890, 3800, 3720, 3630, 3530, 3420, 3300, 3100]
        case .liFePO4:
            [3400, 3350, 3320, 3290, 3270, 3260, 3250, 3230, 3200, 3120, 3000]
        case .leadAcid:
            [2120, 2090, 2070, 2050, 2030, 2010, 1990, 1980, 1970, 1960, 1950]
        case .alkaline:
            [1580, 1400, 1350, 1300, 1280, 1250, 1230, 1190, 1150, 1100, 1000]
        case .niMH:
            [1400, 1300, 1280, 1270, 1260, 1250, 1240, 1230, 1210, 1150, 1000]
        case .lto:
            [2700, 2560, 2540, 2520, 2500, 2460, 2420, 2400, 2380, 2320, 1500]
        case .trackerT1000E:
            [4190, 4042, 3957, 3885, 3820, 3776, 3746, 3725, 3696, 3644, 3100]
        case .heltecPocket5000:
            [4300, 4240, 4120, 4000, 3888, 3800, 3740, 3698, 3655, 3580, 3400]
        case .heltecPocket10000:
            [4100, 4060, 3960, 3840, 3729, 3625, 3550, 3500, 3420, 3345, 3100]
        case .seeedWioTracker:
            [4200, 3876, 3826, 3763, 3713, 3660, 3573, 3485, 3422, 3359, 3300]
        case .seeedSolarNode:
            [4200, 3986, 3922, 3812, 3734, 3645, 3527, 3420, 3281, 3087, 2786]
        case .r1Neo:
            [4330, 4292, 4254, 4216, 4178, 4140, 4102, 4064, 4026, 3988, 3950]
        case .wisMeshTag:
            [4240, 4112, 4029, 3970, 3906, 3846, 3824, 3802, 3776, 3650, 3072]
        case .custom:
            OCVPreset.liIon.ocvArray  // Fallback, actual custom values stored separately
        }
    }

    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .liIon: "Li-Ion (Default)"
        case .liFePO4: "LiFePO4"
        case .leadAcid: "Lead Acid"
        case .alkaline: "Alkaline"
        case .niMH: "NiMH"
        case .lto: "LTO"
        case .trackerT1000E: "Tracker T1000-E"
        case .heltecPocket5000: "Heltec Pocket 5000"
        case .heltecPocket10000: "Heltec Pocket 10000"
        case .seeedWioTracker: "Seeed WIO Tracker"
        case .seeedSolarNode: "Seeed Solar Node"
        case .r1Neo: "R1 Neo"
        case .wisMeshTag: "WisMesh Tag"
        case .custom: "Custom"
        }
    }

    /// The category of this preset
    public var category: OCVPresetCategory {
        switch self {
        case .liIon, .liFePO4, .leadAcid, .alkaline, .niMH, .lto:
            .batteryChemistry
        case .trackerT1000E, .heltecPocket5000, .heltecPocket10000,
             .seeedWioTracker, .seeedSolarNode, .r1Neo, .wisMeshTag, .custom:
            .deviceSpecific
        }
    }

    /// All presets except custom (for picker display)
    public static var selectablePresets: [OCVPreset] {
        allCases.filter { $0 != .custom }
    }

    /// Battery chemistry presets only (excludes device-specific and custom)
    public static var batteryChemistryPresets: [OCVPreset] {
        allCases.filter { $0.category == .batteryChemistry }
    }

    private static let logger = PersistentLogger(subsystem: "com.pocketmesh.services", category: "OCVPreset")

    /// Returns the OCV preset for a known manufacturer name, or nil if no match.
    ///
    /// Manufacturer names must exactly match the strings returned by `getManufacturerName()`
    /// in the MeshCore firmware's device variant headers (`{device_variant}.h`).
    /// See: https://github.com/meshcore-dev/MeshCore
    public static func preset(forManufacturer name: String) -> OCVPreset? {
        let preset: OCVPreset? = switch name {
        case "Seeed Tracker T1000-e": .trackerT1000E
        case "Seeed Wio Tracker L1": .seeedWioTracker
        case "Seeed SenseCap Solar": .seeedSolarNode
        case "RAK WisMesh Tag": .wisMeshTag
        default: nil
        }
        if preset == nil && !name.isEmpty {
            logger.debug("No OCV preset for manufacturer: \(name)")
        }
        return preset
    }
}
