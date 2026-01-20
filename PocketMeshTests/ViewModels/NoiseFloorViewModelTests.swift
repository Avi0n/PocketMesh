import Testing
import Foundation
@testable import PocketMesh

@Suite("NoiseFloorReading")
struct NoiseFloorReadingTests {

    @Test("reading stores all values correctly")
    func readingStoresValues() {
        let timestamp = Date()
        let reading = NoiseFloorReading(
            id: UUID(),
            timestamp: timestamp,
            noiseFloor: -95,
            lastRSSI: -80,
            lastSNR: 7.5
        )

        #expect(reading.noiseFloor == -95)
        #expect(reading.lastRSSI == -80)
        #expect(reading.lastSNR == 7.5)
        #expect(reading.timestamp == timestamp)
    }
}
