import SwiftUI

struct NoiseFloorReading: Identifiable {
    let id: UUID
    let timestamp: Date
    let noiseFloor: Int16
    let lastRSSI: Int8
    let lastSNR: Double
}

struct NoiseFloorStatistics {
    let min: Int16
    let max: Int16
    let average: Double
}

enum SignalQuality: Equatable {
    case excellent
    case good
    case fair
    case poor
    case unknown

    static func from(noiseFloor: Int16) -> SignalQuality {
        switch noiseFloor {
        case ...(-100): return .excellent
        case ...(-90): return .good
        case ...(-80): return .fair
        default: return .poor
        }
    }

    var label: String {
        switch self {
        case .excellent: "Excellent"
        case .good: "Good"
        case .fair: "Fair"
        case .poor: "Poor"
        case .unknown: "Unknown"
        }
    }

    var color: Color {
        switch self {
        case .excellent: .green
        case .good: .blue
        case .fair: .orange
        case .poor: .red
        case .unknown: .secondary
        }
    }

    var icon: String {
        switch self {
        case .excellent: "checkmark.circle.fill"
        case .good: "circle.fill"
        case .fair: "exclamationmark.circle.fill"
        case .poor: "xmark.circle.fill"
        case .unknown: "questionmark.circle"
        }
    }
}
