import Testing
import Foundation
@testable import PocketMeshServices

@Suite("LPP Data Point Display Tests")
struct LPPDataPointDisplayTests {

    // MARK: - Battery Percentage Tests

    @Test("Battery percentage at minimum voltage (3.0V) returns 0%")
    func batteryPercentage3_0VReturns0() {
        let dataPoint = LPPDataPoint(channel: 0, type: .voltage, value: .float(3.0))

        #expect(dataPoint.batteryPercentage == 0)
    }

    @Test("Battery percentage at maximum voltage (4.2V) returns 100%")
    func batteryPercentage4_2VReturns100() {
        let dataPoint = LPPDataPoint(channel: 0, type: .voltage, value: .float(4.2))

        #expect(dataPoint.batteryPercentage == 100)
    }

    @Test("Battery percentage at midpoint voltage (3.6V) returns approximately 50%")
    func batteryPercentage3_6VReturns50() {
        let dataPoint = LPPDataPoint(channel: 0, type: .voltage, value: .float(3.6))

        #expect(dataPoint.batteryPercentage == 50)
    }

    @Test("Battery percentage at 3.9V returns 75%")
    func batteryPercentage3_9VReturns75() {
        let dataPoint = LPPDataPoint(channel: 0, type: .voltage, value: .float(3.9))

        #expect(dataPoint.batteryPercentage == 75)
    }

    @Test("Battery percentage below minimum voltage clamps to 0%")
    func batteryPercentageBelowMinClampsTo0() {
        let dataPoint = LPPDataPoint(channel: 0, type: .voltage, value: .float(2.5))

        #expect(dataPoint.batteryPercentage == 0)
    }

    @Test("Battery percentage above maximum voltage clamps to 100%")
    func batteryPercentageAboveMaxClampsTo100() {
        let dataPoint = LPPDataPoint(channel: 0, type: .voltage, value: .float(5.0))

        #expect(dataPoint.batteryPercentage == 100)
    }

    @Test("Battery percentage for non-voltage type returns nil")
    func batteryPercentageNonVoltageReturnsNil() {
        let dataPoint = LPPDataPoint(channel: 0, type: .temperature, value: .float(25.0))

        #expect(dataPoint.batteryPercentage == nil)
    }

    @Test("Battery percentage for integer value returns nil")
    func batteryPercentageIntegerValueReturnsNil() {
        // Voltage should be float, but test edge case where it's not
        let dataPoint = LPPDataPoint(channel: 0, type: .voltage, value: .integer(4))

        #expect(dataPoint.batteryPercentage == nil)
    }

    @Test("Battery percentage for percentage type returns nil")
    func batteryPercentageForPercentageTypeReturnsNil() {
        let dataPoint = LPPDataPoint(channel: 0, type: .percentage, value: .integer(75))

        #expect(dataPoint.batteryPercentage == nil)
    }

    // MARK: - Formatted Value Tests

    @Test("Voltage formatted value includes V suffix")
    func voltageFormattedValueIncludesVSuffix() {
        let dataPoint = LPPDataPoint(channel: 0, type: .voltage, value: .float(3.85))

        #expect(dataPoint.formattedValue == "3.85 V")
    }

    @Test("Temperature formatted value includes degree symbol")
    func temperatureFormattedValueIncludesDegree() {
        let dataPoint = LPPDataPoint(channel: 0, type: .temperature, value: .float(25.5))

        #expect(dataPoint.formattedValue == "25.5\u{00B0}C")
    }
}
