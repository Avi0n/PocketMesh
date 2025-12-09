import SwiftUI

/// iMessage-style centered timestamp that updates dynamically.
///
/// Displays relative dates:
/// - Today: "1:15 PM"
/// - Yesterday: "Yesterday 1:15 PM"
/// - Same year: "Dec 1, 12:10 PM"
/// - Different year: "Dec 1, 2024, 12:10 PM"
///
/// Uses `TimelineView` to automatically refresh at sensible intervals,
/// ensuring "Today" becomes "Yesterday" at midnight without manual refresh.
struct MessageTimestampView: View {
    let date: Date

    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(formattedDate(relativeTo: context.date))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func formattedDate(relativeTo now: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            // Today: "1:15 PM"
            return date.formatted(date: .omitted, time: .shortened)
        } else if calendar.isDateInYesterday(date) {
            // Yesterday: "Yesterday 1:15 PM"
            return "Yesterday " + date.formatted(date: .omitted, time: .shortened)
        } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            // Same year: "Dec 1, 12:10 PM"
            return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        } else {
            // Different year: "Dec 1, 2024, 12:10 PM"
            return date.formatted(.dateTime.month(.abbreviated).day().year().hour().minute())
        }
    }
}

#Preview("Today") {
    VStack(spacing: 20) {
        MessageTimestampView(date: Date())
        MessageTimestampView(date: Date().addingTimeInterval(-3600)) // 1 hour ago
    }
    .padding()
}

#Preview("Yesterday") {
    MessageTimestampView(date: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)
        .padding()
}

#Preview("Last Week") {
    MessageTimestampView(date: Calendar.current.date(byAdding: .day, value: -5, to: Date())!)
        .padding()
}

#Preview("Last Year") {
    MessageTimestampView(date: Calendar.current.date(byAdding: .year, value: -1, to: Date())!)
        .padding()
}
