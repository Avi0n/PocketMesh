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

@Suite("NoiseFloorStatistics")
struct NoiseFloorStatisticsTests {

    @Test("statistics calculates min/max/avg correctly")
    func statisticsCalculatesCorrectly() {
        let stats = NoiseFloorStatistics(min: -110, max: -80, average: -95.5)

        #expect(stats.min == -110)
        #expect(stats.max == -80)
        #expect(stats.average == -95.5)
    }
}

@Suite("SignalQuality")
struct SignalQualityTests {

    @Test("excellent for noise floor <= -100")
    func excellentThreshold() {
        #expect(SignalQuality.from(noiseFloor: -100) == .excellent)
        #expect(SignalQuality.from(noiseFloor: -110) == .excellent)
    }

    @Test("good for noise floor <= -90")
    func goodThreshold() {
        #expect(SignalQuality.from(noiseFloor: -90) == .good)
        #expect(SignalQuality.from(noiseFloor: -99) == .good)
    }

    @Test("fair for noise floor <= -80")
    func fairThreshold() {
        #expect(SignalQuality.from(noiseFloor: -80) == .fair)
        #expect(SignalQuality.from(noiseFloor: -89) == .fair)
    }

    @Test("poor for noise floor > -80")
    func poorThreshold() {
        #expect(SignalQuality.from(noiseFloor: -79) == .poor)
        #expect(SignalQuality.from(noiseFloor: -60) == .poor)
    }

    @Test("label returns correct strings")
    func labelReturnsCorrectStrings() {
        #expect(SignalQuality.excellent.label == "Excellent")
        #expect(SignalQuality.good.label == "Good")
        #expect(SignalQuality.fair.label == "Fair")
        #expect(SignalQuality.poor.label == "Poor")
        #expect(SignalQuality.unknown.label == "Unknown")
    }

    @Test("icon returns correct SF Symbols")
    func iconReturnsCorrectSymbols() {
        #expect(SignalQuality.excellent.icon == "checkmark.circle.fill")
        #expect(SignalQuality.good.icon == "circle.fill")
        #expect(SignalQuality.fair.icon == "exclamationmark.circle.fill")
        #expect(SignalQuality.poor.icon == "xmark.circle.fill")
        #expect(SignalQuality.unknown.icon == "questionmark.circle")
    }
}
