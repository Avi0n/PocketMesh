import Foundation

/// Thread-safe notification preferences (read-only snapshot from UserDefaults)
public struct NotificationPreferences: Sendable {
    public let contactMessagesEnabled: Bool
    public let channelMessagesEnabled: Bool
    public let roomMessagesEnabled: Bool
    public let newContactDiscoveredEnabled: Bool
    public let reactionNotificationsEnabled: Bool
    public let soundEnabled: Bool
    public let badgeEnabled: Bool
    public let lowBatteryEnabled: Bool

    public init() {
        let defaults = UserDefaults.standard
        self.contactMessagesEnabled = defaults.object(forKey: "notifyContactMessages") as? Bool ?? true
        self.channelMessagesEnabled = defaults.object(forKey: "notifyChannelMessages") as? Bool ?? true
        self.roomMessagesEnabled = defaults.object(forKey: "notifyRoomMessages") as? Bool ?? true
        self.newContactDiscoveredEnabled = defaults.object(forKey: "notifyNewContacts") as? Bool ?? true
        self.reactionNotificationsEnabled = defaults.object(forKey: "notifyReactions") as? Bool ?? true
        self.soundEnabled = defaults.object(forKey: "notificationSoundEnabled") as? Bool ?? true
        self.badgeEnabled = defaults.object(forKey: "notificationBadgeEnabled") as? Bool ?? true
        self.lowBatteryEnabled = defaults.object(forKey: "notifyLowBattery") as? Bool ?? true
    }
}

/// Observable store for notification preferences (used by Settings UI for two-way binding)
@MainActor
@Observable
public final class NotificationPreferencesStore {
    private let defaults = UserDefaults.standard

    // MARK: - Message Notifications

    /// Enable notifications for contact (direct) messages
    public var contactMessagesEnabled: Bool {
        get { defaults.object(forKey: "notifyContactMessages") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notifyContactMessages") }
    }

    /// Enable notifications for channel messages
    public var channelMessagesEnabled: Bool {
        get { defaults.object(forKey: "notifyChannelMessages") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notifyChannelMessages") }
    }

    /// Enable notifications for room messages
    public var roomMessagesEnabled: Bool {
        get { defaults.object(forKey: "notifyRoomMessages") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notifyRoomMessages") }
    }

    /// Enable notifications when new contacts are discovered
    public var newContactDiscoveredEnabled: Bool {
        get { defaults.object(forKey: "notifyNewContacts") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notifyNewContacts") }
    }

    /// Enable notifications when someone reacts to your messages
    public var reactionNotificationsEnabled: Bool {
        get { defaults.object(forKey: "notifyReactions") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notifyReactions") }
    }

    // MARK: - Sound & Badge

    /// Enable notification sounds
    public var soundEnabled: Bool {
        get { defaults.object(forKey: "notificationSoundEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notificationSoundEnabled") }
    }

    /// Enable badge count on app icon
    public var badgeEnabled: Bool {
        get { defaults.object(forKey: "notificationBadgeEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notificationBadgeEnabled") }
    }

    // MARK: - Low Battery

    /// Enable low battery warning notifications
    public var lowBatteryEnabled: Bool {
        get { defaults.object(forKey: "notifyLowBattery") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notifyLowBattery") }
    }

    public init() {}
}
