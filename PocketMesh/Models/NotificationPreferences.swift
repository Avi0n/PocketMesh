import Foundation

/// Centralized notification preferences storage
@MainActor
@Observable
public final class NotificationPreferences {
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
        get { defaults.object(forKey: "notifyNewContacts") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "notifyNewContacts") }
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

    public init() {}
}
