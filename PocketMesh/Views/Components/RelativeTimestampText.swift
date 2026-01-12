import SwiftUI

/// Displays a relative timestamp like "2m ago", "1h ago", "Yesterday"
struct RelativeTimestampText: View {
    let timestamp: UInt32

    private enum Constants {
        static let minute: TimeInterval = 60
        static let hour: TimeInterval = 3_600
        static let day: TimeInterval = 86_400
        static let twoDays: TimeInterval = 172_800
        static let week: TimeInterval = 604_800
    }

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
        let interval = now.timeIntervalSince(date)

        if interval < Constants.minute {
            return "Now"
        } else if interval < Constants.hour {
            let minutes = Int(interval / Constants.minute)
            return "\(minutes)m ago"
        } else if interval < Constants.day {
            let hours = Int(interval / Constants.hour)
            return "\(hours)h ago"
        } else if interval < Constants.twoDays {
            return "Yesterday"
        } else if interval < Constants.week {
            let days = Int(interval / Constants.day)
            return "\(days)d ago"
        } else {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
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
