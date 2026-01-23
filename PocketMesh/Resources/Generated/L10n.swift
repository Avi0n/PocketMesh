// swiftlint:disable all
// Generated using SwiftGen — https://github.com/SwiftGen/SwiftGen

import Foundation

// swiftlint:disable superfluous_disable_command file_length implicit_return prefer_self_in_static_references

// MARK: - Strings

// swiftlint:disable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:disable nesting type_body_length type_name vertical_whitespace_opening_braces
public enum L10n {
  public enum Chats {
    }
  public enum Contacts {
    }
  public enum Localizable {
    public enum Accessibility {
      /// VoiceOver announcement when viewing cached data while disconnected from device
      public static let viewingCachedData = L10n.tr("Localizable", "accessibility.viewingCachedData", fallback: "Viewing cached data. Connect to device for updates.")
    }
    public enum Alert {
      public enum ConnectionFailed {
        /// Default message when device connection fails
        public static let defaultMessage = L10n.tr("Localizable", "alert.connectionFailed.defaultMessage", fallback: "Unable to connect to device.")
        /// Button to remove failed pairing and retry connection
        public static let removeAndRetry = L10n.tr("Localizable", "alert.connectionFailed.removeAndRetry", fallback: "Remove & Try Again")
        /// Alert title when device connection fails
        public static let title = L10n.tr("Localizable", "alert.connectionFailed.title", fallback: "Connection Failed")
      }
      public enum CouldNotConnect {
        /// Message suggesting another app may be connected to the device
        public static let otherAppMessage = L10n.tr("Localizable", "alert.couldNotConnect.otherAppMessage", fallback: "Ensure no other app is connected to the device, then try again.")
        /// Alert title when connection cannot be established
        public static let title = L10n.tr("Localizable", "alert.couldNotConnect.title", fallback: "Could Not Connect")
      }
    }
    public enum Common {
      /// Standard cancel button for dialogs and sheets
      public static let cancel = L10n.tr("Localizable", "common.cancel", fallback: "Cancel")
      /// Standard close button for dismissing views
      public static let close = L10n.tr("Localizable", "common.close", fallback: "Close")
      /// Standard delete button for removing items
      public static let delete = L10n.tr("Localizable", "common.delete", fallback: "Delete")
      /// Standard done button for completing an action
      public static let done = L10n.tr("Localizable", "common.done", fallback: "Done")
      /// Standard edit button for entering edit mode
      public static let edit = L10n.tr("Localizable", "common.edit", fallback: "Edit")
      /// Standard confirmation button for dialogs
      public static let ok = L10n.tr("Localizable", "common.ok", fallback: "OK")
      /// Standard remove button for removing items from a list or group
      public static let remove = L10n.tr("Localizable", "common.remove", fallback: "Remove")
      /// Standard save button for persisting changes
      public static let save = L10n.tr("Localizable", "common.save", fallback: "Save")
      /// Button to retry a failed operation
      public static let tryAgain = L10n.tr("Localizable", "common.tryAgain", fallback: "Try Again")
    }
    public enum NodeType {
      /// Node type for a person or contact
      public static let contact = L10n.tr("Localizable", "nodeType.contact", fallback: "Contact")
      /// Node type for a mesh network repeater device
      public static let repeater = L10n.tr("Localizable", "nodeType.repeater", fallback: "Repeater")
      /// Node type for a group chat room
      public static let room = L10n.tr("Localizable", "nodeType.room", fallback: "Room")
    }
    public enum Permission {
      /// Permission level with full administrative access
      public static let admin = L10n.tr("Localizable", "permission.admin", fallback: "Admin")
      /// Permission level with limited access
      public static let guest = L10n.tr("Localizable", "permission.guest", fallback: "Guest")
      /// Permission level with standard access
      public static let member = L10n.tr("Localizable", "permission.member", fallback: "Member")
    }
    public enum Tabs {
      /// Tab bar title for the messaging/conversations screen
      public static let chats = L10n.tr("Localizable", "tabs.chats", fallback: "Chats")
      /// Tab bar title for the map screen showing node locations
      public static let map = L10n.tr("Localizable", "tabs.map", fallback: "Map")
      /// Tab bar title for the nodes/contacts list screen
      public static let nodes = L10n.tr("Localizable", "tabs.nodes", fallback: "Nodes")
      /// Tab bar title for the app settings screen
      public static let settings = L10n.tr("Localizable", "tabs.settings", fallback: "Settings")
      /// Tab bar title for the tools/utilities screen
      public static let tools = L10n.tr("Localizable", "tabs.tools", fallback: "Tools")
    }
  }
  public enum Map {
    }
  public enum Onboarding {
    }
  public enum RemoteNodes {
    }
  public enum Settings {
    }
  public enum Tools {
    }
}
// swiftlint:enable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:enable nesting type_body_length type_name vertical_whitespace_opening_braces

// MARK: - Implementation Details

extension L10n {
  private static func tr(_ table: String, _ key: String, _ args: CVarArg..., fallback value: String) -> String {
    let format = BundleToken.bundle.localizedString(forKey: key, value: value, table: table)
    return String(format: format, locale: Locale.current, arguments: args)
  }
}

// swiftlint:disable convenience_type
private final class BundleToken {
  static let bundle: Bundle = {
    #if SWIFT_PACKAGE
    return Bundle.module
    #else
    return Bundle(for: BundleToken.self)
    #endif
  }()
}
// swiftlint:enable convenience_type
