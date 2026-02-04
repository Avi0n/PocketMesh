import SwiftUI
import TipKit

/// Tip shown after onboarding to guide users to send their first flood advert
struct SendFloodAdvertTip: Tip {
    static let hasCompletedOnboarding = Tips.Event(id: "hasCompletedOnboarding")

    var title: Text {
        Text(L10n.Chats.Chats.Tip.FloodAdvert.title)
    }

    var message: Text? {
        Text(L10n.Chats.Chats.Tip.FloodAdvert.message)
    }

    var image: Image? {
        Image(systemName: "dot.radiowaves.left.and.right")
    }

    var options: [TipOption] {
        [Tips.MaxDisplayCount(1)]
    }

    var rules: [Rule] {
        #Rule(Self.hasCompletedOnboarding) { $0.donations.count >= 1 }
    }
}
