import Foundation

/// All event types that can flow through the EventDispatcher
/// Derived from PushCode (0x80+) and ResponseCode (0x00-0x19)
public enum MeshEventType: String, Sendable, CaseIterable {
    // MARK: - Push Notifications (from PushCode 0x80+)

    /// Advertisement received (PushCode.advert, .newAdvert)
    case advertisement = "advertisement"
    /// Path updated for contact (PushCode.pathUpdated)
    case pathUpdate = "path_update"
    /// ACK received for sent message (PushCode.sendConfirmed)
    case sendConfirmed = "send_confirmed"
    /// Messages waiting in device queue (PushCode.messageWaiting)
    case messagesWaiting = "messages_waiting"
    /// Raw data received (PushCode.rawData)
    case rawData = "raw_data"
    /// Login succeeded (PushCode.loginSuccess)
    case loginSuccess = "login_success"
    /// Login failed (PushCode.loginFail)
    case loginFailed = "login_failed"
    /// Status response from remote node (PushCode.statusResponse)
    case statusResponse = "status_response"
    /// RF log data received (PushCode.logRxData)
    case logData = "log_data"
    /// Trace data received (PushCode.traceData)
    case traceData = "trace_data"
    /// New advertisement from unknown contact (PushCode.newAdvert)
    case newContact = "new_contact"
    /// Telemetry response (PushCode.telemetryResponse)
    case telemetryResponse = "telemetry_response"
    /// Binary protocol response (PushCode.binaryResponse)
    case binaryResponse = "binary_response"
    /// Path discovery response (PushCode.pathDiscoveryResponse)
    case pathDiscoveryResponse = "path_discovery_response"
    /// Control data packet (PushCode.controlData)
    case controlData = "control_data"

    // MARK: - Command Responses (from ResponseCode 0x00-0x19)

    /// Command succeeded (ResponseCode.ok)
    case commandOk = "command_ok"
    /// Command failed (ResponseCode.error)
    case error = "command_error"
    /// Contact list start (ResponseCode.contactsStart)
    case contactsStart = "contacts_start"
    /// Single contact in list (ResponseCode.contact)
    case contact = "contact"
    /// Contact list end (ResponseCode.endOfContacts)
    case contactsEnd = "contacts_end"
    /// Self info response (ResponseCode.selfInfo)
    case selfInfo = "self_info"
    /// Message sent response (ResponseCode.sent)
    case messageSent = "message_sent"
    /// Direct message received (ResponseCode.contactMessageReceivedV3)
    case contactMessage = "contact_message"
    /// Channel message received (ResponseCode.channelMessageReceivedV3)
    case channelMessage = "channel_message"
    /// Current device time (ResponseCode.currentTime)
    case currentTime = "current_time"
    /// No more messages in queue (ResponseCode.noMoreMessages)
    case noMoreMessages = "no_more_messages"
    /// Contact export data (ResponseCode.exportContact)
    case contactExport = "contact_export"
    /// Battery and storage info (ResponseCode.batteryAndStorage)
    case batteryAndStorage = "battery_and_storage"
    /// Device info response (ResponseCode.deviceInfo)
    case deviceInfo = "device_info"
    /// Private key export (ResponseCode.privateKey)
    case privateKey = "private_key"
    /// Feature disabled response (ResponseCode.disabled)
    case disabled = "disabled"
    /// Channel info response (ResponseCode.channelInfo)
    case channelInfo = "channel_info"
    /// Sign operation started (ResponseCode.signStart)
    case signStart = "sign_start"
    /// Signature result (ResponseCode.signature)
    case signature = "signature"
    /// Custom vars response (ResponseCode.customVars)
    case customVars = "custom_vars"
    /// Advert path response (ResponseCode.advertPath)
    case advertPath = "advert_path"
    /// Tuning params response (ResponseCode.tuningParams)
    case tuningParams = "tuning_params"
    /// Stats response - core (ResponseCode.stats + type 0)
    case statsCore = "stats_core"
    /// Stats response - radio (ResponseCode.stats + type 1)
    case statsRadio = "stats_radio"
    /// Stats response - packets (ResponseCode.stats + type 2)
    case statsPackets = "stats_packets"
    /// Has connection response (ResponseCode.hasConnection)
    case hasConnection = "has_connection"
    /// Neighbours response (parsed from binaryResponse)
    case neighboursResponse = "neighbours_response"
    /// MMA (Min/Max/Avg) response (parsed from binaryResponse with type 0x04)
    case mmaResponse = "mma_response"
    /// ACL (Access Control List) response (parsed from binaryResponse with type 0x05)
    case aclResponse = "acl_response"
    /// Node discover response (parsed from controlData)
    case discoverResponse = "discover_response"

    // MARK: - Connection Lifecycle (not from protocol)

    /// BLE connected to device
    case connected = "connected"
    /// BLE disconnected from device
    case disconnected = "disconnected"
}
