import Foundation
import UserNotifications

// MARK: - Notification Categories

/// Notification category identifiers
public enum NotificationCategory: String, Sendable {
    case directMessage = "DIRECT_MESSAGE"
    case channelMessage = "CHANNEL_MESSAGE"
    case roomMessage = "ROOM_MESSAGE"
    case lowBattery = "LOW_BATTERY"
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

    /// Current authorization status
    public private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// Callback for when a quick reply action is triggered
    /// CRITICAL: Must be @MainActor to ensure callback body executes on main thread.
    /// Without @MainActor, the callback runs on a background executor even when
    /// called from MainActor context, causing "Call must be made on main thread" crashes.
    public var onQuickReply: (@MainActor @Sendable (_ contactID: UUID, _ text: String) async -> Void)?

    /// Callback for when a notification is tapped
    /// CRITICAL: Must be @MainActor - see onQuickReply comment.
    public var onNotificationTapped: (@MainActor @Sendable (_ contactID: UUID) async -> Void)?

    /// Callback for when mark as read action is triggered
    /// CRITICAL: Must be @MainActor - see onQuickReply comment.
    public var onMarkAsRead: (@MainActor @Sendable (_ contactID: UUID, _ messageID: UUID) async -> Void)?

    /// Whether notifications are enabled by user preference
    private var notificationsEnabled: Bool {
        get {
            UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "notificationsEnabled")
        }
    }

    /// Badge count
    public private(set) var badgeCount: Int = 0

    /// Stored draft messages for contacts (keyed by contactID string).
    /// Used when quick reply fails due to disconnection.
    ///
    /// - Important: Drafts are stored in-memory ONLY and will be LOST if:
    ///   - The app is force quit by the user
    ///   - The app is terminated by iOS due to memory pressure
    ///   - The device is restarted
    ///
    /// Drafts persist until consumed via `consumeDraft(for:)` or until the app
    /// terminates. If disk persistence is needed in the future, consider SwiftData
    /// storage with appropriate cleanup policies.
    @MainActor private var pendingDrafts: [String: String] = [:]

    // MARK: - Initialization

    public override init() {
        super.init()
    }

    /// Sets up notification categories and checks current authorization status.
    public func setup() async {
        await registerCategories()
        await checkAuthorizationStatus()

        // Automatically request authorization if not determined yet
        if authorizationStatus == .notDetermined {
            await requestAuthorization()
        }
    }

    // MARK: - Authorization

    /// Requests notification authorization.
    @discardableResult
    public func requestAuthorization() async -> Bool {
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

        // Room message category (no reply action)
        let roomMessageCategory = UNNotificationCategory(
            identifier: NotificationCategory.roomMessage.rawValue,
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

        let categories: Set<UNNotificationCategory> = [
            directMessageCategory,
            channelMessageCategory,
            roomMessageCategory,
            lowBatteryCategory
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

    /// Posts a notification for a room message.
    public func postRoomMessageNotification(
        roomName: String,
        senderName: String?,
        messageText: String,
        messageID: UUID
    ) async {
        guard isAuthorized && notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = roomName
        if let sender = senderName {
            content.body = "\(sender): \(messageText)"
        } else {
            content.body = messageText
        }
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.roomMessage.rawValue
        content.userInfo = [
            "roomName": roomName,
            "messageID": messageID.uuidString,
            "type": "roomMessage"
        ]
        content.threadIdentifier = "room-\(roomName)"

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

    /// Posts a notification that a new contact was discovered.
    public func postNewContactNotification(
        contactName: String,
        contactID: UUID
    ) async {
        guard isAuthorized && notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "New Contact Discovered"
        content.body = "\(contactName) is now available on the mesh"
        content.sound = .default
        content.userInfo = [
            "contactID": contactID.uuidString,
            "type": "newContact"
        ]

        let request = UNNotificationRequest(
            identifier: "new-contact-\(contactID.uuidString)",
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

    /// Posts a notification that a quick reply failed to send.
    public func postQuickReplyFailedNotification(
        contactName: String,
        contactID: UUID
    ) async {
        guard isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Message Not Sent"
        content.body = "Your reply to \(contactName) couldn't be sent. Device is disconnected."
        content.sound = .default
        content.categoryIdentifier = NotificationCategory.directMessage.rawValue
        content.userInfo = [
            "contactID": contactID.uuidString,
            "type": "quickReplyFailed"
        ]

        let request = UNNotificationRequest(
            identifier: "quick-reply-failed-\(contactID.uuidString)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // Notification failed to post
        }
    }

    // MARK: - Draft Message Storage

    /// Saves a draft message for a contact when quick reply fails.
    ///
    /// - Important: Draft is stored in-memory only and will be lost if app is force quit.
    ///
    /// - Parameters:
    ///   - contactID: The UUID of the contact
    ///   - text: The draft message text to save
    @MainActor public func saveDraft(for contactID: UUID, text: String) {
        pendingDrafts[contactID.uuidString] = text
    }

    /// Retrieves and removes a draft message for a contact.
    ///
    /// The draft is removed from storage after retrieval (consumed).
    /// Returns `nil` if no draft exists for the contact.
    ///
    /// - Parameter contactID: The UUID of the contact
    /// - Returns: The draft text if one exists, otherwise `nil`
    @MainActor public func consumeDraft(for contactID: UUID) -> String? {
        let key = contactID.uuidString
        guard let draft = pendingDrafts[key] else { return nil }
        pendingDrafts.removeValue(forKey: key)
        return draft
    }

}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationService: @preconcurrency UNUserNotificationCenterDelegate {

    /// Called when a notification is received while the app is in the foreground.
    /// With @preconcurrency, this method inherits @MainActor from the class.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        // Show banner and sound even when app is active
        return [.banner, .sound, .badge]
    }

    /// Called when the user interacts with a notification.
    /// With @preconcurrency, this method inherits @MainActor from the class,
    /// so we can directly access self and all @Observable properties.
    public func userNotificationCenter(
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
            await onQuickReply?(contactID, replyText)

        case NotificationAction.markRead.rawValue:
            // Handle mark as read
            guard let contactIDString = userInfo["contactID"] as? String,
                  let contactID = UUID(uuidString: contactIDString),
                  let messageIDString = userInfo["messageID"] as? String,
                  let messageID = UUID(uuidString: messageIDString) else {
                return
            }

            await onMarkAsRead?(contactID, messageID)

        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification
            if let contactIDString = userInfo["contactID"] as? String,
               let contactID = UUID(uuidString: contactIDString) {
                await onNotificationTapped?(contactID)
            }

        default:
            break
        }
    }
}
