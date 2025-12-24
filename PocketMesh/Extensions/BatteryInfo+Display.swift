import MeshCore
import SwiftUI

/// Display helpers for battery information.
/// Consolidates LiPo voltage-to-percentage calculation previously duplicated in
/// BLEStatusIndicatorView and DeviceInfoView.
extension BatteryInfo {
    /// Battery voltage in volts (converted from millivolts)
    var voltage: Double {
        Double(level) / 1000.0
    }

    /// Estimated percentage based on LiPo curve (4.2V = 100%, 3.0V = 0%)
    var percentage: Int {
        let percent = ((voltage - 3.0) / 1.2) * 100
        return Int(min(100, max(0, percent)))
    }

    /// SF Symbol name for battery level
    var iconName: String {
        switch percentage {
        case 88...100: "battery.100"
        case 63..<88: "battery.75"
        case 38..<63: "battery.50"
        case 13..<38: "battery.25"
        default: "battery.0"
        }
    }

    /// Color for battery display based on level
    var levelColor: Color {
        switch percentage {
        case 20...100: .primary
        case 10..<20: .orange
        default: .red
        }
    }
}
