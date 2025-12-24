import SwiftUI
import TipKit

/// Tip shown after onboarding to guide users to send their first flood advert
struct SendFloodAdvertTip: Tip {
    static let hasCompletedOnboarding = Tips.Event(id: "hasCompletedOnboarding")

    var title: Text {
        Text("Announce yourself to the mesh")
    }

    var message: Text? {
        Text("Tap here and send a Flood Advert to let nearby devices know you've joined.")
    }

    var image: Image? {
        Image(systemName: "dot.radiowaves.left.and.right")
    }

    var rules: [Rule] {
        #Rule(Self.hasCompletedOnboarding) { $0.donations.count >= 1 }
    }
}
