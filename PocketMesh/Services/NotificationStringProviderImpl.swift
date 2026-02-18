import Foundation
import PocketMeshServices

/// App-layer implementation of NotificationStringProvider using L10n.
struct NotificationStringProviderImpl: NotificationStringProvider {
    func discoveryNotificationTitle(for type: ContactType) -> String {
        switch type {
        case .chat:
            L10n.Localizable.Notifications.Discovery.contact
        case .repeater:
            L10n.Localizable.Notifications.Discovery.repeater
        case .room:
            L10n.Localizable.Notifications.Discovery.room
        }
    }

    var replyActionTitle: String { L10n.Localizable.Notifications.Action.reply }
    var sendButtonTitle: String { L10n.Localizable.Notifications.Action.send }
    var messagePlaceholder: String { L10n.Localizable.Notifications.Action.messagePlaceholder }
    var markAsReadActionTitle: String { L10n.Localizable.Notifications.Action.markAsRead }
}
