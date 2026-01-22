import Testing
import Foundation
@testable import PocketMeshServices

@Suite("SyncCoordinator Timestamp Correction")
struct SyncCoordinatorTimestampTests {

    @Test("Timestamp within valid range is not corrected")
    func validTimestampNotCorrected() {
        let now = Date()
        let timestamp = UInt32(now.timeIntervalSince1970)

        let (corrected, wasCorrected) = SyncCoordinator.correctTimestampIfNeeded(timestamp, receiveTime: now)

        #expect(!wasCorrected)
        #expect(corrected == timestamp)
    }

    @Test("Timestamp 1 minute in future is not corrected")
    func oneMinuteFutureNotCorrected() {
        let now = Date()
        let futureDate = now.addingTimeInterval(60) // 1 minute future
        let timestamp = UInt32(futureDate.timeIntervalSince1970)

        let (corrected, wasCorrected) = SyncCoordinator.correctTimestampIfNeeded(timestamp, receiveTime: now)

        #expect(!wasCorrected)
        #expect(corrected == timestamp)
    }

    @Test("Timestamp exactly 5 minutes in future is not corrected")
    func exactlyFiveMinutesFutureNotCorrected() {
        let now = Date()
        let futureDate = now.addingTimeInterval(5 * 60) // exactly 5 minutes
        let timestamp = UInt32(futureDate.timeIntervalSince1970)

        let (corrected, wasCorrected) = SyncCoordinator.correctTimestampIfNeeded(timestamp, receiveTime: now)

        #expect(!wasCorrected)
        #expect(corrected == timestamp)
    }

    @Test("Timestamp 6 minutes in future is corrected")
    func sixMinutesFutureIsCorrected() {
        let now = Date()
        let futureDate = now.addingTimeInterval(6 * 60) // 6 minutes future
        let timestamp = UInt32(futureDate.timeIntervalSince1970)

        let (corrected, wasCorrected) = SyncCoordinator.correctTimestampIfNeeded(timestamp, receiveTime: now)

        #expect(wasCorrected)
        #expect(corrected == UInt32(now.timeIntervalSince1970))
    }

    @Test("Timestamp 1 week ago is not corrected")
    func oneWeekAgoNotCorrected() {
        let now = Date()
        let pastDate = now.addingTimeInterval(-7 * 24 * 60 * 60) // 1 week ago
        let timestamp = UInt32(pastDate.timeIntervalSince1970)

        let (corrected, wasCorrected) = SyncCoordinator.correctTimestampIfNeeded(timestamp, receiveTime: now)

        #expect(!wasCorrected)
        #expect(corrected == timestamp)
    }

    @Test("Timestamp 3 months ago is not corrected")
    func threeMonthsAgoNotCorrected() {
        let now = Date()
        let pastDate = now.addingTimeInterval(-3 * 30 * 24 * 60 * 60) // ~3 months ago
        let timestamp = UInt32(pastDate.timeIntervalSince1970)

        let (corrected, wasCorrected) = SyncCoordinator.correctTimestampIfNeeded(timestamp, receiveTime: now)

        #expect(!wasCorrected)
        #expect(corrected == timestamp)
    }

    @Test("Timestamp 7 months ago is corrected")
    func sevenMonthsAgoIsCorrected() {
        let now = Date()
        let pastDate = now.addingTimeInterval(-7 * 30 * 24 * 60 * 60) // ~7 months ago
        let timestamp = UInt32(pastDate.timeIntervalSince1970)

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
}
