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
            return date.formatted(.relative(presentation: .named))
        } else {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}
