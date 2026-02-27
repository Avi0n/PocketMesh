import ActivityKit
import SwiftUI
import WidgetKit

struct LockScreenView: View {
    let context: ActivityViewContext<MeshStatusAttributes>

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Image(systemName: context.state.antennaIconName)
                    .accessibilityHidden(true)

                Text(context.attributes.deviceName)
                    .bold()
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                if context.state.isConnected {
                    RXFreshnessLabel(lastRXDate: context.state.lastRXDate)
                } else {
                    Text("Disconnected")
                        .foregroundStyle(.orange)
                }

                BatteryLabel(percent: context.state.batteryPercent)
            }

            if context.state.isConnected, context.state.unreadCount > 0 {
                HStack {
                    Spacer()
                    Image(systemName: "envelope.badge")
                        .accessibilityHidden(true)
                    Text("\(context.state.unreadCount) unread")
                        .contentTransition(.numericText())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(context.state.unreadCount) unread messages")
            }

            if !context.state.isConnected, let disconnectedDate = context.state.disconnectedDate {
                HStack {
                    Spacer()
                    Text(disconnectedDate, style: .relative)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .accessibilityLabel("Disconnected \(Text(disconnectedDate, style: .relative)) ago")
            }
        }
        .padding()
        .accessibilityElement(children: .combine)
        .widgetURL(URL(string: "pocketmesh://status"))
    }
}

// MARK: - Subviews

struct RXFreshnessLabel: View {
    let lastRXDate: Date?

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "arrow.down")
                .font(.caption2)
                .accessibilityHidden(true)
            if let lastRXDate {
                Text(lastRXDate, style: .relative)
                    .monospacedDigit()
            } else {
                Text("—")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(lastRXDate.map { "Last received \(Text($0, style: .relative)) ago" } ?? "No data received")
    }
}

struct BatteryLabel: View {
    let percent: Int?

    var body: some View {
        if let percent {
            Image(systemName: batteryIconName(for: percent))
                .accessibilityLabel("Battery \(percent) percent")
        }
    }

    private func batteryIconName(for percent: Int) -> String {
        switch percent {
        case 88...100: "battery.100"
        case 63..<88: "battery.75"
        case 38..<63: "battery.50"
        case 13..<38: "battery.25"
        default: "battery.0"
        }
    }
}
