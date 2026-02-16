import SwiftUI
import PocketMeshServices

/// Manages tab selection, pending navigation targets, and cross-tab navigation coordination.
@Observable
@MainActor
public final class NavigationCoordinator {

    /// Selected tab index
    var selectedTab: Int = 0

    var tabBarVisibility: Visibility = .visible

    /// Contact to navigate to
    var pendingChatContact: ContactDTO?

    /// The currently selected route in the Chats split view detail pane
    var chatsSelectedRoute: ChatRoute?

    /// Channel to navigate to
    var pendingChannel: ChannelDTO?

    /// Room session to navigate to
    var pendingRoomSession: RemoteNodeSessionDTO?

    /// Whether to navigate to Discovery
    var pendingDiscoveryNavigation = false

    /// Contact to navigate to (for detail view on Contacts tab)
    var pendingContactDetail: ContactDTO?

    /// Message to scroll to after navigation (for reaction notifications)
    var pendingScrollToMessageID: UUID?

    /// Whether device menu tip donation is pending (waiting for valid tab)
    var pendingDeviceMenuTipDonation = false

    // MARK: - Navigation

    func navigateToChat(with contact: ContactDTO, scrollToMessageID: UUID? = nil) {
        tabBarVisibility = .hidden  // Hide tab bar BEFORE switching tabs
        pendingChatContact = contact
        pendingScrollToMessageID = scrollToMessageID
        chatsSelectedRoute = .direct(contact)
        selectedTab = 0
    }

    func navigateToRoom(with session: RemoteNodeSessionDTO) {
        tabBarVisibility = .hidden  // Hide tab bar BEFORE switching tabs
        pendingRoomSession = session
        chatsSelectedRoute = .room(session)
        selectedTab = 0
    }

    func navigateToChannel(with channel: ChannelDTO, scrollToMessageID: UUID? = nil) {
        tabBarVisibility = .hidden
        pendingChannel = channel
        pendingScrollToMessageID = scrollToMessageID
        chatsSelectedRoute = .channel(channel)
        selectedTab = 0
    }

    func navigateToDiscovery() {
        pendingDiscoveryNavigation = true
        selectedTab = 1
    }

    func navigateToContacts() {
        selectedTab = 1
    }

    func navigateToContactDetail(_ contact: ContactDTO) {
        pendingContactDetail = contact
        selectedTab = 1
    }

    func clearPendingNavigation() {
        pendingChatContact = nil
    }

    func clearPendingRoomNavigation() {
        pendingRoomSession = nil
    }

    func clearPendingChannelNavigation() {
        pendingChannel = nil
    }

    func clearPendingDiscoveryNavigation() {
        pendingDiscoveryNavigation = false
    }

    func clearPendingScrollToMessage() {
        pendingScrollToMessageID = nil
    }

    func clearPendingContactDetailNavigation() {
        pendingContactDetail = nil
    }
}
