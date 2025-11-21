import Foundation

public extension Date {
    /// Returns relative time string showing minutes only (no seconds)
    func relativeTimeStringMinutesOnly() -> String {
        let now = Date()
        let timeInterval = abs(now.timeIntervalSince(self))

        let minutes = Int(timeInterval / 60)
        let hours = Int(timeInterval / 3600)
        let days = Int(timeInterval / 86400)

        if timeInterval < 60 {
            return "just now"
        } else if minutes < 60 {
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        } else if hours < 24 {
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        } else if days < 7 {
            return days == 1 ? "1 day ago" : "\(days) days ago"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            return formatter.string(from: self)
        }
    }
}
