import ActivityKit
import Foundation

struct MeshStatusAttributes: ActivityAttributes, Sendable {
    let deviceName: String

    struct ContentState: Codable, Hashable, Sendable {
        var isConnected: Bool
        var batteryPercent: Int?
        var lastRXDate: Date?
        var unreadCount: Int
        var disconnectedDate: Date?

        var antennaIconName: String {
            isConnected
                ? "antenna.radiowaves.left.and.right"
                : "antenna.radiowaves.left.and.right.slash"
        }
    }
}
