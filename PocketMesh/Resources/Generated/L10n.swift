// swiftlint:disable all
// Generated using SwiftGen — https://github.com/SwiftGen/SwiftGen

import Foundation

// swiftlint:disable superfluous_disable_command file_length implicit_return prefer_self_in_static_references

// MARK: - Strings

// swiftlint:disable explicit_type_interface function_parameter_count identifier_name line_length
// swiftlint:disable nesting type_body_length type_name vertical_whitespace_opening_braces
public enum L10n {
  public enum Chats {
    public enum Chats {
      /// Location: ChatsView.swift - Navigation title for main chat list
      public static let title = L10n.tr("Chats", "chats.title", fallback: "Chats")
      public enum Accessibility {
        /// Location: ChatsView.swift - VoiceOver announcement when viewing cached data offline
        public static let offlineAnnouncement = L10n.tr("Chats", "chats.accessibility.offlineAnnouncement", fallback: "Viewing cached data. Connect to device for updates.")
      }
      public enum Alert {
        public enum CannotRefresh {
          /// Location: ChatsView.swift - Alert message for offline refresh
          public static let message = L10n.tr("Chats", "chats.alert.cannotRefresh.message", fallback: "Connect to your device to get the latest messages.")
          /// Location: ChatsView.swift - Alert title when offline refresh attempted
          public static let title = L10n.tr("Chats", "chats.alert.cannotRefresh.title", fallback: "Cannot Refresh")
        }
        public enum LeaveRoom {
          /// Location: ChatsView.swift - Button to confirm leaving a room
          public static let confirm = L10n.tr("Chats", "chats.alert.leaveRoom.confirm", fallback: "Leave")
          /// Location: ChatsView.swift - Alert message explaining what leaving a room does
          public static let message = L10n.tr("Chats", "chats.alert.leaveRoom.message", fallback: "This will remove the room from your chat list, delete all room messages, and remove the associated contact.")
          /// Location: ChatsView.swift - Alert title for leaving a room
          public static let title = L10n.tr("Chats", "chats.alert.leaveRoom.title", fallback: "Leave Room")
        }
        public enum UnableToSend {
          /// Location: ChatView.swift - Alert message when message send fails
          public static let message = L10n.tr("Chats", "chats.alert.unableToSend.message", fallback: "Please ensure your device is connected and try again.")
          /// Location: ChatView.swift - Alert title when message send fails
          public static let title = L10n.tr("Chats", "chats.alert.unableToSend.title", fallback: "Unable to Send")
        }
      }
      public enum Channel {
        /// Location: ChannelChatView.swift - Fallback channel name format - %d is channel index
        public static func defaultName(_ p1: Int) -> String {
          return L10n.tr("Chats", "chats.channel.defaultName", p1, fallback: "Channel %d")
        }
        /// Location: ChannelChatView.swift - Header subtitle for private channels
        public static let typePrivate = L10n.tr("Chats", "chats.channel.typePrivate", fallback: "Private Channel")
        /// Location: ChannelChatView.swift - Header subtitle for public channels
        public static let typePublic = L10n.tr("Chats", "chats.channel.typePublic", fallback: "Public Channel")
        public enum EmptyState {
          /// Location: ChannelChatView.swift - Empty state message
          public static let noMessages = L10n.tr("Chats", "chats.channel.emptyState.noMessages", fallback: "No messages yet")
          /// Location: ChannelChatView.swift - Empty state description for private channel
          public static let privateDescription = L10n.tr("Chats", "chats.channel.emptyState.privateDescription", fallback: "This is a private channel")
          /// Location: ChannelChatView.swift - Empty state description for public channel
          public static let publicDescription = L10n.tr("Chats", "chats.channel.emptyState.publicDescription", fallback: "This is a public broadcast channel")
        }
      }
      public enum ChannelInfo {
        /// Location: ChannelInfoSheet.swift - Button to copy secret key
        public static let copy = L10n.tr("Chats", "chats.channelInfo.copy", fallback: "Copy")
        /// Location: ChannelInfoSheet.swift - Delete channel button
        public static let deleteButton = L10n.tr("Chats", "chats.channelInfo.deleteButton", fallback: "Delete Channel")
        /// Location: ChannelInfoSheet.swift - Footer explaining delete action
        public static let deleteFooter = L10n.tr("Chats", "chats.channelInfo.deleteFooter", fallback: "Deleting removes this channel from your device. You can rejoin later if you have the secret key.")
        /// Location: ChannelInfoSheet.swift - Label for last message date
        public static let lastMessage = L10n.tr("Chats", "chats.channelInfo.lastMessage", fallback: "Last Message")
        /// Location: ChannelInfoSheet.swift - Section header for manual sharing
        public static let manualSharing = L10n.tr("Chats", "chats.channelInfo.manualSharing", fallback: "Manual Sharing")
        /// Location: ChannelInfoSheet.swift - Footer explaining manual sharing
        public static let manualSharingFooter = L10n.tr("Chats", "chats.channelInfo.manualSharingFooter", fallback: "Share the channel name and this secret key for others to join manually.")
        /// Location: ChannelInfoSheet.swift - QR code instruction text
        public static let scanToJoin = L10n.tr("Chats", "chats.channelInfo.scanToJoin", fallback: "Scan to join this channel")
        /// Location: ChannelInfoSheet.swift - Label for secret key
        public static let secretKey = L10n.tr("Chats", "chats.channelInfo.secretKey", fallback: "Secret Key")
        /// Location: ChannelInfoSheet.swift - Section header for QR sharing
        public static let shareChannel = L10n.tr("Chats", "chats.channelInfo.shareChannel", fallback: "Share Channel")
        /// Location: ChannelInfoSheet.swift - Label for channel slot
        public static let slot = L10n.tr("Chats", "chats.channelInfo.slot", fallback: "Slot")
        /// Location: ChannelInfoSheet.swift - Navigation title
        public static let title = L10n.tr("Chats", "chats.channelInfo.title", fallback: "Channel Info")
        public enum ChannelType {
          /// Location: ChannelInfoSheet.swift - Channel type label for hashtag channel - %d is slot number
          public static func hashtag(_ p1: Int) -> String {
            return L10n.tr("Chats", "chats.channelInfo.channelType.hashtag", p1, fallback: "Hashtag Channel • Slot %d")
          }
          /// Location: ChannelInfoSheet.swift - Channel type label for private channel - %d is slot number
          public static func `private`(_ p1: Int) -> String {
            return L10n.tr("Chats", "chats.channelInfo.channelType.private", p1, fallback: "Private Channel • Slot %d")
          }
          /// Location: ChannelInfoSheet.swift - Channel type label for public channel
          public static let `public` = L10n.tr("Chats", "chats.channelInfo.channelType.public", fallback: "Public Channel • Slot 0")
        }
        public enum DeleteConfirm {
          /// Location: ChannelInfoSheet.swift - Confirmation dialog message
          public static let message = L10n.tr("Chats", "chats.channelInfo.deleteConfirm.message", fallback: "This will remove the channel from your device and delete all local messages. This action cannot be undone.")
          /// Location: ChannelInfoSheet.swift - Confirmation dialog title
          public static let title = L10n.tr("Chats", "chats.channelInfo.deleteConfirm.title", fallback: "Delete Channel")
        }
      }
      public enum ChannelOptions {
        /// Location: ChannelOptionsSheet.swift - Loading indicator text
        public static let loading = L10n.tr("Chats", "chats.channelOptions.loading", fallback: "Loading channels...")
        /// Location: ChannelOptionsSheet.swift - Navigation title
        public static let title = L10n.tr("Chats", "chats.channelOptions.title", fallback: "New Channel")
        public enum CreatePrivate {
          /// Location: ChannelOptionsSheet.swift - Create private channel option description
          public static let description = L10n.tr("Chats", "chats.channelOptions.createPrivate.description", fallback: "Generate a secret key and QR code to share")
          /// Location: ChannelOptionsSheet.swift - Create private channel option title
          public static let title = L10n.tr("Chats", "chats.channelOptions.createPrivate.title", fallback: "Create a Private Channel")
        }
        public enum Footer {
          /// Location: ChannelOptionsSheet.swift - Footer when public channel already exists
          public static let hasPublic = L10n.tr("Chats", "chats.channelOptions.footer.hasPublic", fallback: "The public channel is already configured on slot 0.")
          /// Location: ChannelOptionsSheet.swift - Footer when all slots are in use
          public static let noSlots = L10n.tr("Chats", "chats.channelOptions.footer.noSlots", fallback: "All channel slots are in use. Delete an existing channel to add a new one.")
        }
        public enum JoinHashtag {
          /// Location: ChannelOptionsSheet.swift - Join hashtag channel option description
          public static let description = L10n.tr("Chats", "chats.channelOptions.joinHashtag.description", fallback: "Public channel anyone can join by name")
          /// Location: ChannelOptionsSheet.swift - Join hashtag channel option title
          public static let title = L10n.tr("Chats", "chats.channelOptions.joinHashtag.title", fallback: "Join a Hashtag Channel")
        }
        public enum JoinPrivate {
          /// Location: ChannelOptionsSheet.swift - Join private channel option description
          public static let description = L10n.tr("Chats", "chats.channelOptions.joinPrivate.description", fallback: "Enter channel name and secret key")
          /// Location: ChannelOptionsSheet.swift - Join private channel option title
          public static let title = L10n.tr("Chats", "chats.channelOptions.joinPrivate.title", fallback: "Join a Private Channel")
        }
        public enum JoinPublic {
          /// Location: ChannelOptionsSheet.swift - Join public channel option description
          public static let description = L10n.tr("Chats", "chats.channelOptions.joinPublic.description", fallback: "The default public channel")
          /// Location: ChannelOptionsSheet.swift - Join public channel option title
          public static let title = L10n.tr("Chats", "chats.channelOptions.joinPublic.title", fallback: "Join the Public Channel")
        }
        public enum ScanQR {
          /// Location: ChannelOptionsSheet.swift - Scan QR code option description
          public static let description = L10n.tr("Chats", "chats.channelOptions.scanQR.description", fallback: "Join a channel by scanning its QR code")
          /// Location: ChannelOptionsSheet.swift - Scan QR code option title
          public static let title = L10n.tr("Chats", "chats.channelOptions.scanQR.title", fallback: "Scan a QR Code")
        }
        public enum Section {
          /// Location: ChannelOptionsSheet.swift - Section header for private channels
          public static let `private` = L10n.tr("Chats", "chats.channelOptions.section.private", fallback: "Private Channels")
          /// Location: ChannelOptionsSheet.swift - Section header for public channels
          public static let `public` = L10n.tr("Chats", "chats.channelOptions.section.public", fallback: "Public Channels")
        }
      }
      public enum Common {
        /// Location: Various - Cancel button (use L10n.Localizable.Common.cancel)
        public static let cancel = L10n.tr("Chats", "chats.common.cancel", fallback: "Cancel")
        /// Location: Various - Done button (use L10n.Localizable.Common.done)
        public static let done = L10n.tr("Chats", "chats.common.done", fallback: "Done")
        /// Location: Various - OK button (use L10n.Localizable.Common.ok)
        public static let ok = L10n.tr("Chats", "chats.common.ok", fallback: "OK")
      }
      public enum Compose {
        /// Location: ChatsView.swift - Button to create or join a channel
        public static let newChannel = L10n.tr("Chats", "chats.compose.newChannel", fallback: "New Channel")
        /// Location: ChatsView.swift - Button to start a new direct chat
        public static let newChat = L10n.tr("Chats", "chats.compose.newChat", fallback: "New Chat")
        /// Location: ChatsView.swift - Menu label for new message options
        public static let newMessage = L10n.tr("Chats", "chats.compose.newMessage", fallback: "New Message")
      }
      public enum ConnectionStatus {
        /// Location: ChatView.swift - Connection status format for direct path - %d is hop count
        public static func direct(_ p1: Int) -> String {
          return L10n.tr("Chats", "chats.connectionStatus.direct", p1, fallback: "Direct • %d hops")
        }
        /// Location: ChatView.swift - Connection status for flood routed contacts
        public static let floodRouting = L10n.tr("Chats", "chats.connectionStatus.floodRouting", fallback: "Flood routing")
        /// Location: ChatView.swift - Connection status when route is unknown
        public static let unknown = L10n.tr("Chats", "chats.connectionStatus.unknown", fallback: "Unknown route")
      }
      public enum ContactInfo {
        /// Location: ChatView.swift - Label showing contact has location
        public static let hasLocation = L10n.tr("Chats", "chats.contactInfo.hasLocation", fallback: "Has location")
      }
      public enum CreatePrivate {
        /// Location: CreatePrivateChannelView.swift - Text field placeholder for channel name
        public static let channelName = L10n.tr("Chats", "chats.createPrivate.channelName", fallback: "Channel Name")
        /// Location: CreatePrivateChannelView.swift - Button to create channel
        public static let createButton = L10n.tr("Chats", "chats.createPrivate.createButton", fallback: "Create Channel")
        /// Location: CreatePrivateChannelView.swift - Footer explaining generated secret
        public static let secretFooter = L10n.tr("Chats", "chats.createPrivate.secretFooter", fallback: "A random secret key has been generated. You'll be able to share it via QR code after creating the channel.")
        /// Location: CreatePrivateChannelView.swift - Footer explaining manual sharing
        public static let shareManuallyFooter = L10n.tr("Chats", "chats.createPrivate.shareManuallyFooter", fallback: "Share the channel name and this secret key with others. They'll need both to join.")
        /// Location: CreatePrivateChannelView.swift - Title when creating channel
        public static let titleCreate = L10n.tr("Chats", "chats.createPrivate.titleCreate", fallback: "Create Private Channel")
        /// Location: CreatePrivateChannelView.swift - Title when sharing created channel
        public static let titleShare = L10n.tr("Chats", "chats.createPrivate.titleShare", fallback: "Share Private Channel")
        public enum Section {
          /// Location: CreatePrivateChannelView.swift - Section header for channel details
          public static let details = L10n.tr("Chats", "chats.createPrivate.section.details", fallback: "Channel Details")
          /// Location: CreatePrivateChannelView.swift - Section header for generated secret
          public static let secret = L10n.tr("Chats", "chats.createPrivate.section.secret", fallback: "Generated Secret")
          /// Location: CreatePrivateChannelView.swift - Section header for manual sharing
          public static let shareManually = L10n.tr("Chats", "chats.createPrivate.section.shareManually", fallback: "Share Manually")
        }
      }
      public enum EmptyState {
        /// Location: ChatsView.swift - Split view placeholder when no conversation selected
        public static let selectConversation = L10n.tr("Chats", "chats.emptyState.selectConversation", fallback: "Select a conversation")
        /// Location: ChatView.swift - Empty state text prompting user to start chatting
        public static let startConversation = L10n.tr("Chats", "chats.emptyState.startConversation", fallback: "Start a conversation")
        public enum NoChannels {
          /// Location: ChatsView.swift - Description when no channels
          public static let description = L10n.tr("Chats", "chats.emptyState.noChannels.description", fallback: "Join or create a channel")
          /// Location: ChatsView.swift - Title when no channels
          public static let title = L10n.tr("Chats", "chats.emptyState.noChannels.title", fallback: "No Channels")
        }
        public enum NoConversations {
          /// Location: ChatsView.swift - Description when no conversations exist
          public static let description = L10n.tr("Chats", "chats.emptyState.noConversations.description", fallback: "Start a conversation from Contacts")
          /// Location: ChatsView.swift - Title when no conversations exist
          public static let title = L10n.tr("Chats", "chats.emptyState.noConversations.title", fallback: "No Conversations")
        }
        public enum NoDirectMessages {
          /// Location: ChatsView.swift - Description when no direct messages
          public static let description = L10n.tr("Chats", "chats.emptyState.noDirectMessages.description", fallback: "Start a chat from Contacts")
          /// Location: ChatsView.swift - Title when no direct messages
          public static let title = L10n.tr("Chats", "chats.emptyState.noDirectMessages.title", fallback: "No Direct Messages")
        }
        public enum NoFavorites {
          /// Location: ChatsView.swift - Description when no favorites
          public static let description = L10n.tr("Chats", "chats.emptyState.noFavorites.description", fallback: "Mark contacts as favorites to see them here")
          /// Location: ChatsView.swift - Title when no favorites
          public static let title = L10n.tr("Chats", "chats.emptyState.noFavorites.title", fallback: "No Favorites")
        }
        public enum NoUnread {
          /// Location: ChatsView.swift - Description when no unread messages
          public static let description = L10n.tr("Chats", "chats.emptyState.noUnread.description", fallback: "You're all caught up")
          /// Location: ChatsView.swift - Title when no unread messages
          public static let title = L10n.tr("Chats", "chats.emptyState.noUnread.title", fallback: "No Unread Messages")
        }
      }
      public enum Error {
        /// Location: ChannelInfoSheet.swift - Error when device not connected
        public static let noDeviceConnected = L10n.tr("Chats", "chats.error.noDeviceConnected", fallback: "No device connected")
        /// Location: ChannelInfoSheet.swift - Error when services unavailable
        public static let servicesUnavailable = L10n.tr("Chats", "chats.error.servicesUnavailable", fallback: "Services not available")
      }
      public enum Fab {
        public enum Badge {
          /// Location: ScrollToMentionFAB.swift, ScrollToBottomFAB.swift - Badge text for 99+ unread
          public static let overflow = L10n.tr("Chats", "chats.fab.badge.overflow", fallback: "99+")
        }
        public enum ScrollToBottom {
          /// Location: ScrollToBottomFAB.swift - Accessibility label for scroll to bottom button
          public static let accessibilityLabel = L10n.tr("Chats", "chats.fab.scrollToBottom.accessibilityLabel", fallback: "Scroll to latest message")
        }
        public enum ScrollToMention {
          /// Location: ScrollToMentionFAB.swift - Accessibility hint for scroll to mention button
          public static let accessibilityHint = L10n.tr("Chats", "chats.fab.scrollToMention.accessibilityHint", fallback: "Double-tap to navigate to the message")
          /// Location: ScrollToMentionFAB.swift - Accessibility label for scroll to mention button
          public static let accessibilityLabel = L10n.tr("Chats", "chats.fab.scrollToMention.accessibilityLabel", fallback: "Scroll to your oldest unread mention")
        }
      }
      public enum Filter {
        /// Location: ChatsView.swift - Accessibility label when no filter is active
        public static let accessibilityLabel = L10n.tr("Chats", "chats.filter.accessibilityLabel", fallback: "Filter conversations")
        /// Location: ChatsView.swift - Accessibility label format when filter is active - %@ is the filter name
        public static func accessibilityLabelActive(_ p1: Any) -> String {
          return L10n.tr("Chats", "chats.filter.accessibilityLabelActive", String(describing: p1), fallback: "Filter conversations, currently showing %@")
        }
        /// Location: ChatsView.swift - Filter option for all conversations
        public static let all = L10n.tr("Chats", "chats.filter.all", fallback: "All")
        /// Location: ChatsView.swift - Button to clear active filter
        public static let clear = L10n.tr("Chats", "chats.filter.clear", fallback: "Clear Filter")
        /// Location: ChatsView.swift - Filter menu title
        public static let title = L10n.tr("Chats", "chats.filter.title", fallback: "Filter")
      }
      public enum Input {
        /// Location: ChatInputBar.swift - Accessibility hint for text input
        public static let accessibilityHint = L10n.tr("Chats", "chats.input.accessibilityHint", fallback: "Type your message here")
        /// Location: ChatInputBar.swift - Accessibility label for text input
        public static let accessibilityLabel = L10n.tr("Chats", "chats.input.accessibilityLabel", fallback: "Message input")
        /// Location: ChatInputBar.swift - Accessibility label for character count - %d is current, %d is max
        public static func characterCount(_ p1: Int, _ p2: Int) -> String {
          return L10n.tr("Chats", "chats.input.characterCount", p1, p2, fallback: "%d of %d characters")
        }
        /// Location: ChatInputBar.swift - Accessibility hint when over character limit - %d is characters to remove
        public static func removeCharacters(_ p1: Int) -> String {
          return L10n.tr("Chats", "chats.input.removeCharacters", p1, fallback: "Remove %d characters to send")
        }
        /// Location: ChatInputBar.swift - Accessibility hint when not connected
        public static let requiresConnection = L10n.tr("Chats", "chats.input.requiresConnection", fallback: "Requires radio connection")
        /// Location: ChatInputBar.swift - Accessibility label for send button
        public static let sendMessage = L10n.tr("Chats", "chats.input.sendMessage", fallback: "Send message")
        /// Location: ChatInputBar.swift - Accessibility hint when ready to send
        public static let tapToSend = L10n.tr("Chats", "chats.input.tapToSend", fallback: "Tap to send your message")
        /// Location: ChatInputBar.swift - Accessibility label when message too long
        public static let tooLong = L10n.tr("Chats", "chats.input.tooLong", fallback: "Message too long")
        /// Location: ChatInputBar.swift - Accessibility hint when message is empty
        public static let typeFirst = L10n.tr("Chats", "chats.input.typeFirst", fallback: "Type a message first")
        public enum Placeholder {
          /// Location: ChatView.swift - Input bar placeholder for direct messages
          public static let directMessage = L10n.tr("Chats", "chats.input.placeholder.directMessage", fallback: "Private Message")
        }
      }
      public enum JoinFromMessage {
        /// Location: JoinHashtagFromMessageView.swift - Description of hashtag channels
        public static let description = L10n.tr("Chats", "chats.joinFromMessage.description", fallback: "Hashtag channels are public. Anyone can join by entering the same name.")
        /// Location: JoinHashtagFromMessageView.swift - Button to join channel - %@ is channel name
        public static func joinButton(_ p1: Any) -> String {
          return L10n.tr("Chats", "chats.joinFromMessage.joinButton", String(describing: p1), fallback: "Join %@")
        }
        /// Location: JoinHashtagFromMessageView.swift - Loading text
        public static let loading = L10n.tr("Chats", "chats.joinFromMessage.loading", fallback: "Loading...")
        /// Location: JoinHashtagFromMessageView.swift - Navigation title
        public static let title = L10n.tr("Chats", "chats.joinFromMessage.title", fallback: "Join Channel")
        public enum Error {
          /// Location: JoinHashtagFromMessageView.swift - Error for invalid channel name
          public static let invalidName = L10n.tr("Chats", "chats.joinFromMessage.error.invalidName", fallback: "Invalid channel name format.")
          /// Location: JoinHashtagFromMessageView.swift - Error when channel created but couldn't be loaded
          public static let loadFailed = L10n.tr("Chats", "chats.joinFromMessage.error.loadFailed", fallback: "Channel created but could not be loaded.")
          /// Location: JoinHashtagFromMessageView.swift - Error for no available slots
          public static let noSlots = L10n.tr("Chats", "chats.joinFromMessage.error.noSlots", fallback: "No available slots.")
        }
        public enum NoDevice {
          /// Location: JoinHashtagFromMessageView.swift - No device connected description - %@ is channel name
          public static func description(_ p1: Any) -> String {
            return L10n.tr("Chats", "chats.joinFromMessage.noDevice.description", String(describing: p1), fallback: "Connect a device to join %@.")
          }
          /// Location: JoinHashtagFromMessageView.swift - No device connected title
          public static let title = L10n.tr("Chats", "chats.joinFromMessage.noDevice.title", fallback: "No Device Connected")
        }
        public enum NoSlots {
          /// Location: JoinHashtagFromMessageView.swift - No slots available description - %@ is channel name
          public static func description(_ p1: Any) -> String {
            return L10n.tr("Chats", "chats.joinFromMessage.noSlots.description", String(describing: p1), fallback: "All channel slots are full. Remove an existing channel to join %@.")
          }
          /// Location: JoinHashtagFromMessageView.swift - No slots available title
          public static let title = L10n.tr("Chats", "chats.joinFromMessage.noSlots.title", fallback: "No Slots Available")
        }
      }
      public enum JoinHashtag {
        /// Location: JoinHashtagChannelView.swift - Footer label when channel already joined
        public static let alreadyJoined = L10n.tr("Chats", "chats.joinHashtag.alreadyJoined", fallback: "Already joined")
        /// Location: JoinHashtagChannelView.swift - Accessibility label for already joined
        public static let alreadyJoinedAccessibility = L10n.tr("Chats", "chats.joinHashtag.alreadyJoinedAccessibility", fallback: "Channel already joined")
        /// Location: JoinHashtagChannelView.swift - Description about encryption
        public static let encryptionDescription = L10n.tr("Chats", "chats.joinHashtag.encryptionDescription", fallback: "The channel name is used to generate the encryption key. Anyone with the same name can read messages.")
        /// Location: JoinHashtagChannelView.swift - Accessibility hint for existing channel
        public static let existingHint = L10n.tr("Chats", "chats.joinHashtag.existingHint", fallback: "Opens the channel you've already joined")
        /// Location: JoinHashtagChannelView.swift - Footer explaining hashtag channels
        public static let footer = L10n.tr("Chats", "chats.joinHashtag.footer", fallback: "Hashtag channels are public. Anyone can join by entering the same name. Only lowercase letters, numbers, and hyphens are allowed.")
        /// Location: JoinHashtagChannelView.swift - Button format for existing channel - %@ is channel name
        public static func goToButton(_ p1: Any) -> String {
          return L10n.tr("Chats", "chats.joinHashtag.goToButton", String(describing: p1), fallback: "Go to #%@")
        }
        /// Location: JoinHashtagChannelView.swift - Button format for new channel - %@ is channel name
        public static func joinButton(_ p1: Any) -> String {
          return L10n.tr("Chats", "chats.joinHashtag.joinButton", String(describing: p1), fallback: "Join #%@")
        }
        /// Location: JoinHashtagChannelView.swift - Accessibility hint for new channel
        public static let newHint = L10n.tr("Chats", "chats.joinHashtag.newHint", fallback: "Creates and joins this hashtag channel")
        /// Location: JoinHashtagChannelView.swift - Text field placeholder
        public static let placeholder = L10n.tr("Chats", "chats.joinHashtag.placeholder", fallback: "channel-name")
        /// Location: JoinHashtagChannelView.swift - Navigation title
        public static let title = L10n.tr("Chats", "chats.joinHashtag.title", fallback: "Join Hashtag Channel")
        public enum Section {
          /// Location: JoinHashtagChannelView.swift - Section header
          public static let header = L10n.tr("Chats", "chats.joinHashtag.section.header", fallback: "Hashtag Channel")
        }
      }
      public enum JoinPrivate {
        /// Location: JoinPrivateChannelView.swift - Footer explaining how to join
        public static let footer = L10n.tr("Chats", "chats.joinPrivate.footer", fallback: "Enter the channel name and secret key shared by the channel creator.")
        /// Location: JoinPrivateChannelView.swift - Button to join channel
        public static let joinButton = L10n.tr("Chats", "chats.joinPrivate.joinButton", fallback: "Join Channel")
        /// Location: JoinPrivateChannelView.swift - Text field placeholder for secret key
        public static let secretKeyPlaceholder = L10n.tr("Chats", "chats.joinPrivate.secretKeyPlaceholder", fallback: "Secret Key (32 hex characters)")
        /// Location: JoinPrivateChannelView.swift - Navigation title
        public static let title = L10n.tr("Chats", "chats.joinPrivate.title", fallback: "Join Private Channel")
        public enum Error {
          /// Location: JoinPrivateChannelView.swift - Error for invalid secret key format
          public static let invalidFormat = L10n.tr("Chats", "chats.joinPrivate.error.invalidFormat", fallback: "Invalid secret key format")
          /// Location: JoinPrivateChannelView.swift - Validation error for invalid secret
          public static let invalidSecret = L10n.tr("Chats", "chats.joinPrivate.error.invalidSecret", fallback: "Secret key must be exactly 32 hexadecimal characters (0-9, A-F)")
        }
      }
      public enum JoinPublic {
        /// Location: JoinPublicChannelView.swift - Button to add public channel
        public static let addButton = L10n.tr("Chats", "chats.joinPublic.addButton", fallback: "Add Public Channel")
        /// Location: JoinPublicChannelView.swift - Channel name displayed
        public static let channelName = L10n.tr("Chats", "chats.joinPublic.channelName", fallback: "Public Channel")
        /// Location: JoinPublicChannelView.swift - Description of public channel
        public static let description = L10n.tr("Chats", "chats.joinPublic.description", fallback: "The public channel is an open broadcast channel on slot 0. All devices on the mesh network can send and receive messages on this channel.")
        /// Location: JoinPublicChannelView.swift - Navigation title
        public static let title = L10n.tr("Chats", "chats.joinPublic.title", fallback: "Join Public Channel")
      }
      public enum Message {
        /// Location: ChatView.swift - Placeholder when message data is unavailable
        public static let unavailable = L10n.tr("Chats", "chats.message.unavailable", fallback: "Message unavailable")
        /// Location: ChatView.swift - Accessibility label for unavailable message
        public static let unavailableAccessibility = L10n.tr("Chats", "chats.message.unavailableAccessibility", fallback: "Message could not be loaded")
        public enum Action {
          /// Location: UnifiedMessageBubble.swift - Context menu action to copy
          public static let copy = L10n.tr("Chats", "chats.message.action.copy", fallback: "Copy")
          /// Location: UnifiedMessageBubble.swift - Context menu action to delete
          public static let delete = L10n.tr("Chats", "chats.message.action.delete", fallback: "Delete")
          /// Location: UnifiedMessageBubble.swift - Context menu submenu label
          public static let details = L10n.tr("Chats", "chats.message.action.details", fallback: "Details")
          /// Location: UnifiedMessageBubble.swift - Context menu action to view repeat details
          public static let repeatDetails = L10n.tr("Chats", "chats.message.action.repeatDetails", fallback: "Repeat Details")
          /// Location: UnifiedMessageBubble.swift - Context menu action to reply
          public static let reply = L10n.tr("Chats", "chats.message.action.reply", fallback: "Reply")
          /// Location: UnifiedMessageBubble.swift - Context menu action to send again
          public static let sendAgain = L10n.tr("Chats", "chats.message.action.sendAgain", fallback: "Send Again")
          /// Location: UnifiedMessageBubble.swift - Context menu action to view path
          public static let viewPath = L10n.tr("Chats", "chats.message.action.viewPath", fallback: "View Path")
        }
        public enum Hops {
          /// Location: UnifiedMessageBubble.swift - Hop count direct
          public static let direct = L10n.tr("Chats", "chats.message.hops.direct", fallback: "Direct")
        }
        public enum Info {
          /// Location: UnifiedMessageBubble.swift - Indicator that timestamp was adjusted
          public static let adjusted = L10n.tr("Chats", "chats.message.info.adjusted", fallback: "(adjusted)")
          /// Location: UnifiedMessageBubble.swift - Accessibility label for adjusted timestamp
          public static let adjustedAccessibility = L10n.tr("Chats", "chats.message.info.adjustedAccessibility", fallback: "Sent time adjusted due to sender clock error")
          /// Location: UnifiedMessageBubble.swift - Accessibility hint for adjusted timestamp
          public static let adjustedHint = L10n.tr("Chats", "chats.message.info.adjustedHint", fallback: "Sender's clock was incorrect")
          /// Location: UnifiedMessageBubble.swift - Context menu text showing heard repeats - %d is count, second %@ is "repeat" or "repeats"
          public static func heardRepeats(_ p1: Int, _ p2: Any) -> String {
            return L10n.tr("Chats", "chats.message.info.heardRepeats", p1, String(describing: p2), fallback: "Heard: %d %@")
          }
          /// Location: UnifiedMessageBubble.swift - Context menu text showing hop count - %@ is count or "Direct"
          public static func hops(_ p1: Any) -> String {
            return L10n.tr("Chats", "chats.message.info.hops", String(describing: p1), fallback: "Hops: %@")
          }
          /// Location: UnifiedMessageBubble.swift - Context menu text showing received time - %@ is formatted date
          public static func received(_ p1: Any) -> String {
            return L10n.tr("Chats", "chats.message.info.received", String(describing: p1), fallback: "Received: %@")
          }
          /// Location: UnifiedMessageBubble.swift - Context menu text showing round trip time - %d is milliseconds
          public static func roundTrip(_ p1: Int) -> String {
            return L10n.tr("Chats", "chats.message.info.roundTrip", p1, fallback: "Round trip: %dms")
          }
          /// Location: UnifiedMessageBubble.swift - Context menu text showing sent time - %@ is formatted date
          public static func sent(_ p1: Any) -> String {
            return L10n.tr("Chats", "chats.message.info.sent", String(describing: p1), fallback: "Sent: %@")
          }
          /// Location: UnifiedMessageBubble.swift - Context menu text showing SNR - %@ is formatted value
          public static func snr(_ p1: Any) -> String {
            return L10n.tr("Chats", "chats.message.info.snr", String(describing: p1), fallback: "SNR: %@")
          }
        }
        public enum Repeat {
          /// Location: UnifiedMessageBubble.swift - Plural form of repeats
          public static let plural = L10n.tr("Chats", "chats.message.repeat.plural", fallback: "repeats")
          /// Location: UnifiedMessageBubble.swift - Singular form of repeat
          public static let singular = L10n.tr("Chats", "chats.message.repeat.singular", fallback: "repeat")
        }
        public enum Sender {
          /// Location: UnifiedMessageBubble.swift - Fallback sender name
          public static let unknown = L10n.tr("Chats", "chats.message.sender.unknown", fallback: "Unknown")
        }
        public enum Status {
          /// Location: UnifiedMessageBubble.swift - Message status delivered
          public static let delivered = L10n.tr("Chats", "chats.message.status.delivered", fallback: "Delivered")
          /// Location: UnifiedMessageBubble.swift - Message status failed
          public static let failed = L10n.tr("Chats", "chats.message.status.failed", fallback: "Failed")
          /// Location: UnifiedMessageBubble.swift - Status row retry button
          public static let retry = L10n.tr("Chats", "chats.message.status.retry", fallback: "Retry")
          /// Location: UnifiedMessageBubble.swift - Message status retrying
          public static let retrying = L10n.tr("Chats", "chats.message.status.retrying", fallback: "Retrying...")
          /// Location: UnifiedMessageBubble.swift - Message status sending
          public static let sending = L10n.tr("Chats", "chats.message.status.sending", fallback: "Sending...")
          /// Location: UnifiedMessageBubble.swift - Message status sent
          public static let sent = L10n.tr("Chats", "chats.message.status.sent", fallback: "Sent")
          /// Location: UnifiedMessageBubble.swift - Message status sent multiple times - %d is count
          public static func sentMultiple(_ p1: Int) -> String {
            return L10n.tr("Chats", "chats.message.status.sentMultiple", p1, fallback: "Sent %d times")
          }
        }
      }
      public enum NewChat {
        /// Location: NewChatView.swift - Navigation title
        public static let title = L10n.tr("Chats", "chats.newChat.title", fallback: "New Chat")
        public enum ContactType {
          /// Location: NewChatView.swift - Contact type label for direct contacts
          public static let direct = L10n.tr("Chats", "chats.newChat.contactType.direct", fallback: "Direct")
          /// Location: NewChatView.swift - Contact type label for repeaters
          public static let repeater = L10n.tr("Chats", "chats.newChat.contactType.repeater", fallback: "Repeater")
          /// Location: NewChatView.swift - Contact type label for rooms
          public static let room = L10n.tr("Chats", "chats.newChat.contactType.room", fallback: "Room")
        }
        public enum EmptyState {
          /// Location: NewChatView.swift - Empty state description
          public static let description = L10n.tr("Chats", "chats.newChat.emptyState.description", fallback: "Contacts will appear when discovered")
          /// Location: NewChatView.swift - Empty state title
          public static let title = L10n.tr("Chats", "chats.newChat.emptyState.title", fallback: "No Contacts")
        }
        public enum Search {
          /// Location: NewChatView.swift - Search placeholder
          public static let placeholder = L10n.tr("Chats", "chats.newChat.search.placeholder", fallback: "Search contacts")
        }
      }
      public enum Path {
        /// Location: MessagePathSheet.swift - Accessibility label for copy button
        public static let copyAccessibility = L10n.tr("Chats", "chats.path.copyAccessibility", fallback: "Copy path to clipboard")
        /// Location: MessagePathSheet.swift - Button to copy path
        public static let copyButton = L10n.tr("Chats", "chats.path.copyButton", fallback: "Copy Path")
        /// Location: MessagePathSheet.swift - Accessibility hint for copy button
        public static let copyHint = L10n.tr("Chats", "chats.path.copyHint", fallback: "Copies node IDs as hexadecimal values")
        /// Location: MessagePathSheet.swift - Navigation title
        public static let title = L10n.tr("Chats", "chats.path.title", fallback: "Message Path")
        public enum Hop {
          /// Location: PathHopRowView.swift - Accessibility value format for non-last hops - %@ is hex ID
          public static func nodeId(_ p1: Any) -> String {
            return L10n.tr("Chats", "chats.path.hop.nodeId", String(describing: p1), fallback: "Node ID: %@")
          }
          /// Location: PathHopRowView.swift - Label for intermediate hops - %d is hop number
          public static func number(_ p1: Int) -> String {
            return L10n.tr("Chats", "chats.path.hop.number", p1, fallback: "Hop %d")
          }
          /// Location: PathHopRowView.swift - Label for sender (first hop)
          public static let sender = L10n.tr("Chats", "chats.path.hop.sender", fallback: "Sender")
          /// Location: PathHopRowView.swift - Accessibility value format for last hop - %@ is quality, %@ is SNR
          public static func signalQuality(_ p1: Any, _ p2: Any) -> String {
            return L10n.tr("Chats", "chats.path.hop.signalQuality", String(describing: p1), String(describing: p2), fallback: "Signal quality: %@, SNR %@ dB")
          }
          /// Location: PathHopRowView.swift - Unknown signal quality
          public static let signalUnknown = L10n.tr("Chats", "chats.path.hop.signalUnknown", fallback: "Unknown")
          /// Location: PathHopRowView.swift - Unknown node name
          public static let unknown = L10n.tr("Chats", "chats.path.hop.unknown", fallback: "<unknown>")
        }
        public enum Section {
          /// Location: MessagePathSheet.swift - Section header for path
          public static let header = L10n.tr("Chats", "chats.path.section.header", fallback: "Path")
        }
        public enum Unavailable {
          /// Location: MessagePathSheet.swift - Empty state description
          public static let description = L10n.tr("Chats", "chats.path.unavailable.description", fallback: "Path data is not available for this message")
          /// Location: MessagePathSheet.swift - Empty state title
          public static let title = L10n.tr("Chats", "chats.path.unavailable.title", fallback: "Path Unavailable")
        }
      }
      public enum Preview {
        /// Location: TapToLoadPreview.swift - Loading state text
        public static let loading = L10n.tr("Chats", "chats.preview.loading", fallback: "Loading preview...")
        /// Location: TapToLoadPreview.swift - Loading accessibility label format - %@ is host
        public static func loadingAccessibility(_ p1: Any) -> String {
          return L10n.tr("Chats", "chats.preview.loadingAccessibility", String(describing: p1), fallback: "Loading preview for %@")
        }
        /// Location: TapToLoadPreview.swift - Loading accessibility hint
        public static let loadingHint = L10n.tr("Chats", "chats.preview.loadingHint", fallback: "Please wait")
        /// Location: TapToLoadPreview.swift - Idle accessibility label format - %@ is host
        public static func tapAccessibility(_ p1: Any) -> String {
          return L10n.tr("Chats", "chats.preview.tapAccessibility", String(describing: p1), fallback: "Load preview for %@")
        }
        /// Location: TapToLoadPreview.swift - Idle accessibility hint
        public static let tapHint = L10n.tr("Chats", "chats.preview.tapHint", fallback: "Fetches title and image from the website")
        /// Location: TapToLoadPreview.swift - Idle state text
        public static let tapToLoad = L10n.tr("Chats", "chats.preview.tapToLoad", fallback: "Tap to load preview")
      }
      public enum Repeats {
        /// Location: RepeatDetailsSheet.swift - Navigation title
        public static let title = L10n.tr("Chats", "chats.repeats.title", fallback: "Repeat Details")
        /// Location: RepeatRowView.swift - Unknown repeater name
        public static let unknownRepeater = L10n.tr("Chats", "chats.repeats.unknownRepeater", fallback: "<unknown repeater>")
        public enum EmptyState {
          /// Location: RepeatDetailsSheet.swift - Empty state description
          public static let description = L10n.tr("Chats", "chats.repeats.emptyState.description", fallback: "Repeats will appear here as your message propagates through the mesh")
          /// Location: RepeatDetailsSheet.swift - Empty state title
          public static let title = L10n.tr("Chats", "chats.repeats.emptyState.title", fallback: "No repeats yet")
        }
        public enum Hop {
          /// Location: RepeatRowView.swift - Plural hops label - %d is count
          public static func plural(_ p1: Int) -> String {
            return L10n.tr("Chats", "chats.repeats.hop.plural", p1, fallback: "%d Hops")
          }
          /// Location: RepeatRowView.swift - Singular hop label
          public static let singular = L10n.tr("Chats", "chats.repeats.hop.singular", fallback: "1 Hop")
        }
        public enum Row {
          /// Location: RepeatRowView.swift - Accessibility label format - %@ is repeater name
          public static func accessibility(_ p1: Any) -> String {
            return L10n.tr("Chats", "chats.repeats.row.accessibility", String(describing: p1), fallback: "Repeat from %@")
          }
          /// Location: RepeatRowView.swift - Accessibility value format - %@ is quality, %@ is SNR, %@ is RSSI
          public static func accessibilityValue(_ p1: Any, _ p2: Any, _ p3: Any) -> String {
            return L10n.tr("Chats", "chats.repeats.row.accessibilityValue", String(describing: p1), String(describing: p2), String(describing: p3), fallback: "%@ signal, SNR %@, RSSI %@")
          }
        }
      }
      public enum Room {
        /// Location: RoomConversationRow.swift - Status when room is connected
        public static let connected = L10n.tr("Chats", "chats.room.connected", fallback: "Connected")
        /// Location: RoomConversationRow.swift - Prompt to reconnect to room
        public static let tapToReconnect = L10n.tr("Chats", "chats.room.tapToReconnect", fallback: "Tap to reconnect")
      }
      public enum RoomAuth {
        public enum NotFound {
          /// Location: RoomAuthenticationSheet.swift - Error description when room not found
          public static let description = L10n.tr("Chats", "chats.roomAuth.notFound.description", fallback: "Could not find the room contact")
          /// Location: RoomAuthenticationSheet.swift - Error title when room not found
          public static let title = L10n.tr("Chats", "chats.roomAuth.notFound.title", fallback: "Room Not Found")
        }
      }
      public enum Row {
        /// Location: ConversationRow.swift, ChannelConversationRow.swift, RoomConversationRow.swift - Accessibility label for favorite indicator
        public static let favorite = L10n.tr("Chats", "chats.row.favorite", fallback: "Favorite")
        /// Location: MutedIndicator.swift - Accessibility label for muted indicator
        public static let muted = L10n.tr("Chats", "chats.row.muted", fallback: "Muted")
        /// Location: ConversationRow.swift, ChannelConversationRow.swift - Default text when no messages exist
        public static let noMessages = L10n.tr("Chats", "chats.row.noMessages", fallback: "No messages yet")
      }
      public enum ScanQR {
        /// Location: ScanChannelQRView.swift - Instruction to point camera
        public static let instruction = L10n.tr("Chats", "chats.scanQR.instruction", fallback: "Point your camera at a channel QR code")
        /// Location: ScanChannelQRView.swift - Button to open settings
        public static let openSettings = L10n.tr("Chats", "chats.scanQR.openSettings", fallback: "Open Settings")
        /// Location: ScanChannelQRView.swift - Button to scan again
        public static let scanAgain = L10n.tr("Chats", "chats.scanQR.scanAgain", fallback: "Scan Again")
        /// Location: ScanChannelQRView.swift - Navigation title
        public static let title = L10n.tr("Chats", "chats.scanQR.title", fallback: "Scan QR Code")
        public enum Error {
          /// Location: ScanChannelQRView.swift - Error for invalid channel data
          public static let invalidData = L10n.tr("Chats", "chats.scanQR.error.invalidData", fallback: "Invalid channel data in QR code")
          /// Location: ScanChannelQRView.swift - Error for invalid QR format
          public static let invalidFormat = L10n.tr("Chats", "chats.scanQR.error.invalidFormat", fallback: "Invalid QR code format")
        }
        public enum NotAvailable {
          /// Location: ScanChannelQRView.swift - Error description when scanner not available
          public static let description = L10n.tr("Chats", "chats.scanQR.notAvailable.description", fallback: "QR scanning is not supported on this device")
          /// Location: ScanChannelQRView.swift - Error when scanner not available
          public static let title = L10n.tr("Chats", "chats.scanQR.notAvailable.title", fallback: "Scanner Not Available")
        }
        public enum PermissionDenied {
          /// Location: ScanChannelQRView.swift - Camera permission denied message
          public static let message = L10n.tr("Chats", "chats.scanQR.permissionDenied.message", fallback: "Please enable camera access in Settings to scan QR codes.")
          /// Location: ScanChannelQRView.swift - Camera permission denied title
          public static let title = L10n.tr("Chats", "chats.scanQR.permissionDenied.title", fallback: "Camera Access Required")
        }
      }
      public enum Search {
        /// Location: ChatsView.swift - Search placeholder
        public static let placeholder = L10n.tr("Chats", "chats.search.placeholder", fallback: "Search conversations")
      }
      public enum Section {
        /// Location: ConversationListContent.swift - Section accessibility label for other conversations
        public static let conversations = L10n.tr("Chats", "chats.section.conversations", fallback: "Conversations")
        /// Location: ConversationListContent.swift - Section accessibility label for favorites
        public static let favorites = L10n.tr("Chats", "chats.section.favorites", fallback: "Favorites")
      }
      public enum Signal {
        /// Location: UnifiedMessageBubble.swift - SNR quality excellent
        public static let excellent = L10n.tr("Chats", "chats.signal.excellent", fallback: "Excellent")
        /// Location: UnifiedMessageBubble.swift - SNR quality fair
        public static let fair = L10n.tr("Chats", "chats.signal.fair", fallback: "Fair")
        /// Location: UnifiedMessageBubble.swift - SNR quality good
        public static let good = L10n.tr("Chats", "chats.signal.good", fallback: "Good")
        /// Location: UnifiedMessageBubble.swift - SNR quality poor
        public static let poor = L10n.tr("Chats", "chats.signal.poor", fallback: "Poor")
        /// Location: UnifiedMessageBubble.swift - SNR quality very poor
        public static let veryPoor = L10n.tr("Chats", "chats.signal.veryPoor", fallback: "Very Poor")
      }
      public enum SwipeAction {
        /// Location: ConversationSwipeActionsModifier.swift - Swipe action to delete
        public static let delete = L10n.tr("Chats", "chats.swipeAction.delete", fallback: "Delete")
        /// Location: ConversationSwipeActionsModifier.swift - Swipe action to add to favorites
        public static let favorite = L10n.tr("Chats", "chats.swipeAction.favorite", fallback: "Favorite")
        /// Location: ConversationSwipeActionsModifier.swift - Swipe action to mute
        public static let mute = L10n.tr("Chats", "chats.swipeAction.mute", fallback: "Mute")
        /// Location: ConversationSwipeActionsModifier.swift - Swipe action to remove from favorites
        public static let unfavorite = L10n.tr("Chats", "chats.swipeAction.unfavorite", fallback: "Unfavorite")
        /// Location: ConversationSwipeActionsModifier.swift - Swipe action to unmute
        public static let unmute = L10n.tr("Chats", "chats.swipeAction.unmute", fallback: "Unmute")
      }
      public enum Timestamp {
        /// Location: MessageTimestampView.swift - Prefix for yesterday's date
        public static let yesterday = L10n.tr("Chats", "chats.timestamp.yesterday", fallback: "Yesterday")
      }
    }
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
    public enum DeviceScan {
      /// Location: DeviceScanView.swift - Button to add a new device
      public static let addDevice = L10n.tr("Onboarding", "deviceScan.addDevice", fallback: "Add Device")
      /// Location: DeviceScanView.swift - Message shown when device is already paired
      public static let alreadyPaired = L10n.tr("Onboarding", "deviceScan.alreadyPaired", fallback: "Your device is already paired")
      /// Location: DeviceScanView.swift - Button label while connecting
      public static let connecting = L10n.tr("Onboarding", "deviceScan.connecting", fallback: "Connecting...")
      /// Location: DeviceScanView.swift - Button to connect simulator (debug)
      public static let connectSimulator = L10n.tr("Onboarding", "deviceScan.connectSimulator", fallback: "Connect Simulator")
      /// Location: DeviceScanView.swift - Button to connect via WiFi
      public static let connectViaWifi = L10n.tr("Onboarding", "deviceScan.connectViaWifi", fallback: "Connect via WiFi")
      /// Location: DeviceScanView.swift - Button to continue after pairing
      public static let `continue` = L10n.tr("Onboarding", "deviceScan.continue", fallback: "Continue")
      /// Location: DeviceScanView.swift - Button to continue in demo mode
      public static let continueDemo = L10n.tr("Onboarding", "deviceScan.continueDemo", fallback: "Continue in Demo Mode")
      /// Location: DeviceScanView.swift - Button for troubleshooting
      public static let deviceNotAppearing = L10n.tr("Onboarding", "deviceScan.deviceNotAppearing", fallback: "Device not appearing?")
      /// Location: DeviceScanView.swift - Subtitle with pairing instructions
      public static let subtitle = L10n.tr("Onboarding", "deviceScan.subtitle", fallback: "Make sure your MeshCore device is powered on and nearby")
      /// Location: DeviceScanView.swift - Screen title for device pairing
      public static let title = L10n.tr("Onboarding", "deviceScan.title", fallback: "Pair Your Device")
      public enum DemoModeAlert {
        /// Location: DeviceScanView.swift - Alert message for demo mode
        public static let message = L10n.tr("Onboarding", "deviceScan.demoModeAlert.message", fallback: "You can now continue without a device. Toggle demo mode in Settings anytime.")
        /// Location: DeviceScanView.swift - Alert title when demo mode is unlocked
        public static let title = L10n.tr("Onboarding", "deviceScan.demoModeAlert.title", fallback: "Demo Mode Unlocked")
      }
      public enum Instruction {
        /// Location: DeviceScanView.swift - Instruction step 4
        public static let enterPin = L10n.tr("Onboarding", "deviceScan.instruction.enterPin", fallback: "Enter the PIN when prompted")
        /// Location: DeviceScanView.swift - Instruction step 1
        public static let powerOn = L10n.tr("Onboarding", "deviceScan.instruction.powerOn", fallback: "Power on your MeshCore device")
        /// Location: DeviceScanView.swift - Instruction step 3
        public static let selectDevice = L10n.tr("Onboarding", "deviceScan.instruction.selectDevice", fallback: "Select your device from the list")
        /// Location: DeviceScanView.swift - Instruction step 2
        public static let tapAdd = L10n.tr("Onboarding", "deviceScan.instruction.tapAdd", fallback: "Tap \"Add Device\" below")
      }
    }
    public enum MeshAnimation {
      /// Location: MeshAnimationView.swift - Accessibility label for mesh visualization
      public static let accessibilityLabel = L10n.tr("Onboarding", "meshAnimation.accessibilityLabel", fallback: "Mesh network visualization")
    }
    public enum Permissions {
      /// Location: PermissionsView.swift - Button to allow a permission
      public static let allow = L10n.tr("Onboarding", "permissions.allow", fallback: "Allow")
      /// Location: PermissionsView.swift - Button to go back
      public static let back = L10n.tr("Onboarding", "permissions.back", fallback: "Back")
      /// Location: PermissionsView.swift - Button when all permissions granted
      public static let `continue` = L10n.tr("Onboarding", "permissions.continue", fallback: "Continue")
      /// Location: PermissionsView.swift - Button to open system settings
      public static let openSettings = L10n.tr("Onboarding", "permissions.openSettings", fallback: "Settings")
      /// Location: PermissionsView.swift - Badge shown for optional permissions
      public static let `optional` = L10n.tr("Onboarding", "permissions.optional", fallback: "Optional")
      /// Location: PermissionsView.swift - Button when some permissions skipped
      public static let skipForNow = L10n.tr("Onboarding", "permissions.skipForNow", fallback: "Skip for Now")
      /// Location: PermissionsView.swift - Subtitle encouraging notification permission
      public static let subtitle = L10n.tr("Onboarding", "permissions.subtitle", fallback: "Allow Notifications for the best experience")
      /// Location: PermissionsView.swift - Screen title for permissions
      public static let title = L10n.tr("Onboarding", "permissions.title", fallback: "Permissions")
      public enum Location {
        /// Location: PermissionsView.swift - Permission card description for location
        public static let description = L10n.tr("Onboarding", "permissions.location.description", fallback: "See your location on the map")
        /// Location: PermissionsView.swift - Permission card title for location
        public static let title = L10n.tr("Onboarding", "permissions.location.title", fallback: "Location")
      }
      public enum LocationAlert {
        /// Location: PermissionsView.swift - Alert message explaining denied location permission
        public static let message = L10n.tr("Onboarding", "permissions.locationAlert.message", fallback: "Location permission was previously denied. Please enable it in Settings to share your location with mesh contacts.")
        /// Location: PermissionsView.swift - Alert button to open settings
        public static let openSettings = L10n.tr("Onboarding", "permissions.locationAlert.openSettings", fallback: "Open Settings")
        /// Location: PermissionsView.swift - Alert title for location permission
        public static let title = L10n.tr("Onboarding", "permissions.locationAlert.title", fallback: "Location Permission")
      }
      public enum Notifications {
        /// Location: PermissionsView.swift - Permission card description for notifications
        public static let description = L10n.tr("Onboarding", "permissions.notifications.description", fallback: "Receive alerts for new messages")
        /// Location: PermissionsView.swift - Permission card title for notifications
        public static let title = L10n.tr("Onboarding", "permissions.notifications.title", fallback: "Notifications")
      }
    }
    public enum RadioPreset {
      /// Location: RadioPresetOnboardingView.swift - Button to apply selected preset
      public static let apply = L10n.tr("Onboarding", "radioPreset.apply", fallback: "Apply")
      /// Location: RadioPresetOnboardingView.swift - Button label while applying preset
      public static let applying = L10n.tr("Onboarding", "radioPreset.applying", fallback: "Applying...")
      /// Location: RadioPresetOnboardingView.swift - Button to continue
      public static let `continue` = L10n.tr("Onboarding", "radioPreset.continue", fallback: "Continue")
      /// Location: RadioPresetOnboardingView.swift - Label for custom (non-preset) radio settings
      public static let custom = L10n.tr("Onboarding", "radioPreset.custom", fallback: "Custom")
      /// Location: RadioPresetOnboardingView.swift - Button to skip radio setup
      public static let skip = L10n.tr("Onboarding", "radioPreset.skip", fallback: "Skip")
      /// Location: RadioPresetOnboardingView.swift - Subtitle with instructions and Discord link
      public static let subtitle = L10n.tr("Onboarding", "radioPreset.subtitle", fallback: "You can change these settings at any time in PocketMesh's Settings. If you're not sure which preset to use, ask in the [MeshCore Discord](https://meshcore.co.uk/contact.html)")
      /// Location: RadioPresetOnboardingView.swift - Screen title for radio settings
      public static let title = L10n.tr("Onboarding", "radioPreset.title", fallback: "Radio Settings")
    }
    public enum Troubleshooting {
      /// Location: DeviceScanView.swift - Navigation title for troubleshooting sheet
      public static let title = L10n.tr("Onboarding", "troubleshooting.title", fallback: "Troubleshooting")
      public enum BasicChecks {
        /// Location: DeviceScanView.swift - Section header for basic checks
        public static let header = L10n.tr("Onboarding", "troubleshooting.basicChecks.header", fallback: "Basic Checks")
        /// Location: DeviceScanView.swift - Check to move device closer
        public static let moveCloser = L10n.tr("Onboarding", "troubleshooting.basicChecks.moveCloser", fallback: "Move the device closer to your phone")
        /// Location: DeviceScanView.swift - Check to ensure device is powered on
        public static let powerOn = L10n.tr("Onboarding", "troubleshooting.basicChecks.powerOn", fallback: "Make sure your device is powered on")
        /// Location: DeviceScanView.swift - Check to restart the device
        public static let restart = L10n.tr("Onboarding", "troubleshooting.basicChecks.restart", fallback: "Restart the MeshCore device")
      }
      public enum FactoryReset {
        /// Location: DeviceScanView.swift - Button to clear previous pairing
        public static let clearPairing = L10n.tr("Onboarding", "troubleshooting.factoryReset.clearPairing", fallback: "Clear Previous Pairing")
        /// Location: DeviceScanView.swift - Additional explanation about removal confirmation
        public static let confirmationNote = L10n.tr("Onboarding", "troubleshooting.factoryReset.confirmationNote", fallback: "Tapping below will ask you to confirm removing the old pairing. This is normal — it allows your reset device to appear again.")
        /// Location: DeviceScanView.swift - Explanation about stale pairings
        public static let explanation = L10n.tr("Onboarding", "troubleshooting.factoryReset.explanation", fallback: "If you factory-reset your MeshCore device, iOS may still have the old pairing stored. Clearing this in system Settings allows the device to appear again.")
        /// Location: DeviceScanView.swift - Section header for factory reset help
        public static let header = L10n.tr("Onboarding", "troubleshooting.factoryReset.header", fallback: "Factory Reset Device?")
        /// Location: DeviceScanView.swift - Footer when no pairings found
        public static let noPairings = L10n.tr("Onboarding", "troubleshooting.factoryReset.noPairings", fallback: "No previous pairings found.")
        /// Location: DeviceScanView.swift - Footer showing pairing count - uses stringsdict
        public static func pairingsFound(_ p1: Int) -> String {
          return L10n.tr("Onboarding", "troubleshooting.factoryReset.pairingsFound", p1, fallback: "Found %d previous pairing(s).")
        }
      }
      public enum SystemSettings {
        /// Location: DeviceScanView.swift - Section header for system settings info
        public static let header = L10n.tr("Onboarding", "troubleshooting.systemSettings.header", fallback: "System Settings")
        /// Location: DeviceScanView.swift - Info about managing accessories
        public static let manageAccessories = L10n.tr("Onboarding", "troubleshooting.systemSettings.manageAccessories", fallback: "You can also manage Bluetooth accessories in:")
        /// Location: DeviceScanView.swift - Path to accessories in settings
        public static let path = L10n.tr("Onboarding", "troubleshooting.systemSettings.path", fallback: "Settings → Privacy & Security → Accessories")
      }
    }
    public enum Welcome {
      /// Location: WelcomeView.swift - Button to proceed to next onboarding step
      public static let getStarted = L10n.tr("Onboarding", "welcome.getStarted", fallback: "Get Started")
      /// Location: WelcomeView.swift - Subtitle describing the app
      public static let subtitle = L10n.tr("Onboarding", "welcome.subtitle", fallback: "Unofficial MeshCore client for iOS")
      /// Location: WelcomeView.swift - App title displayed on welcome screen
      public static let title = L10n.tr("Onboarding", "welcome.title", fallback: "PocketMesh")
      public enum Feature {
        public enum Community {
          /// Location: WelcomeView.swift - Feature description for community network
          public static let description = L10n.tr("Onboarding", "welcome.feature.community.description", fallback: "Network built by users like you")
          /// Location: WelcomeView.swift - Feature title for community network
          public static let title = L10n.tr("Onboarding", "welcome.feature.community.title", fallback: "Community Network")
        }
        public enum MultiHop {
          /// Location: WelcomeView.swift - Feature description for multi-hop routing
          public static let description = L10n.tr("Onboarding", "welcome.feature.multiHop.description", fallback: "Your message finds a path across the mesh")
          /// Location: WelcomeView.swift - Feature title for multi-hop routing
          public static let title = L10n.tr("Onboarding", "welcome.feature.multiHop.title", fallback: "Multi-Hop Routing")
        }
      }
    }
    public enum WifiConnection {
      /// Location: WiFiConnectionSheet.swift - Button to initiate connection
      public static let connect = L10n.tr("Onboarding", "wifiConnection.connect", fallback: "Connect")
      /// Location: WiFiConnectionSheet.swift - Button label while connecting
      public static let connecting = L10n.tr("Onboarding", "wifiConnection.connecting", fallback: "Connecting...")
      /// Location: WiFiConnectionSheet.swift - Navigation title
      public static let title = L10n.tr("Onboarding", "wifiConnection.title", fallback: "Connect via WiFi")
      public enum ConnectionDetails {
        /// Location: WiFiConnectionSheet.swift - Footer explaining connection details
        public static let footer = L10n.tr("Onboarding", "wifiConnection.connectionDetails.footer", fallback: "Enter your MeshCore device's local network address. The default port is 5000.")
        /// Location: WiFiConnectionSheet.swift - Section header for connection details
        public static let header = L10n.tr("Onboarding", "wifiConnection.connectionDetails.header", fallback: "Connection Details")
      }
      public enum Error {
        /// Location: WiFiConnectionSheet.swift - Error message for invalid port
        public static let invalidPort = L10n.tr("Onboarding", "wifiConnection.error.invalidPort", fallback: "Invalid port number")
      }
      public enum IpAddress {
        /// Location: WiFiConnectionSheet.swift - Accessibility label for clear IP button
        public static let clearAccessibility = L10n.tr("Onboarding", "wifiConnection.ipAddress.clearAccessibility", fallback: "Clear IP address")
        /// Location: WiFiConnectionSheet.swift - Placeholder for IP address field
        public static let placeholder = L10n.tr("Onboarding", "wifiConnection.ipAddress.placeholder", fallback: "IP Address")
      }
      public enum Port {
        /// Location: WiFiConnectionSheet.swift - Accessibility label for clear port button
        public static let clearAccessibility = L10n.tr("Onboarding", "wifiConnection.port.clearAccessibility", fallback: "Clear port")
        /// Location: WiFiConnectionSheet.swift - Placeholder for port field
        public static let placeholder = L10n.tr("Onboarding", "wifiConnection.port.placeholder", fallback: "Port")
      }
    }
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
