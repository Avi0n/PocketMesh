import Foundation
import Testing
@testable import PocketMesh

@Suite("RelativeTimestampText Tests")
struct RelativeTimestampTextTests {

    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func timestamp(secondsAgo: TimeInterval) -> UInt32 {
        UInt32(referenceDate.addingTimeInterval(-secondsAgo).timeIntervalSince1970)
    }

    // MARK: - Now (< 1 minute)

    @Test("Now is returned for 0 seconds ago")
    func format_justNow_returnsNow() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 0),
            relativeTo: referenceDate
        )
        #expect(result == "Now")
    }

    @Test("Now is returned for 30 seconds ago")
    func format_30SecondsAgo_returnsNow() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 30),
            relativeTo: referenceDate
        )
        #expect(result == "Now")
    }

    @Test("Now is returned for 59 seconds ago")
    func format_59SecondsAgo_returnsNow() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 59),
            relativeTo: referenceDate
        )
        #expect(result == "Now")
    }

    // MARK: - Minutes (1-59 min)

    @Test("1m ago is returned for exactly 60 seconds")
    func format_1MinuteAgo_returns1mAgo() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 60),
            relativeTo: referenceDate
        )
        #expect(result == "1m ago")
    }

    @Test("30m ago is returned for 1800 seconds")
    func format_30MinutesAgo_returns30mAgo() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 1800),
            relativeTo: referenceDate
        )
        #expect(result == "30m ago")
    }

    @Test("59m ago is returned for 3599 seconds")
    func format_59MinutesAgo_returns59mAgo() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 3599),
            relativeTo: referenceDate
        )
        #expect(result == "59m ago")
    }

    // MARK: - Hours (1-23 hours)

    @Test("1h ago is returned for exactly 3600 seconds")
    func format_1HourAgo_returns1hAgo() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 3600),
            relativeTo: referenceDate
        )
        #expect(result == "1h ago")
    }

    @Test("12h ago is returned for 43200 seconds")
    func format_12HoursAgo_returns12hAgo() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 43200),
            relativeTo: referenceDate
        )
        #expect(result == "12h ago")
    }

    @Test("23h ago is returned for 86399 seconds")
    func format_23HoursAgo_returns23hAgo() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 86399),
            relativeTo: referenceDate
        )
        #expect(result == "23h ago")
    }

    // MARK: - Yesterday (24-47 hours)

    @Test("Yesterday is returned for exactly 86400 seconds (24 hours)")
    func format_24HoursAgo_returnsYesterday() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 86400),
            relativeTo: referenceDate
        )
        #expect(result == "Yesterday")
    }

    @Test("Yesterday is returned for 172799 seconds (47h 59m 59s)")
    func format_47HoursAgo_returnsYesterday() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 172799),
            relativeTo: referenceDate
        )
        #expect(result == "Yesterday")
    }

    // MARK: - Days (2-6 days)

    @Test("2d ago is returned for exactly 172800 seconds (48 hours)")
    func format_2DaysAgo_returns2dAgo() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 172800),
            relativeTo: referenceDate
        )
        #expect(result == "2d ago")
    }

    @Test("6d ago is returned for 604799 seconds")
    func format_6DaysAgo_returns6dAgo() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 604799),
            relativeTo: referenceDate
        )
        #expect(result == "6d ago")
    }

    // MARK: - Week+ (formatted date)

    @Test("Formatted date is returned for 7+ days ago")
    func format_7DaysAgo_returnsFormattedDate() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 604800),
            relativeTo: referenceDate
        )
        // Should return abbreviated month and day, e.g., "Nov 7"
        #expect(result.contains(" "))
        #expect(!result.contains("ago"))
    }
}
