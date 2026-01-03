import SwiftUI

extension ClearanceStatus {
    var color: Color {
        switch self {
        case .clear: .green
        case .marginal: .yellow
        case .partialObstruction: .orange
        case .blocked: .red
        }
    }

    var iconName: String {
        switch self {
        case .clear: "checkmark.circle.fill"
        case .marginal, .partialObstruction: "exclamationmark.triangle.fill"
        case .blocked: "xmark.octagon.fill"
        }
    }

    static var blockedSubtitle: String {
        "Direct path intersects terrain"
    }
}
