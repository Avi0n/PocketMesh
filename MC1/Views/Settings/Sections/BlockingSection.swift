import PocketMeshServices
import SwiftUI

/// Settings section for managing blocked channel users and contacts.
struct BlockingSection: View {
    var body: some View {
        Section {
            NavigationLink {
                BlockedChannelSendersView()
            } label: {
                TintedLabel(L10n.Settings.Blocking.channelSenders, systemImage: "person.crop.circle.badge.xmark")
            }

            NavigationLink {
                BlockedContactsView()
            } label: {
                TintedLabel(L10n.Settings.Blocking.contacts, systemImage: "hand.raised.slash")
            }
        } header: {
            Text(L10n.Settings.Blocking.header)
        }
    }
}
