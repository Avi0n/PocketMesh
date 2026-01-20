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
