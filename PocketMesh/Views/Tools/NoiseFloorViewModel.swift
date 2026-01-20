import SwiftUI

struct NoiseFloorReading: Identifiable {
    let id: UUID
    let timestamp: Date
    let noiseFloor: Int16
    let lastRSSI: Int8
    let lastSNR: Double
}
