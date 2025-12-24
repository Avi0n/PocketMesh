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

    /// Callback for when a new contact discovered notification is tapped
    /// CRITICAL: Must be @MainActor - see onQuickReply comment.
    public var onNewContactNotificationTapped: (@MainActor @Sendable (_ contactID: UUID) async -> Void)?

    /// Callback for when mark as read action is triggered
    /// CRITICAL: Must be @MainActor - see onQuickReply comment.
    public var onMarkAsRead: (@MainActor @Sendable (_ contactID: UUID, _ messageID: UUID) async -> Void)?

    /// Callback for when mark as read action is triggered on a channel message
    /// Includes deviceID to correctly identify the channel across multiple connected devices
    /// CRITICAL: Must be @MainActor - see onQuickReply comment.
    public var onChannelMarkAsRead: (@MainActor @Sendable (_ deviceID: UUID, _ channelIndex: UInt8, _ messageID: UUID) async -> Void)?

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

    // MARK: - Active Conversation Tracking

    /// Currently active contact ID (user is viewing this chat)
    public var activeContactID: UUID?

    /// Currently active channel index (user is viewing this channel)
    public var activeChannelIndex: UInt8?

    /// Device ID for the active channel
    public var activeChannelDeviceID: UUID?

    // MARK: - Badge Management

    /// Callback to get total unread count from data layer
    /// Returns (contactUnread, channelUnread) tuple for preference-aware calculation
    public var getBadgeCount: (@Sendable () async -> (contacts: Int, channels: Int))?

    /// Cached notification preferences (refreshed on each badge update)
    private var cachedPreferences: NotificationPreferences?

    /// Last time preferences were refreshed
    private var preferencesLastRefreshed: Date = .distantPast

    /// Pending badge update task (for debouncing rapid updates)
    private var pendingBadgeUpdate: Task<Void, Never>?

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

        // Check granular preference (uses cached preferences)
        guard preferences.contactMessagesEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = contactName
        content.body = messageText
        content.sound = preferences.soundEnabled ? .default : nil
        content.categoryIdentifier = NotificationCategory.directMessage.rawValue
        content.userInfo = [
            "contactID": contactID.uuidString,
            "messageID": messageID.uuidString,
            "type": "directMessage"
        ]
        content.threadIdentifier = contactID.uuidString

        // Use current badge count (will be updated after posting)
        if preferences.badgeEnabled {
            content.badge = NSNumber(value: badgeCount + 1)
        }

        let request = UNNotificationRequest(
            identifier: messageID.uuidString,
            content: content,
            trigger: nil
        )

        // Post notification immediately - don't block on badge calculation
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // Notification failed to post - log but don't throw
        }

        // Update badge from database AFTER posting (non-blocking for notification display)
        if preferences.badgeEnabled {
            await updateBadgeCount()
        }
    }

    /// Posts a notification for a channel message.
    public func postChannelMessageNotification(
        channelName: String,
        channelIndex: UInt8,
        deviceID: UUID,
        senderName: String?,
        messageText: String,
        messageID: UUID
    ) async {
        guard isAuthorized && notificationsEnabled else { return }

        // Check granular preference (uses cached preferences)
        guard preferences.channelMessagesEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "#\(channelName)"
        if let sender = senderName {
            content.body = "\(sender): \(messageText)"
        } else {
            content.body = messageText
        }
        content.sound = preferences.soundEnabled ? .default : nil
        content.categoryIdentifier = NotificationCategory.channelMessage.rawValue
        content.userInfo = [
            "channelIndex": Int(channelIndex),
            "deviceID": deviceID.uuidString,
            "messageID": messageID.uuidString,
            "type": "channelMessage"
        ]
        content.threadIdentifier = "channel-\(deviceID.uuidString)-\(channelIndex)"

        // Use current badge count (will be updated after posting)
        if preferences.badgeEnabled {
            content.badge = NSNumber(value: badgeCount + 1)
        }

        let request = UNNotificationRequest(
            identifier: messageID.uuidString,
            content: content,
            trigger: nil
        )

        // Post notification immediately
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            // Notification failed to post
        }

        // Update badge from database AFTER posting
        if preferences.badgeEnabled {
            await updateBadgeCount()
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

        // Check granular preference
        let preferences = NotificationPreferences()
        guard preferences.roomMessagesEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = roomName
        if let sender = senderName {
            content.body = "\(sender): \(messageText)"
        } else {
            content.body = messageText
        }
        content.sound = preferences.soundEnabled ? .default : nil
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

        // Check granular preference
        let preferences = NotificationPreferences()
        guard preferences.newContactDiscoveredEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "New Contact Discovered"
        content.body = "\(contactName) is now available on the mesh"
        content.sound = preferences.soundEnabled ? .default : nil
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

    // MARK: - Badge Management Methods

    /// Refresh preferences if stale (older than 5 seconds)
    /// Note: 5s cache prevents excessive UserDefaults reads during rapid message arrival
    private func refreshPreferencesIfNeeded() {
        let now = Date()
        if cachedPreferences == nil || now.timeIntervalSince(preferencesLastRefreshed) > 5.0 {
            cachedPreferences = NotificationPreferences()
            preferencesLastRefreshed = now
        }
    }

    /// Get current preferences (uses cache)
    private var preferences: NotificationPreferences {
        refreshPreferencesIfNeeded()
        return cachedPreferences ?? NotificationPreferences()
    }

    /// Updates the app badge count from the database.
    /// Uses 100ms debounce to handle rapid-fire message arrivals efficiently.
    public func updateBadgeCount() async {
        // Cancel any pending update to debounce rapid arrivals
        pendingBadgeUpdate?.cancel()

        // Create new debounced update
        pendingBadgeUpdate = Task {
            // Wait 100ms before actually updating (allows batching multiple arrivals)
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }

            await performBadgeUpdate()
        }

        // Wait for the update to complete
        await pendingBadgeUpdate?.value
    }

    /// Performs the actual badge update (called by debounced updateBadgeCount)
    private func performBadgeUpdate() async {
        guard let getBadgeCount else {
            return
        }

        refreshPreferencesIfNeeded()
        let prefs = preferences

        // If badge is disabled, clear it and return
        guard prefs.badgeEnabled else {
            badgeCount = 0
            do {
                try await UNUserNotificationCenter.current().setBadgeCount(0)
            } catch {
                // Failed to clear badge
            }
            return
        }

        // Get counts from data layer via callback
        let counts = await getBadgeCount()

        var totalUnread = 0

        // Only include contact messages if preference enabled
        if prefs.contactMessagesEnabled {
            totalUnread += counts.contacts
        }

        // Only include channel messages if preference enabled
        if prefs.channelMessagesEnabled {
            totalUnread += counts.channels
        }

        // Update badge
        badgeCount = totalUnread
        do {
            try await UNUserNotificationCenter.current().setBadgeCount(totalUnread)
        } catch {
            // Failed to set badge count
        }
    }

    /// Remove a delivered notification by message ID
    public func removeDeliveredNotification(messageID: UUID) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: [messageID.uuidString]
        )
    }

    /// Remove all delivered notifications for a contact
    public func removeDeliveredNotifications(forContactID contactID: UUID) async {
        let center = UNUserNotificationCenter.current()
        let notifications = await center.deliveredNotifications()
        let idsToRemove = notifications
            .filter { $0.request.content.userInfo["contactID"] as? String == contactID.uuidString }
            .map(\.request.identifier)

        if !idsToRemove.isEmpty {
            center.removeDeliveredNotifications(withIdentifiers: idsToRemove)
        }
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
        let userInfo = notification.request.content.userInfo

        // Check if this is a direct message notification for the active chat
        if let contactIDString = userInfo["contactID"] as? String,
           let contactID = UUID(uuidString: contactIDString),
           contactID == activeContactID {
            // User is viewing this chat - don't show notification
            return []
        }

        // Check if this is a channel message notification for the active channel
        // Must check BOTH channelIndex AND deviceID for multi-device scenarios
        if let channelIndex = userInfo["channelIndex"] as? Int,
           let deviceIDString = userInfo["deviceID"] as? String,
           let deviceID = UUID(uuidString: deviceIDString),
           UInt8(channelIndex) == activeChannelIndex,
           deviceID == activeChannelDeviceID {
            // User is viewing this channel - don't show notification
            return []
        }

        // Show banner and sound for other notifications
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
            let messageIDString = userInfo["messageID"] as? String
            let messageID = messageIDString.flatMap { UUID(uuidString: $0) }

            if let contactIDString = userInfo["contactID"] as? String,
               let contactID = UUID(uuidString: contactIDString),
               let messageID {
                // Direct message mark as read
                await onMarkAsRead?(contactID, messageID)
            } else if let channelIndex = userInfo["channelIndex"] as? Int,
                      let deviceIDString = userInfo["deviceID"] as? String,
                      let deviceID = UUID(uuidString: deviceIDString),
                      let messageID {
                // Channel message mark as read (includes deviceID for multi-device)
                await onChannelMarkAsRead?(deviceID, UInt8(channelIndex), messageID)
            }

        case UNNotificationDefaultActionIdentifier:
            // User tapped the notification
            if let contactIDString = userInfo["contactID"] as? String,
               let contactID = UUID(uuidString: contactIDString) {
                let notificationType = userInfo["type"] as? String
                if notificationType == "newContact" {
                    await onNewContactNotificationTapped?(contactID)
                } else {
                    await onNotificationTapped?(contactID)
                }
            }

        default:
            break
        }
    }
}
