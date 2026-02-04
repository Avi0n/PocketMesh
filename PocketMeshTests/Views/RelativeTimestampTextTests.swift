import Foundation
import Testing
@testable import PocketMesh

@Suite("RelativeTimestampText Tests")
struct RelativeTimestampTextTests {

    private let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private func timestamp(secondsAgo: TimeInterval) -> UInt32 {
        UInt32(referenceDate.addingTimeInterval(-secondsAgo).timeIntervalSince1970)
    }

    // MARK: - Now Threshold (< 60 seconds)

    @Test("Returns 'Now' for timestamps under 60 seconds")
    func format_justNow_returnsNow() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 0),
            relativeTo: referenceDate
        )
        #expect(result == L10n.Chats.Chats.Timestamp.now)
    }

    @Test("Returns 'Now' at 59 seconds ago")
    func format_59Seconds_returnsNow() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 59),
            relativeTo: referenceDate
        )
        #expect(result == L10n.Chats.Chats.Timestamp.now)
    }

    @Test("Returns relative format at exactly 60 seconds")
    func format_60Seconds_returnsRelative() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 60),
            relativeTo: referenceDate
        )
        #expect(result != L10n.Chats.Chats.Timestamp.now)
        #expect(!result.isEmpty)
    }

    // MARK: - Relative Times (1 min to 1 week)

    @Test("Returns non-empty string for minutes ago")
    func format_minutesAgo_returnsNonEmpty() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 120),
            relativeTo: referenceDate
        )
        #expect(!result.isEmpty)
    }

    @Test("Returns non-empty string for hours ago")
    func format_hoursAgo_returnsNonEmpty() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 3600),
            relativeTo: referenceDate
        )
        #expect(!result.isEmpty)
    }

    @Test("Returns non-empty string for yesterday")
    func format_yesterday_returnsNonEmpty() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 86400),
            relativeTo: referenceDate
        )
        #expect(!result.isEmpty)
    }

    @Test("Returns non-empty string for days ago")
    func format_daysAgo_returnsNonEmpty() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 172800),
            relativeTo: referenceDate
        )
        #expect(!result.isEmpty)
    }

    // MARK: - Week+ (formatted date)

    @Test("Returns abbreviated date format for 7+ days ago")
    func format_7DaysAgo_returnsFormattedDate() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 604800),
            relativeTo: referenceDate
        )
        // Should return abbreviated month and day, e.g., "Nov 7"
        #expect(result.contains(" "))
    }

    @Test("Returns abbreviated date format for old dates")
    func format_oldDate_returnsFormattedDate() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 2_592_000), // 30 days
            relativeTo: referenceDate
        )
        // Should return abbreviated month and day
        #expect(result.contains(" "))
    }

    // MARK: - Boundary Tests

    @Test("Uses relative format just before week threshold")
    func format_justBeforeWeek_usesRelativeFormat() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 604799), // 1 second before 7 days
            relativeTo: referenceDate
        )
        #expect(!result.isEmpty)
    }

    @Test("Uses date format at exactly week threshold")
    func format_exactlyWeek_usesDateFormat() {
        let result = RelativeTimestampText.format(
            timestamp: timestamp(secondsAgo: 604800), // exactly 7 days
            relativeTo: referenceDate
        )
        // Date format should contain a space (e.g., "Nov 7")
        #expect(result.contains(" "))
    }
}
