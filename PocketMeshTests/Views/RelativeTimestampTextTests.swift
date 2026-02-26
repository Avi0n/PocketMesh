import Foundation
import Testing
@testable import PocketMesh

@Suite("RelativeTimestampText Tests")
struct RelativeTimestampTextTests {

    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func timestamp(secondsAgo: TimeInterval) -> UInt32 {
        UInt32(referenceDate.addingTimeInterval(-secondsAgo).timeIntervalSince1970)
    }

    // MARK: - Same Day (clock time)

    @Test("Returns clock time for just now")
    func format_justNow_returnsClockTime() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 0),
            relativeTo: referenceDate
        )
        // Should return clock time like "3:42 PM", which contains ":"
        #expect(result.contains(":"))
    }

    @Test("Returns clock time for minutes ago")
    func format_minutesAgo_returnsClockTime() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 120),
            relativeTo: referenceDate
        )
        #expect(result.contains(":"))
    }

    @Test("Returns clock time for hours ago")
    func format_hoursAgo_returnsClockTime() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 3600),
            relativeTo: referenceDate
        )
        #expect(result.contains(":"))
    }

    // MARK: - Yesterday

    @Test("Returns 'Yesterday' for yesterday")
    func format_yesterday_returnsYesterday() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 86400),
            relativeTo: referenceDate
        )
        #expect(result == "Yesterday")
    }

    // MARK: - Day of Week (2-6 days ago)

    @Test("Returns full weekday name for 2 days ago")
    func format_2DaysAgo_returnsWeekday() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 172800),
            relativeTo: referenceDate
        )
        let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        #expect(weekdays.contains(result))
    }

    // MARK: - Week+ (formatted date)

    @Test("Returns abbreviated date format for 7+ days ago (same year)")
    func format_7DaysAgo_returnsFormattedDate() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 604800),
            relativeTo: referenceDate
        )
        // Should return abbreviated month and day, e.g., "Nov 7"
        #expect(result.contains(" "))
    }

    @Test("Returns abbreviated date format for 30 days ago (same year)")
    func format_30DaysAgo_returnsFormattedDate() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 2_592_000), // 30 days
            relativeTo: referenceDate
        )
        // Should return abbreviated month and day
        #expect(result.contains(" "))
    }

    // MARK: - Previous Year

    @Test("Returns date with year for previous year dates")
    func format_previousYear_includesYear() {
        // referenceDate is Nov 14, 2023 — go back ~365 days to 2022
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 31_536_000),
            relativeTo: referenceDate
        )
        // Should include year, e.g., "Nov 14, 2022"
        #expect(result.contains("2022"))
    }

    // MARK: - Boundary Tests

    @Test("Uses weekday name just before week threshold")
    func format_6DaysAgo_returnsWeekday() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 518400), // 6 days
            relativeTo: referenceDate
        )
        let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        #expect(weekdays.contains(result))
    }

    @Test("Uses date format at 7 days ago")
    func format_7Days_usesDateFormat() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 604800), // 7 days
            relativeTo: referenceDate
        )
        // Date format should contain a space (e.g., "Nov 7")
        #expect(result.contains(" "))
    }
}
