import SwiftUI

/// Displays a relative timestamp using Apple's localized relative date formatting
struct RelativeTimestampText: View {
    let timestamp: UInt32

    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(Self.format(timestamp: timestamp, relativeTo: context.date))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// Formats a timestamp relative to the given date. Exposed for testing.
    static func format(timestamp: UInt32, relativeTo now: Date) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let calendar = Calendar.current

        let startOfNow = calendar.startOfDay(for: now)
        let startOfDate = calendar.startOfDay(for: date)
        let daysAgo = calendar.dateComponents([.day], from: startOfDate, to: startOfNow).day ?? 0

        if daysAgo == 0 {
            return date.formatted(date: .omitted, time: .shortened)
        }

        if daysAgo == 1 {
            return "Yesterday"
        }

        if daysAgo < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        }

        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }

        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}

#Preview {
    VStack(alignment: .trailing, spacing: 8) {
        RelativeTimestampText(timestamp: UInt32(Date().timeIntervalSince1970))
        RelativeTimestampText(timestamp: UInt32(Date().addingTimeInterval(-120).timeIntervalSince1970))
        RelativeTimestampText(timestamp: UInt32(Date().addingTimeInterval(-3600).timeIntervalSince1970))
        RelativeTimestampText(timestamp: UInt32(Date().addingTimeInterval(-86400).timeIntervalSince1970))
        RelativeTimestampText(timestamp: UInt32(Date().addingTimeInterval(-259200).timeIntervalSince1970))
    }
    .padding()
}
