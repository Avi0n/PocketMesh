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
    /// Build number display with build number
    public static func build(_ p1: Any) -> String {
      return L10n.tr("Settings", "build", String(describing: p1), fallback: "Build %@")
    }
    /// Placeholder shown in split view detail when no setting is selected
    public static let selectSetting = L10n.tr("Settings", "selectSetting", fallback: "Select a setting")
    /// Navigation title for the main settings screen
    public static let title = L10n.tr("Settings", "title", fallback: "Settings")
    /// Version display prefix with version number
    public static func version(_ p1: Any) -> String {
      return L10n.tr("Settings", "version", String(describing: p1), fallback: "v%@")
    }
    public enum About {
      /// Link to GitHub repository
      public static let github = L10n.tr("Settings", "about.github", fallback: "GitHub")
      /// Section header for about links
      public static let header = L10n.tr("Settings", "about.header", fallback: "About")
      /// Link to MeshCore online map
      public static let onlineMap = L10n.tr("Settings", "about.onlineMap", fallback: "MeshCore Online Map")
      /// Link to MeshCore website
      public static let website = L10n.tr("Settings", "about.website", fallback: "MeshCore Website")
    }
    public enum AdvancedRadio {
      /// Button to apply radio settings
      public static let apply = L10n.tr("Settings", "advancedRadio.apply", fallback: "Apply Radio Settings")
      /// Label for bandwidth picker
      public static let bandwidth = L10n.tr("Settings", "advancedRadio.bandwidth", fallback: "Bandwidth (kHz)")
      /// Label for coding rate picker
      public static let codingRate = L10n.tr("Settings", "advancedRadio.codingRate", fallback: "Coding Rate")
      /// Footer warning about incorrect radio settings
      public static let footer = L10n.tr("Settings", "advancedRadio.footer", fallback: "Warning: Incorrect settings may prevent communication with other mesh devices.")
      /// Label for frequency input
      public static let frequency = L10n.tr("Settings", "advancedRadio.frequency", fallback: "Frequency (MHz)")
      /// Placeholder for frequency text field
      public static let frequencyPlaceholder = L10n.tr("Settings", "advancedRadio.frequencyPlaceholder", fallback: "MHz")
      /// Section header for radio configuration
      public static let header = L10n.tr("Settings", "advancedRadio.header", fallback: "Radio Configuration")
      /// Error message for invalid input
      public static let invalidInput = L10n.tr("Settings", "advancedRadio.invalidInput", fallback: "Invalid input values or device not connected")
      /// Label for spreading factor picker
      public static let spreadingFactor = L10n.tr("Settings", "advancedRadio.spreadingFactor", fallback: "Spreading Factor")
      /// Label for TX power input
      public static let txPower = L10n.tr("Settings", "advancedRadio.txPower", fallback: "TX Power (dBm)")
      /// Placeholder for TX power text field
      public static let txPowerPlaceholder = L10n.tr("Settings", "advancedRadio.txPowerPlaceholder", fallback: "dBm")
    }
    public enum AdvancedSettings {
      /// Footer text for the advanced settings row
      public static let footer = L10n.tr("Settings", "advancedSettings.footer", fallback: "Radio tuning, telemetry, contact settings, and device management")
      /// Label for the advanced settings navigation row
      public static let title = L10n.tr("Settings", "advancedSettings.title", fallback: "Advanced Settings")
    }
    public enum Alert {
      public enum Error {
        /// Alert title for generic errors
        public static let title = L10n.tr("Settings", "alert.error.title", fallback: "Error")
      }
      public enum Retry {
        /// Alert title for connection errors
        public static let connectionError = L10n.tr("Settings", "alert.retry.connectionError", fallback: "Connection Error")
        /// Alert message when max retries exceeded
        public static let ensureConnected = L10n.tr("Settings", "alert.retry.ensureConnected", fallback: "Please ensure your device is connected.")
        /// Button to retry the operation
        public static let retry = L10n.tr("Settings", "alert.retry.retry", fallback: "Retry")
        /// Alert title when max retries exceeded
        public static let unableToSave = L10n.tr("Settings", "alert.retry.unableToSave", fallback: "Unable to Save Setting")
      }
    }
    public enum BatteryCurve {
      /// Option for custom battery curve
      public static let custom = L10n.tr("Settings", "batteryCurve.custom", fallback: "Custom")
      /// Disclosure group label for editing values
      public static let editValues = L10n.tr("Settings", "batteryCurve.editValues", fallback: "Edit Values")
      /// Footer explaining battery curve configuration
      public static let footer = L10n.tr("Settings", "batteryCurve.footer", fallback: "Configure the voltage-to-percentage curve for your device's battery.")
      /// Section header for battery curve
      public static let header = L10n.tr("Settings", "batteryCurve.header", fallback: "Battery Curve")
      /// Unit label for millivolts
      public static let mv = L10n.tr("Settings", "batteryCurve.mV", fallback: "mV")
      /// Label for preset picker
      public static let preset = L10n.tr("Settings", "batteryCurve.preset", fallback: "Preset")
      public enum Validation {
        /// Validation error for non-descending values
        public static let notDescending = L10n.tr("Settings", "batteryCurve.validation.notDescending", fallback: "Values must be in descending order")
        /// Validation error for value out of range - %d is the percentage level
        public static func outOfRange(_ p1: Int) -> String {
          return L10n.tr("Settings", "batteryCurve.validation.outOfRange", p1, fallback: "Value at %d%% must be 1000-5000 mV")
        }
      }
    }
    public enum Bluetooth {
      /// Button to change the device display name
      public static let changeDisplayName = L10n.tr("Settings", "bluetooth.changeDisplayName", fallback: "Change Display Name")
      /// Button to change the PIN
      public static let changePin = L10n.tr("Settings", "bluetooth.changePin", fallback: "Change PIN")
      /// Label showing current PIN
      public static let currentPin = L10n.tr("Settings", "bluetooth.currentPin", fallback: "Current PIN")
      /// Footer explaining default PIN
      public static let defaultPinFooter = L10n.tr("Settings", "bluetooth.defaultPinFooter", fallback: "Default PIN is 123456. Devices with screens show their own PIN.")
      /// Section header for Bluetooth settings
      public static let header = L10n.tr("Settings", "bluetooth.header", fallback: "Bluetooth")
      /// Placeholder for PIN text field
      public static let pinPlaceholder = L10n.tr("Settings", "bluetooth.pinPlaceholder", fallback: "6-digit PIN")
      /// Label for PIN type picker
      public static let pinType = L10n.tr("Settings", "bluetooth.pinType", fallback: "PIN Type")
      /// Button to set the PIN
      public static let setPin = L10n.tr("Settings", "bluetooth.setPin", fallback: "Set PIN")
      public enum Alert {
        /// Button to confirm change
        public static let change = L10n.tr("Settings", "bluetooth.alert.change", fallback: "Change")
        public enum ChangePin {
          /// Alert message for changing PIN
          public static let message = L10n.tr("Settings", "bluetooth.alert.changePin.message", fallback: "Enter a new 6-digit PIN. The device will reboot to apply the change.")
          /// Alert title for changing custom PIN
          public static let title = L10n.tr("Settings", "bluetooth.alert.changePin.title", fallback: "Change Custom PIN")
        }
        public enum ChangePinType {
          /// Alert message for PIN type change
          public static let message = L10n.tr("Settings", "bluetooth.alert.changePinType.message", fallback: "The device will reboot to apply the change.")
          /// Alert title for confirming PIN type change
          public static let title = L10n.tr("Settings", "bluetooth.alert.changePinType.title", fallback: "Change PIN Type?")
        }
        public enum SetPin {
          /// Alert message for setting PIN
          public static let message = L10n.tr("Settings", "bluetooth.alert.setPin.message", fallback: "Enter a 6-digit PIN. The device will reboot to apply the change.")
          /// Alert title for setting custom PIN
          public static let title = L10n.tr("Settings", "bluetooth.alert.setPin.title", fallback: "Set Custom PIN")
        }
      }
      public enum Error {
        /// Error for invalid PIN format
        public static let invalidPin = L10n.tr("Settings", "bluetooth.error.invalidPin", fallback: "PIN must be a 6-digit number between 100000 and 999999")
      }
      public enum PinType {
        /// PIN type option for custom PIN
        public static let custom = L10n.tr("Settings", "bluetooth.pinType.custom", fallback: "Custom PIN")
        /// PIN type option for default PIN
        public static let `default` = L10n.tr("Settings", "bluetooth.pinType.default", fallback: "Default")
      }
    }
    public enum Chart {
      /// Accessibility label for battery curve chart
      public static let accessibility = L10n.tr("Settings", "chart.accessibility", fallback: "Battery discharge curve showing voltage at each percentage level")
      /// Chart X axis label
      public static let percent = L10n.tr("Settings", "chart.percent", fallback: "Percent")
      /// Chart Y axis label
      public static let voltage = L10n.tr("Settings", "chart.voltage", fallback: "Voltage (V)")
    }
    public enum Contacts {
      /// Toggle label for auto-add nodes
      public static let autoAdd = L10n.tr("Settings", "contacts.autoAdd", fallback: "Auto-Add Nodes")
      /// Description for auto-add nodes toggle
      public static let autoAddDescription = L10n.tr("Settings", "contacts.autoAddDescription", fallback: "Automatically add nodes from received advertisements")
      /// Section header for nodes/contacts settings
      public static let header = L10n.tr("Settings", "contacts.header", fallback: "Nodes")
    }
    public enum DangerZone {
      /// Button to factory reset the device
      public static let factoryReset = L10n.tr("Settings", "dangerZone.factoryReset", fallback: "Factory Reset Device")
      /// Footer explaining factory reset
      public static let footer = L10n.tr("Settings", "dangerZone.footer", fallback: "Factory reset erases all contacts, messages, and settings on the device.")
      /// Button to forget/unpair the device
      public static let forgetDevice = L10n.tr("Settings", "dangerZone.forgetDevice", fallback: "Forget Device")
      /// Section header for danger zone
      public static let header = L10n.tr("Settings", "dangerZone.header", fallback: "Danger Zone")
      /// Text shown while resetting
      public static let resetting = L10n.tr("Settings", "dangerZone.resetting", fallback: "Resetting...")
      public enum Alert {
        public enum Forget {
          /// Button to confirm forget
          public static let confirm = L10n.tr("Settings", "dangerZone.alert.forget.confirm", fallback: "Forget")
          /// Alert message for forget device
          public static let message = L10n.tr("Settings", "dangerZone.alert.forget.message", fallback: "This will remove the device from your paired devices. You can pair it again later.")
          /// Alert title for forget device confirmation
          public static let title = L10n.tr("Settings", "dangerZone.alert.forget.title", fallback: "Forget Device")
        }
        public enum Reset {
          /// Button to confirm reset
          public static let confirm = L10n.tr("Settings", "dangerZone.alert.reset.confirm", fallback: "Reset")
          /// Alert message for factory reset
          public static let message = L10n.tr("Settings", "dangerZone.alert.reset.message", fallback: "This will erase ALL data on the device including contacts, messages, and settings. This cannot be undone.")
          /// Alert title for factory reset confirmation
          public static let title = L10n.tr("Settings", "dangerZone.alert.reset.title", fallback: "Factory Reset")
        }
      }
      public enum Error {
        /// Error when services are not available
        public static let servicesUnavailable = L10n.tr("Settings", "dangerZone.error.servicesUnavailable", fallback: "Services not available")
      }
    }
    public enum DemoMode {
      /// Toggle label to enable demo mode
      public static let enabled = L10n.tr("Settings", "demoMode.enabled", fallback: "Enabled")
      /// Footer explaining what demo mode does
      public static let footer = L10n.tr("Settings", "demoMode.footer", fallback: "Demo mode allows testing without hardware using mock data.")
      /// Section header for demo mode
      public static let header = L10n.tr("Settings", "demoMode.header", fallback: "Demo Mode")
    }
    public enum Device {
      /// Button to connect a device
      public static let connect = L10n.tr("Settings", "device.connect", fallback: "Connect Device")
      /// Status shown when device is connected
      public static let connected = L10n.tr("Settings", "device.connected", fallback: "Connected")
      /// Section header for device information
      public static let header = L10n.tr("Settings", "device.header", fallback: "Device")
      /// Footer shown when no device is connected
      public static let noDeviceConnected = L10n.tr("Settings", "device.noDeviceConnected", fallback: "No MeshCore device connected")
    }
    public enum DeviceInfo {
      /// Label for battery level
      public static let battery = L10n.tr("Settings", "deviceInfo.battery", fallback: "Battery")
      /// Combined label for battery and storage when loading
      public static let batteryAndStorage = L10n.tr("Settings", "deviceInfo.batteryAndStorage", fallback: "Battery & Storage")
      /// Label for build date
      public static let buildDate = L10n.tr("Settings", "deviceInfo.buildDate", fallback: "Build Date")
      /// Fallback manufacturer name
      public static let defaultManufacturer = L10n.tr("Settings", "deviceInfo.defaultManufacturer", fallback: "MeshCore Device")
      /// Label for firmware version
      public static let firmwareVersion = L10n.tr("Settings", "deviceInfo.firmwareVersion", fallback: "Firmware Version")
      /// Label for manufacturer
      public static let manufacturer = L10n.tr("Settings", "deviceInfo.manufacturer", fallback: "Manufacturer")
      /// Label for max channels capability
      public static let maxChannels = L10n.tr("Settings", "deviceInfo.maxChannels", fallback: "Max Channels")
      /// Label for max contacts capability
      public static let maxContacts = L10n.tr("Settings", "deviceInfo.maxContacts", fallback: "Max Contacts")
      /// Label for max TX power capability
      public static let maxTxPower = L10n.tr("Settings", "deviceInfo.maxTxPower", fallback: "Max TX Power")
      /// Label for public key
      public static let publicKey = L10n.tr("Settings", "deviceInfo.publicKey", fallback: "Public Key")
      /// Button to share contact information
      public static let shareContact = L10n.tr("Settings", "deviceInfo.shareContact", fallback: "Share My Contact")
      /// Label for storage used
      public static let storageUsed = L10n.tr("Settings", "deviceInfo.storageUsed", fallback: "Storage Used")
      /// Navigation title for device info screen
      public static let title = L10n.tr("Settings", "deviceInfo.title", fallback: "Device Info")
      /// TX power display format with dBm unit
      public static func txPowerFormat(_ p1: Any) -> String {
        return L10n.tr("Settings", "deviceInfo.txPowerFormat", String(describing: p1), fallback: "%@ dBm")
      }
      /// Placeholder when a value is unknown
      public static let unknown = L10n.tr("Settings", "deviceInfo.unknown", fallback: "Unknown")
      public enum Capabilities {
        /// Section header for device capabilities
        public static let header = L10n.tr("Settings", "deviceInfo.capabilities.header", fallback: "Capabilities")
      }
      public enum Connection {
        /// Section header for connection status
        public static let header = L10n.tr("Settings", "deviceInfo.connection.header", fallback: "Connection")
        /// Label for connection status
        public static let status = L10n.tr("Settings", "deviceInfo.connection.status", fallback: "Status")
      }
      public enum Firmware {
        /// Section header for firmware information
        public static let header = L10n.tr("Settings", "deviceInfo.firmware.header", fallback: "Firmware")
      }
      public enum Identity {
        /// Section header for identity information
        public static let header = L10n.tr("Settings", "deviceInfo.identity.header", fallback: "Identity")
      }
      public enum NoDevice {
        /// Description for ContentUnavailableView when no device is connected
        public static let description = L10n.tr("Settings", "deviceInfo.noDevice.description", fallback: "Connect to a MeshCore device to view its information")
        /// Title for ContentUnavailableView when no device is connected
        public static let title = L10n.tr("Settings", "deviceInfo.noDevice.title", fallback: "No Device Connected")
      }
      public enum PowerStorage {
        /// Section header for power and storage
        public static let header = L10n.tr("Settings", "deviceInfo.powerStorage.header", fallback: "Power & Storage")
      }
    }
    public enum DeviceSelection {
      /// Fallback connection type description
      public static let bluetooth = L10n.tr("Settings", "deviceSelection.bluetooth", fallback: "Bluetooth")
      /// Button to connect to selected device
      public static let connect = L10n.tr("Settings", "deviceSelection.connect", fallback: "Connect")
      /// Label shown when device is connected to another app
      public static let connectedElsewhere = L10n.tr("Settings", "deviceSelection.connectedElsewhere", fallback: "Connected elsewhere")
      /// Button to connect via WiFi
      public static let connectViaWifi = L10n.tr("Settings", "deviceSelection.connectViaWifi", fallback: "Connect via WiFi")
      /// Description for empty state
      public static let noPairedDescription = L10n.tr("Settings", "deviceSelection.noPairedDescription", fallback: "You haven't paired any devices yet.")
      /// Title for empty state when no devices are paired
      public static let noPairedDevices = L10n.tr("Settings", "deviceSelection.noPairedDevices", fallback: "No Paired Devices")
      /// Section header for previously paired devices
      public static let previouslyPaired = L10n.tr("Settings", "deviceSelection.previouslyPaired", fallback: "Previously Paired")
      /// Button to scan for Bluetooth devices
      public static let scanBluetooth = L10n.tr("Settings", "deviceSelection.scanBluetooth", fallback: "Scan for Bluetooth Device")
      /// Button to scan for new devices
      public static let scanForDevices = L10n.tr("Settings", "deviceSelection.scanForDevices", fallback: "Scan for Devices")
      /// Footer text prompting user to select a device
      public static let selectToReconnect = L10n.tr("Settings", "deviceSelection.selectToReconnect", fallback: "Select a device to reconnect")
      /// Navigation title for device selection
      public static let title = L10n.tr("Settings", "deviceSelection.title", fallback: "Connect Device")
    }
    public enum Diagnostics {
      /// Button to clear debug logs
      public static let clearLogs = L10n.tr("Settings", "diagnostics.clearLogs", fallback: "Clear Debug Logs")
      /// Button to export debug logs
      public static let exportLogs = L10n.tr("Settings", "diagnostics.exportLogs", fallback: "Export Debug Logs")
      /// Footer explaining log export
      public static let footer = L10n.tr("Settings", "diagnostics.footer", fallback: "Export includes debug logs from the last 24 hours across app sessions. Logs are stored locally and automatically pruned.")
      /// Section header for diagnostics
      public static let header = L10n.tr("Settings", "diagnostics.header", fallback: "Diagnostics")
      public enum Alert {
        public enum Clear {
          /// Button to confirm clear
          public static let confirm = L10n.tr("Settings", "diagnostics.alert.clear.confirm", fallback: "Clear")
          /// Alert message for clear logs
          public static let message = L10n.tr("Settings", "diagnostics.alert.clear.message", fallback: "This will delete all stored debug logs. Exported log files will not be affected.")
          /// Alert title for clear logs confirmation
          public static let title = L10n.tr("Settings", "diagnostics.alert.clear.title", fallback: "Clear Debug Logs")
        }
      }
      public enum Error {
        /// Error when export fails
        public static let exportFailed = L10n.tr("Settings", "diagnostics.error.exportFailed", fallback: "Failed to create export file")
      }
    }
    public enum LinkPreviews {
      /// Footer explaining link preview privacy implications
      public static let footer = L10n.tr("Settings", "linkPreviews.footer", fallback: "Link previews fetch data from the web, which may reveal your IP address to the server hosting the link.")
      /// Section header for privacy settings
      public static let header = L10n.tr("Settings", "linkPreviews.header", fallback: "Privacy")
      /// Toggle label for showing previews in channels
      public static let showInChannels = L10n.tr("Settings", "linkPreviews.showInChannels", fallback: "Show in Channels")
      /// Toggle label for showing previews in DMs
      public static let showInDMs = L10n.tr("Settings", "linkPreviews.showInDMs", fallback: "Show in Direct Messages")
      /// Toggle label for link previews
      public static let toggle = L10n.tr("Settings", "linkPreviews.toggle", fallback: "Link Previews")
    }
    public enum LocationPicker {
      /// Button to clear the selected location
      public static let clearLocation = L10n.tr("Settings", "locationPicker.clearLocation", fallback: "Clear Location")
      /// Button to drop a pin at the map center
      public static let dropPin = L10n.tr("Settings", "locationPicker.dropPin", fallback: "Drop Pin at Center")
      /// Label for latitude display
      public static let latitude = L10n.tr("Settings", "locationPicker.latitude", fallback: "Latitude:")
      /// Label for longitude display
      public static let longitude = L10n.tr("Settings", "locationPicker.longitude", fallback: "Longitude:")
      /// Marker title for node location on map
      public static let markerTitle = L10n.tr("Settings", "locationPicker.markerTitle", fallback: "Node Location")
      /// Navigation title for location picker
      public static let title = L10n.tr("Settings", "locationPicker.title", fallback: "Set Location")
    }
    public enum Node {
      /// Button text to copy
      public static let copy = L10n.tr("Settings", "node.copy", fallback: "Copy")
      /// Footer explaining node visibility
      public static let footer = L10n.tr("Settings", "node.footer", fallback: "Your node name and location are visible to other mesh users when shared.")
      /// Section header for node settings
      public static let header = L10n.tr("Settings", "node.header", fallback: "Node")
      /// Text shown when location is not set
      public static let locationNotSet = L10n.tr("Settings", "node.locationNotSet", fallback: "Not Set")
      /// Text shown when location is set
      public static let locationSet = L10n.tr("Settings", "node.locationSet", fallback: "Set")
      /// Label for node name
      public static let name = L10n.tr("Settings", "node.name", fallback: "Node Name")
      /// Label for set location button
      public static let setLocation = L10n.tr("Settings", "node.setLocation", fallback: "Set Location")
      /// Toggle label for share location publicly
      public static let shareLocationPublicly = L10n.tr("Settings", "node.shareLocationPublicly", fallback: "Share Location Publicly")
      /// Default node name when unknown
      public static let unknown = L10n.tr("Settings", "node.unknown", fallback: "Unknown")
      public enum Alert {
        public enum EditName {
          /// Alert title for editing node name
          public static let title = L10n.tr("Settings", "node.alert.editName.title", fallback: "Edit Node Name")
        }
      }
    }
    public enum Notifications {
      /// Toggle label for channel messages notifications
      public static let channelMessages = L10n.tr("Settings", "notifications.channelMessages", fallback: "Channel Messages")
      /// Message shown when device not connected
      public static let connectDevice = L10n.tr("Settings", "notifications.connectDevice", fallback: "Connect a device to configure notifications")
      /// Toggle label for contact messages notifications
      public static let contactMessages = L10n.tr("Settings", "notifications.contactMessages", fallback: "Contact Messages")
      /// Label shown when notifications are disabled
      public static let disabled = L10n.tr("Settings", "notifications.disabled", fallback: "Notifications Disabled")
      /// Button to enable notifications
      public static let enable = L10n.tr("Settings", "notifications.enable", fallback: "Enable Notifications")
      /// Section header for notifications
      public static let header = L10n.tr("Settings", "notifications.header", fallback: "Notifications")
      /// Toggle label for low battery warnings
      public static let lowBattery = L10n.tr("Settings", "notifications.lowBattery", fallback: "Low Battery Warnings")
      /// Toggle label for new contact discovered notifications
      public static let newContactDiscovered = L10n.tr("Settings", "notifications.newContactDiscovered", fallback: "New Contact Discovered")
      /// Button to open system settings
      public static let openSettings = L10n.tr("Settings", "notifications.openSettings", fallback: "Open Settings")
      /// Toggle label for room messages notifications
      public static let roomMessages = L10n.tr("Settings", "notifications.roomMessages", fallback: "Room Messages")
    }
    public enum PublicKey {
      /// Button to copy key to clipboard
      public static let copy = L10n.tr("Settings", "publicKey.copy", fallback: "Copy to Clipboard")
      /// Footer explaining the public key's purpose
      public static let footer = L10n.tr("Settings", "publicKey.footer", fallback: "This key uniquely identifies your device on the mesh network")
      /// Section header describing the key type
      public static let header = L10n.tr("Settings", "publicKey.header", fallback: "32-byte Ed25519 Public Key")
      /// Navigation title for public key screen
      public static let title = L10n.tr("Settings", "publicKey.title", fallback: "Public Key")
      public enum Base64 {
        /// Section header for base64 representation
        public static let header = L10n.tr("Settings", "publicKey.base64.header", fallback: "Base64")
      }
    }
    public enum Radio {
      /// Footer explaining radio presets
      public static let footer = L10n.tr("Settings", "radio.footer", fallback: "Choose a preset matching your region. MeshCore devices must use the same radio settings in order to communicate.")
      /// Section header for radio settings
      public static let header = L10n.tr("Settings", "radio.header", fallback: "Radio")
      /// Label for radio preset picker
      public static let preset = L10n.tr("Settings", "radio.preset", fallback: "Radio Preset")
    }
    public enum Telemetry {
      /// Toggle label for allowing telemetry requests
      public static let allowRequests = L10n.tr("Settings", "telemetry.allowRequests", fallback: "Allow Telemetry Requests")
      /// Description for telemetry requests toggle
      public static let allowRequestsDescription = L10n.tr("Settings", "telemetry.allowRequestsDescription", fallback: "Required for other users to manually trace a path to you. Shares battery level.")
      /// Footer explaining telemetry
      public static let footer = L10n.tr("Settings", "telemetry.footer", fallback: "When enabled, other nodes can request your device's telemetry data.")
      /// Section header for telemetry settings
      public static let header = L10n.tr("Settings", "telemetry.header", fallback: "Telemetry")
      /// Toggle label for including environment sensors
      public static let includeEnvironment = L10n.tr("Settings", "telemetry.includeEnvironment", fallback: "Include Environment Sensors")
      /// Description for include environment toggle
      public static let includeEnvironmentDescription = L10n.tr("Settings", "telemetry.includeEnvironmentDescription", fallback: "Share temperature, humidity, etc.")
      /// Toggle label for including location in telemetry
      public static let includeLocation = L10n.tr("Settings", "telemetry.includeLocation", fallback: "Include Location")
      /// Description for include location toggle
      public static let includeLocationDescription = L10n.tr("Settings", "telemetry.includeLocationDescription", fallback: "Share GPS coordinates in telemetry")
      /// Link to manage trusted contacts
      public static let manageTrusted = L10n.tr("Settings", "telemetry.manageTrusted", fallback: "Manage Trusted Contacts")
      /// Toggle label for trusted contacts only
      public static let trustedOnly = L10n.tr("Settings", "telemetry.trustedOnly", fallback: "Only Share with Trusted Contacts")
      /// Description for trusted contacts toggle
      public static let trustedOnlyDescription = L10n.tr("Settings", "telemetry.trustedOnlyDescription", fallback: "Limit telemetry to selected contacts")
    }
    public enum TrustedContacts {
      /// Title for empty state when no contacts exist
      public static let noContacts = L10n.tr("Settings", "trustedContacts.noContacts", fallback: "No Contacts")
      /// Description for empty state
      public static let noContactsDescription = L10n.tr("Settings", "trustedContacts.noContactsDescription", fallback: "Add contacts to select trusted ones")
      /// Navigation title for trusted contacts picker
      public static let title = L10n.tr("Settings", "trustedContacts.title", fallback: "Trusted Contacts")
    }
    public enum Wifi {
      /// Label for IP address
      public static let address = L10n.tr("Settings", "wifi.address", fallback: "Address")
      /// Button to edit WiFi connection
      public static let editConnection = L10n.tr("Settings", "wifi.editConnection", fallback: "Edit Connection")
      /// Footer explaining WiFi address
      public static let footer = L10n.tr("Settings", "wifi.footer", fallback: "Your device's local network address")
      /// Section header for WiFi settings
      public static let header = L10n.tr("Settings", "wifi.header", fallback: "WiFi")
      /// Label for port number
      public static let port = L10n.tr("Settings", "wifi.port", fallback: "Port")
    }
    public enum WifiEdit {
      /// Accessibility label for clear IP button
      public static let clearIp = L10n.tr("Settings", "wifiEdit.clearIp", fallback: "Clear IP address")
      /// Accessibility label for clear port button
      public static let clearPort = L10n.tr("Settings", "wifiEdit.clearPort", fallback: "Clear port")
      /// Section header for connection details
      public static let connectionDetails = L10n.tr("Settings", "wifiEdit.connectionDetails", fallback: "Connection Details")
      /// Footer explaining reconnection
      public static let footer = L10n.tr("Settings", "wifiEdit.footer", fallback: "Changing these values will disconnect and reconnect to the new address.")
      /// Placeholder for IP address field
      public static let ipPlaceholder = L10n.tr("Settings", "wifiEdit.ipPlaceholder", fallback: "IP Address")
      /// Placeholder for port field
      public static let portPlaceholder = L10n.tr("Settings", "wifiEdit.portPlaceholder", fallback: "Port")
      /// Text shown while reconnecting
      public static let reconnecting = L10n.tr("Settings", "wifiEdit.reconnecting", fallback: "Reconnecting...")
      /// Button to save changes
      public static let saveChanges = L10n.tr("Settings", "wifiEdit.saveChanges", fallback: "Save Changes")
      /// Navigation title for WiFi edit sheet
      public static let title = L10n.tr("Settings", "wifiEdit.title", fallback: "Edit WiFi Connection")
      public enum Error {
        /// Error for invalid port
        public static let invalidPort = L10n.tr("Settings", "wifiEdit.error.invalidPort", fallback: "Invalid port number")
      }
    }
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
