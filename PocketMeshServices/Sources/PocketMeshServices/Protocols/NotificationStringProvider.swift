import Foundation

/// Provides localized strings for notifications.
///
/// This protocol allows the app layer to inject localized strings into
/// PocketMeshServices without the service layer depending on L10n directly.
public protocol NotificationStringProvider: Sendable {
    /// Returns the notification title for a discovered contact of the given type.
    /// - Parameter type: The type of contact discovered
    /// - Returns: Localized notification title (e.g., "New Repeater Discovered")
    func discoveryNotificationTitle(for type: ContactType) -> String

    /// Returns the localized title for the "Reply" notification action.
    var replyActionTitle: String { get }

    /// Returns the localized title for the "Send" button in notification quick reply.
    var sendButtonTitle: String { get }

    /// Returns the localized placeholder for the notification quick reply text input.
    var messagePlaceholder: String { get }

    /// Returns the localized title for the "Mark as Read" notification action.
    var markAsReadActionTitle: String { get }
}
