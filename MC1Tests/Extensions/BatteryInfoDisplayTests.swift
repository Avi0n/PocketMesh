import Testing
@testable import PocketMesh
import MeshCore

struct BatteryInfoDisplayTests {

    // MARK: - Voltage Tests

    @Test func voltage_convertsMillivoltsCorrectly() {
        let battery = BatteryInfo(level: 3700)
        #expect(battery.voltage == 3.7)
    }

    @Test func voltage_zeroMillivolts() {
        let battery = BatteryInfo(level: 0)
        #expect(battery.voltage == 0.0)
    }

    // MARK: - Percentage Tests

    @Test func percentage_fullBattery() {
        let battery = BatteryInfo(level: 4200)
        #expect(battery.percentage == 100)
    }

    @Test func percentage_emptyBattery() {
        let battery = BatteryInfo(level: 3000)
        #expect(battery.percentage == 0)
    }

    @Test func percentage_midRange() {
        let battery = BatteryInfo(level: 3600)  // 50% point
        #expect(battery.percentage == 50)
    }

    @Test func percentage_clampsAbove100() {
        let battery = BatteryInfo(level: 4500)
        #expect(battery.percentage == 100)
    }

    @Test func percentage_clampsBelow0() {
        let battery = BatteryInfo(level: 2500)
        #expect(battery.percentage == 0)
    }

    // MARK: - Icon Tests

    @Test func iconName_fullBattery() {
        let battery = BatteryInfo(level: 4200)
        #expect(battery.iconName == "battery.100")
    }

    @Test func iconName_75percent() {
        let battery = BatteryInfo(level: 3900)  // ~75%
        #expect(battery.iconName == "battery.75")
    }

    @Test func iconName_50percent() {
        let battery = BatteryInfo(level: 3600)  // ~50%
        #expect(battery.iconName == "battery.50")
    }

    @Test func iconName_25percent() {
        let battery = BatteryInfo(level: 3300)  // ~25%
        #expect(battery.iconName == "battery.25")
    }

    @Test func iconName_lowBattery() {
        let battery = BatteryInfo(level: 3100)  // ~8%
        #expect(battery.iconName == "battery.0")
    }

    // MARK: - Color Tests

    @Test func levelColor_normalLevel() {
        let battery = BatteryInfo(level: 3600)  // 50%
        #expect(battery.levelColor == .primary)
    }

    @Test func levelColor_warningLevel() {
        let battery = BatteryInfo(level: 3180)  // ~15%
        #expect(battery.levelColor == .orange)
    }

    @Test func levelColor_criticalLevel() {
        let battery = BatteryInfo(level: 3060)  // ~5%
        #expect(battery.levelColor == .red)
    }
}
