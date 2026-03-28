import MeshCore
import SwiftUI

extension ContactType {
    var iconSystemName: String {
        switch self {
        case .chat: "person.fill"
        case .repeater: "antenna.radiowaves.left.and.right"
        case .room: "person.3.fill"
        }
    }

    var displayColor: Color {
        switch self {
        case .chat: .blue
        case .repeater: .green
        case .room: .purple
        }
    }

    var pinStyle: MapPoint.PinStyle {
        switch self {
        case .chat: .contactChat
        case .repeater: .contactRepeater
        case .room: .contactRoom
        }
    }
}
