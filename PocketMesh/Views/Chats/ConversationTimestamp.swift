import SwiftUI

struct ConversationTimestamp: View {
    let date: Date
    var font: Font = .caption

    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(formattedDate(relativeTo: context.date))
                .font(font)
                .foregroundStyle(.secondary)
        }
    }

    private func formattedDate(relativeTo now: Date) -> String {
        let calendar = Calendar.current

        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if let daysAgo = calendar.dateComponents([.day], from: date, to: now).day, daysAgo < 7 {
            return date.formatted(.dateTime.weekday(.wide))
        } else if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        } else {
            return date.formatted(.dateTime.month(.abbreviated).day().year())
        }
    }
}
