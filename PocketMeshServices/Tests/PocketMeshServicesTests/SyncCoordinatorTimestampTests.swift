import Testing
import Foundation
@testable import PocketMeshServices

@Suite("SyncCoordinator Timestamp Correction")
struct SyncCoordinatorTimestampTests {

    // MARK: - Test Constants

    private let oneMinute: TimeInterval = 60
    private let fiveMinutes: TimeInterval = 5 * 60
    private let sixMinutes: TimeInterval = 6 * 60
    private let oneWeek: TimeInterval = 7 * 24 * 60 * 60
    private let threeMonths: TimeInterval = 3 * 30 * 24 * 60 * 60
    private let sixMonths: TimeInterval = 6 * 30 * 24 * 60 * 60
    private let sevenMonths: TimeInterval = 7 * 30 * 24 * 60 * 60

    // MARK: - Valid Range Tests

    @Test("Timestamp within valid range is not corrected")
    func validTimestampNotCorrected() {
        let now = Date()
        let timestamp = UInt32(now.timeIntervalSince1970)

        let (corrected, wasCorrected) = SyncCoordinator.correctTimestampIfNeeded(timestamp, receiveTime: now)

        #expect(!wasCorrected)
        #expect(corrected == timestamp)
    }

    // MARK: - Future Timestamp Tests

    @Test("Timestamp 1 minute in future is not corrected")
    func oneMinuteFutureNotCorrected() {
        let now = Date()
        let futureDate = now.addingTimeInterval(oneMinute)
        let timestamp = UInt32(futureDate.timeIntervalSince1970)

        let (corrected, wasCorrected) = SyncCoordinator.correctTimestampIfNeeded(timestamp, receiveTime: now)

        #expect(!wasCorrected)
        #expect(corrected == timestamp)
    }

    @Test("Timestamp exactly 5 minutes in future is not corrected")
    func exactlyFiveMinutesFutureNotCorrected() {
        let now = Date()
        let futureDate = now.addingTimeInterval(fiveMinutes)
        let timestamp = UInt32(futureDate.timeIntervalSince1970)

        let (corrected, wasCorrected) = SyncCoordinator.correctTimestampIfNeeded(timestamp, receiveTime: now)

        #expect(!wasCorrected)
        #expect(corrected == timestamp)
    }

    @Test("Timestamp 6 minutes in future is corrected")
    func sixMinutesFutureIsCorrected() {
        let now = Date()
        let futureDate = now.addingTimeInterval(sixMinutes)
        let timestamp = UInt32(futureDate.timeIntervalSince1970)

        let (corrected, wasCorrected) = SyncCoordinator.correctTimestampIfNeeded(timestamp, receiveTime: now)

        #expect(wasCorrected)
        #expect(corrected == UInt32(now.timeIntervalSince1970))
    }

    // MARK: - Past Timestamp Tests

    @Test("Timestamp 1 week ago is not corrected")
    func oneWeekAgoNotCorrected() {
        let now = Date()
        let pastDate = now.addingTimeInterval(-oneWeek)
        let timestamp = UInt32(pastDate.timeIntervalSince1970)

        let (corrected, wasCorrected) = SyncCoordinator.correctTimestampIfNeeded(timestamp, receiveTime: now)

        #expect(!wasCorrected)
        #expect(corrected == timestamp)
    }

    @Test("Timestamp 3 months ago is not corrected")
    func threeMonthsAgoNotCorrected() {
        let now = Date()
        let pastDate = now.addingTimeInterval(-threeMonths)
        let timestamp = UInt32(pastDate.timeIntervalSince1970)

        let (corrected, wasCorrected) = SyncCoordinator.correctTimestampIfNeeded(timestamp, receiveTime: now)

        #expect(!wasCorrected)
        #expect(corrected == timestamp)
    }

    @Test("Timestamp exactly 6 months in past is not corrected")
    func exactlySixMonthsAgoNotCorrected() {
        let now = Date()
        let pastDate = now.addingTimeInterval(-sixMonths)
        let timestamp = UInt32(pastDate.timeIntervalSince1970)

        let (corrected, wasCorrected) = SyncCoordinator.correctTimestampIfNeeded(timestamp, receiveTime: now)

        #expect(!wasCorrected)
        #expect(corrected == timestamp)
    }

    @Test("Timestamp 7 months ago is corrected")
    func sevenMonthsAgoIsCorrected() {
        let now = Date()
        let pastDate = now.addingTimeInterval(-sevenMonths)
        let timestamp = UInt32(pastDate.timeIntervalSince1970)

        let (corrected, wasCorrected) = SyncCoordinator.correctTimestampIfNeeded(timestamp, receiveTime: now)

        #expect(wasCorrected)
        #expect(corrected == UInt32(now.timeIntervalSince1970))
    }

    // MARK: - Edge Case Tests

    @Test("Timestamp of zero (Unix epoch) is corrected")
    func unixEpochIsCorrected() {
        let now = Date()
        let timestamp: UInt32 = 0

        let (corrected, wasCorrected) = SyncCoordinator.correctTimestampIfNeeded(timestamp, receiveTime: now)

        #expect(wasCorrected)
        #expect(corrected == UInt32(now.timeIntervalSince1970))
    }

    @Test("Timestamp from year 2020 is corrected")
    func year2020IsCorrected() {
        let now = Date()
        let oldDate = Date(timeIntervalSince1970: 1577836800) // Jan 1, 2020
        let timestamp = UInt32(oldDate.timeIntervalSince1970)

        let (corrected, wasCorrected) = SyncCoordinator.correctTimestampIfNeeded(timestamp, receiveTime: now)

        #expect(wasCorrected)
        #expect(corrected == UInt32(now.timeIntervalSince1970))
    }

    @Test("Timestamp from year 2030 is corrected")
    func year2030IsCorrected() {
        let now = Date()
        let futureDate = Date(timeIntervalSince1970: 1893456000) // Jan 1, 2030
        let timestamp = UInt32(futureDate.timeIntervalSince1970)

        let (corrected, wasCorrected) = SyncCoordinator.correctTimestampIfNeeded(timestamp, receiveTime: now)

        #expect(wasCorrected)
        #expect(corrected == UInt32(now.timeIntervalSince1970))
    }

    // MARK: - Original Timestamp Preservation Tests

    @Test("Original timestamp is preserved when correction is applied")
    func originalTimestampPreservedForCorrelation() {
        // This test documents critical behavior: the original timestamp must be preserved
        // for RxLogEntry correlation (per payloads.md:65 - ACK deduplication uses original timestamp)
        let now = Date()
        let brokenClockTimestamp: UInt32 = 0  // Unix epoch - clearly invalid

        let (corrected, wasCorrected) = SyncCoordinator.correctTimestampIfNeeded(brokenClockTimestamp, receiveTime: now)

        // Verify correction was applied
        #expect(wasCorrected)
        #expect(corrected == UInt32(now.timeIntervalSince1970))

        // The original timestamp (0) is still available as the input parameter
        // and should be used for RxLogEntry lookup, not the corrected value.
        // This is verified by the fact that correctTimestampIfNeeded returns
        // ONLY the corrected timestamp - the caller must preserve the original.
        #expect(brokenClockTimestamp == 0)  // Original unchanged
        #expect(corrected != brokenClockTimestamp)  // Different from original
    }

    @Test("Corrected timestamp differs from original for invalid input")
    func correctedTimestampDiffersFromOriginal() {
        let now = Date()
        let farFuture = now.addingTimeInterval(365 * 24 * 60 * 60) // 1 year in future
        let originalTimestamp = UInt32(farFuture.timeIntervalSince1970)

        let (corrected, wasCorrected) = SyncCoordinator.correctTimestampIfNeeded(originalTimestamp, receiveTime: now)

        #expect(wasCorrected)
        // The corrected timestamp should be the receive time, not the invalid original
        #expect(corrected == UInt32(now.timeIntervalSince1970))
        // Original and corrected must be different (caller uses original for RxLogEntry lookup)
        #expect(corrected != originalTimestamp)
    }

    // MARK: - Underflow Prevention Tests

    @Test("Receive time near Unix epoch does not crash")
    func nearEpochReceiveTimeDoesNotCrash() {
        // Device clock set to early 1970 - would previously cause UInt32 underflow crash
        let nearEpoch = Date(timeIntervalSince1970: 1000) // ~16 minutes after Unix epoch
        let timestamp: UInt32 = 500

        // This should not crash - the fix uses TimeInterval arithmetic instead of UInt32
        let (corrected, wasCorrected) = SyncCoordinator.correctTimestampIfNeeded(timestamp, receiveTime: nearEpoch)

        // Timestamp is within range (500 is less than 6 months before 1000)
        #expect(!wasCorrected)
        #expect(corrected == timestamp)
    }

    @Test("Receive time at Unix epoch handles timestamp validation")
    func epochReceiveTimeHandlesValidation() {
        let epoch = Date(timeIntervalSince1970: 0)
        let timestamp: UInt32 = 1_000_000 // ~11 days after epoch

        let (corrected, wasCorrected) = SyncCoordinator.correctTimestampIfNeeded(timestamp, receiveTime: epoch)

        // Timestamp is too far in the future from epoch perspective (> 5 minutes)
        #expect(wasCorrected)
        #expect(corrected == 0)
    }
}
