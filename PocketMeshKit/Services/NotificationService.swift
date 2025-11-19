import Foundation
import UserNotifications
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh.app", category: "Notifications")

@MainActor
public final class NotificationService {

    public static let shared = NotificationService()

    private init() {}

    public func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            logger.info("Notification authorization: \(granted)")
            return granted
        } catch {
            logger.error("Failed to request notification authorization: \(error.localizedDescription)")
            return false
        }
    }

    public func scheduleMessageNotification(from contactName: String, contactPublicKey: Data, text: String) {
        let content = UNMutableNotificationContent()
        content.title = "New Message"
        content.subtitle = "from \(contactName)"
        content.body = text
        content.sound = .default
        content.categoryIdentifier = "MESSAGE"

        // Add contact info to userInfo for reply handling
        content.userInfo = [
            "contactPublicKey": contactPublicKey.base64EncodedString(),
            "contactName": contactName
        ]

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Immediate
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                logger.error("Failed to schedule notification: \(error.localizedDescription)")
            } else {
                logger.info("Message notification scheduled")
            }
        }
    }

    public func scheduleLowBatteryWarning(voltage: Double) {
        let content = UNMutableNotificationContent()
        content.title = "Low Battery"
        content.body = "Your MeshCore device battery is low (\(String(format: "%.2f", voltage))V)"
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "low-battery",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    public func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0)
    }
}
