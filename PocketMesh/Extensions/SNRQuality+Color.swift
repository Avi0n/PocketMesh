import PocketMeshServices
import SwiftUI

extension SNRQuality {
    /// SwiftUI color for signal quality indicators.
    var color: Color {
        switch self {
        case .excellent: .green
        case .good: .yellow
        case .fair, .poor, .veryPoor: .red
        case .unknown: .secondary
        }
    }
}
