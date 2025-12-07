import Foundation
import UserNotifications

// MARK: - Notification Categories

/// Notification category identifiers
public enum NotificationCategory: String, Sendable {
    case directMessage = "DIRECT_MESSAGE"
    case channelMessage = "CHANNEL_MESSAGE"
    case lowBattery = "LOW_BATTERY"
    case connectionLost = "CONNECTION_LOST"
}

/// Notification action identifiers
public enum NotificationAction: String, Sendable {
    case reply = "REPLY_ACTION"
    case markRead = "MARK_READ_ACTION"
    case dismiss = "DISMISS_ACTION"
}

// MARK: - Notification Service

/// Service for managing local notifications.
/// Handles message notifications, quick reply actions, and battery warnings.
@MainActor
@Observable
public final class NotificationService: NSObject {

    // MARK: - Properties

    /// Whether notification permissions are authorized
    public private(set) var isAuthorized: Bool = false

    /// Whether permissions have been requested
    public private(set) var hasRequestedPermission: Bool = false

    /// Current authorization status
    public private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// Callback for when a quick reply action is triggered
    public var onQuickReply: (@Sendable (_ contactID: UUID, _ text: String) async -> Void)?

    /// Callback for when a notification is tapped
    public var onNotificationTapped: (@Sendable (_ contactID: UUID) async -> Void)?

    /// Whether notifications are enabled by user preference
    private var notificationsEnabled: Bool = true

    /// Badge count
    public private(set) var badgeCount: Int = 0

    // MARK: - Initialization

    public override init() {
        super.init()
    }

    /// Sets up notification categories and checks current authorization status.
    public func setup() async {
        await registerCategories()
        await checkAuthorizationStatus()
    }

    // MARK: - Authorization

    /// Requests notification authorization.
    @discardableResult
    public func requestAuthorization() async -> Bool {
        hasRequestedPermission = true

        do {
            let options: UNAuthorizationOptions = [.alert, .sound, .badge]
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: options)
            isAuthorized = granted
            authorizationStatus = granted ? .authorized : .denied
            return granted
        } catch {
            isAuthorized = false
            authorizationStatus = .denied
            return false
        }
    }

    /// Checks current authorization status.
    public func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
        isAuthorized = settings.authorizationStatus == .authorized

        // Check if we've requested before
        hasRequestedPermission = settings.authorizationStatus != .notDetermined
    }

    // MARK: - Category Registration

    /// Registers notification categories with actions.
    private func registerCategories() async {
        // Reply action with text input
        let replyAction = UNTextInputNotificationAction(
            identifier: NotificationAction.reply.rawValue,
            title: "Reply",
            options: [],
            textInputButtonTitle: "Send",
            textInputPlaceholder: "Message..."
        )

        // Mark as read action
        let markReadAction = UNNotificationAction(
            identifier: NotificationAction.markRead.rawValue,
            title: "Mark as Read",
            options: []
        )

        // Direct message category
        let directMessageCategory = UNNotificationCategory(
            identifier: NotificationCategory.directMessage.rawValue,
            actions: [replyAction, markReadAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // Channel message category (no reply action)
        let channelMessageCategory = UNNotificationCategory(
            identifier: NotificationCategory.channelMessage.rawValue,
            actions: [markReadAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        // Low battery category
        let lowBatteryCategory = UNNotificationCategory(
            identifier: NotificationCategory.lowBattery.rawValue,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        // Connection lost category
        let connectionLostCategory = UNNotificationCategory(
            identifier: NotificationCategory.connectionLost.rawValue,
            actions: [],
            intentIdentifiers: [],
            options: []
        )

        let categories: Set<UNNotificationCategory> = [
            directMessageCategory,
            channelMessageCategory,
            lowBatteryCategory,
            connectionLostCategory
        ]

        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }

    // MARK: - Sending Notifications

    /// Posts a notification for a direct message.
    public func postDirectMessageNotification(
        from contactName: String,
        contactID: UUID,
        messageText: String,
        messageID: UUID
    ) async {
        guard isAuthorized && notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = contactName
        content.body = messageText
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.directMessage.rawValue
        content.userInfo = [
            "contactID": contactID.uuidString,
            "messageID": messageID.uuidString,
            "type": "directMessage"
        ]
        content.threadIdentifier = contactID.uuidString

        badgeCount += 1
        content.badge = NSNumber(value: badgeCount)

        let request = UNNotificationRequest(
            identifier: messageID.uuidString,
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // Notification failed to post - log but don't throw
        }
    }

    /// Posts a notification for a channel message.
    public func postChannelMessageNotification(
        channelName: String,
        channelIndex: UInt8,
        senderName: String?,
        messageText: String,
        messageID: UUID
    ) async {
        guard isAuthorized && notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "#\(channelName)"
        if let sender = senderName {
            content.body = "\(sender): \(messageText)"
        } else {
            content.body = messageText
        }
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.channelMessage.rawValue
        content.userInfo = [
            "channelIndex": Int(channelIndex),
            "messageID": messageID.uuidString,
            "type": "channelMessage"
        ]
        content.threadIdentifier = "channel-\(channelIndex)"

        badgeCount += 1
        content.badge = NSNumber(value: badgeCount)

        let request = UNNotificationRequest(
            identifier: messageID.uuidString,
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // Notification failed to post
        }
    }

    /// Posts a low battery warning notification.
    public func postLowBatteryNotification(
        deviceName: String,
        batteryPercentage: Int
    ) async {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Low Battery"
        content.body = "\(deviceName) battery is at \(batteryPercentage)%"
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.lowBattery.rawValue
        content.userInfo = [
            "type": "lowBattery",
            "batteryPercentage": batteryPercentage
        ]

        // Use device name as identifier to avoid duplicate notifications
        let request = UNNotificationRequest(
            identifier: "low-battery-\(deviceName)",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // Notification failed to post
        }
    }

    /// Posts a connection lost notification.
    public func postConnectionLostNotification(deviceName: String) async {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Connection Lost"
        content.body = "Lost connection to \(deviceName)"
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.connectionLost.rawValue
        content.userInfo = [
            "type": "connectionLost"
        ]

        let request = UNNotificationRequest(
            identifier: "connection-lost",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // Notification failed to post
        }
    }

    // MARK: - Badge Management

    /// Clears the badge count.
    public func clearBadge() async {
        badgeCount = 0
        do {
            try await UNUserNotificationCenter.current().setBadgeCount(0)
        } catch {
            // Badge update failed
        }
    }

    /// Decrements the badge count by a specific amount.
    public func decrementBadge(by count: Int = 1) async {
        badgeCount = max(0, badgeCount - count)
        do {
            try await UNUserNotificationCenter.current().setBadgeCount(badgeCount)
        } catch {
            // Badge update failed
        }
    }

    /// Sets the badge count to a specific value.
    public func setBadge(count: Int) async {
        badgeCount = count
        do {
            try await UNUserNotificationCenter.current().setBadgeCount(count)
        } catch {
            // Badge update failed
        }
    }

    // MARK: - Notification Management

    /// Removes all pending notifications for a contact.
    public func removeNotifications(for contactID: UUID) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: [contactID.uuidString]
        )
    }

    /// Removes all pending notifications for a channel.
    public func removeChannelNotifications(channelIndex: UInt8) {
        let threadID = "channel-\(channelIndex)"
        UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
            let idsToRemove = notifications
                .filter { $0.request.content.threadIdentifier == threadID }
                .map { $0.request.identifier }
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: idsToRemove)
        }
    }

    /// Removes all delivered notifications.
    public func removeAllNotifications() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    // MARK: - User Preferences

    /// Enables or disables notifications (user preference, not system permission).
    public func setNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: UNUserNotificationCenterDelegate {

    /// Called when a notification is received while the app is in the foreground.
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Show banner and sound even when app is active
        return [.banner, .sound, .badge]
    }

    /// Called when the user interacts with a notification.
    nonisolated public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo

        switch response.actionIdentifier {
        case NotificationAction.reply.rawValue:
            // Handle quick reply
            guard let textResponse = response as? UNTextInputNotificationResponse,
                  let contactIDString = userInfo["contactID"] as? String,
                  let contactID = UUID(uuidString: contactIDString) else {
                return
            }

            let replyText = textResponse.userText
            Task { @MainActor in
                await self.onQuickReply?(contactID, replyText)
            }

        case NotificationAction.markRead.rawValue:
            // Handle mark as read - could update unread count
            break

        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification
            if let contactIDString = userInfo["contactID"] as? String,
               let contactID = UUID(uuidString: contactIDString) {
                Task { @MainActor in
                    await self.onNotificationTapped?(contactID)
                }
            }

        default:
            break
        }
    }
}
