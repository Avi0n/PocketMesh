import SwiftUI

/// Displays a relative timestamp like "2m ago", "1h ago", "Yesterday"
struct RelativeTimestampText: View {
    let timestamp: UInt32

    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(formattedTimestamp(relativeTo: context.date))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var date: Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp))
    }

    private func formattedTimestamp(relativeTo now: Date) -> String {
        let interval = now.timeIntervalSince(date)

        if interval < 60 {
            return "Now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else if interval < 172800 {
            return "Yesterday"
        } else if interval < 604800 {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        } else {
            // Older than a week, show date
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
