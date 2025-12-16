import XCTest
@testable import PocketMeshKit

final class RadioOptionsTests: XCTestCase {

    // MARK: - Bandwidth Options Tests

    func testBandwidthOptionsAreSorted() {
        XCTAssertEqual(
            RadioOptions.bandwidthsHz,
            RadioOptions.bandwidthsHz.sorted(),
            "Bandwidth options should be sorted in ascending order"
        )
    }

    func testBandwidthOptionsCount() {
        XCTAssertEqual(RadioOptions.bandwidthsHz.count, 10, "Should have exactly 10 bandwidth options")
    }

    func testBandwidthOptionsValues() {
        let expected: [UInt32] = [7_800, 10_400, 15_600, 20_800, 31_250, 41_700, 62_500, 125_000, 250_000, 500_000]
        XCTAssertEqual(RadioOptions.bandwidthsHz, expected)
    }

    func testBandwidthOptionsWithinFirmwareRange() {
        // Firmware validates: bw >= 7000 && bw <= 500000
        for bw in RadioOptions.bandwidthsHz {
            XCTAssertGreaterThanOrEqual(bw, 7_000, "Bandwidth \(bw) below firmware minimum")
            XCTAssertLessThanOrEqual(bw, 500_000, "Bandwidth \(bw) above firmware maximum")
        }
    }

    // MARK: - Format Bandwidth Tests

    func testFormatBandwidthWholeNumbers() {
        XCTAssertEqual(RadioOptions.formatBandwidth(125_000), "125")
        XCTAssertEqual(RadioOptions.formatBandwidth(250_000), "250")
        XCTAssertEqual(RadioOptions.formatBandwidth(500_000), "500")
    }

    func testFormatBandwidthFractionalNumbers() {
        XCTAssertEqual(RadioOptions.formatBandwidth(7_800), "7.8")
        XCTAssertEqual(RadioOptions.formatBandwidth(10_400), "10.4")
        XCTAssertEqual(RadioOptions.formatBandwidth(31_250), "31.25")
        XCTAssertEqual(RadioOptions.formatBandwidth(41_700), "41.7")
        XCTAssertEqual(RadioOptions.formatBandwidth(62_500), "62.5")
    }

    // MARK: - Nearest Bandwidth Tests

    func testNearestBandwidthExactMatch() {
        for bw in RadioOptions.bandwidthsHz {
            XCTAssertEqual(RadioOptions.nearestBandwidth(to: bw), bw, "Exact match should return same value")
        }
    }

    func testNearestBandwidthSlightlyOff() {
        // Handles firmware float precision issues (e.g., 7799 instead of 7800)
        XCTAssertEqual(RadioOptions.nearestBandwidth(to: 7_799), 7_800)
        XCTAssertEqual(RadioOptions.nearestBandwidth(to: 7_801), 7_800)
        XCTAssertEqual(RadioOptions.nearestBandwidth(to: 125_001), 125_000)
        XCTAssertEqual(RadioOptions.nearestBandwidth(to: 124_999), 125_000)
        XCTAssertEqual(RadioOptions.nearestBandwidth(to: 250_100), 250_000)
    }

    func testNearestBandwidthNonStandardValues() {
        // Non-standard values should find the closest option
        XCTAssertEqual(RadioOptions.nearestBandwidth(to: 100_000), 125_000)  // Between 62.5k and 125k
        XCTAssertEqual(RadioOptions.nearestBandwidth(to: 300_000), 250_000)  // Between 250k and 500k
        XCTAssertEqual(RadioOptions.nearestBandwidth(to: 400_000), 500_000)  // Between 250k and 500k
    }

    func testNearestBandwidthEdgeCases() {
        // Very small or zero - should snap to minimum
        XCTAssertEqual(RadioOptions.nearestBandwidth(to: 0), 7_800)
        XCTAssertEqual(RadioOptions.nearestBandwidth(to: 1_000), 7_800)

        // Very large - should snap to maximum
        XCTAssertEqual(RadioOptions.nearestBandwidth(to: 1_000_000), 500_000)
    }

    func testNearestBandwidthAtFirmwareMinimum() {
        // Firmware minimum is 7000 Hz, but our options start at 7800 Hz
        // Values at or below firmware minimum should snap to our minimum option
        XCTAssertEqual(RadioOptions.nearestBandwidth(to: 7_000), 7_800)
        XCTAssertEqual(RadioOptions.nearestBandwidth(to: 7_500), 7_800)
    }

    // MARK: - Spreading Factor Tests

    func testSpreadingFactorRange() {
        XCTAssertEqual(RadioOptions.spreadingFactors.lowerBound, 5)
        XCTAssertEqual(RadioOptions.spreadingFactors.upperBound, 12)
        XCTAssertEqual(RadioOptions.spreadingFactors.count, 8)
    }

    // MARK: - Coding Rate Tests

    func testCodingRateRange() {
        XCTAssertEqual(RadioOptions.codingRates.lowerBound, 5)
        XCTAssertEqual(RadioOptions.codingRates.upperBound, 8)
        XCTAssertEqual(RadioOptions.codingRates.count, 4)
    }
}
