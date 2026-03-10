import Testing
import MeshCore
@testable import PocketMesh

@Suite("Battery Percentage Calculation Tests")
struct BatteryPercentageCalculationTests {

    // Li-Ion array for testing: [4190, 4050, 3990, 3890, 3800, 3720, 3630, 3530, 3420, 3300, 3100]
    let liIonArray = [4190, 4050, 3990, 3890, 3800, 3720, 3630, 3530, 3420, 3300, 3100]

    @Test("Voltage at 100% point returns 100")
    func voltageAt100Percent() {
        let battery = BatteryInfo(level: 4190)
        #expect(battery.percentage(using: liIonArray) == 100)
    }

    @Test("Voltage at 0% point returns 0")
    func voltageAt0Percent() {
        let battery = BatteryInfo(level: 3100)
        #expect(battery.percentage(using: liIonArray) == 0)
    }

    @Test("Voltage above max returns 100")
    func voltageAboveMax() {
        let battery = BatteryInfo(level: 4500)
        #expect(battery.percentage(using: liIonArray) == 100)
    }

    @Test("Voltage below min returns 0")
    func voltageBelowMin() {
        let battery = BatteryInfo(level: 2800)
        #expect(battery.percentage(using: liIonArray) == 0)
    }

    @Test("Voltage at 50% point returns 50")
    func voltageAt50Percent() {
        // 50% is at index 5 = 3720mV
        let battery = BatteryInfo(level: 3720)
        #expect(battery.percentage(using: liIonArray) == 50)
    }

    @Test("Voltage interpolates between points")
    func voltageInterpolates() {
        // Midpoint between 4190 (100%) and 4050 (90%) = 4120 should be ~95%
        let battery = BatteryInfo(level: 4120)
        let percent = battery.percentage(using: liIonArray)
        #expect(percent >= 94 && percent <= 96, "Expected ~95%, got \(percent)")
    }
}
