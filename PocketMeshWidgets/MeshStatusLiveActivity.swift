import ActivityKit
import SwiftUI
import WidgetKit

struct MeshStatusLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MeshStatusAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(
                    context.state.isConnected ? .green.opacity(0.15) : .orange.opacity(0.2)
                )
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack {
                        Image(systemName: context.state.antennaIconName)
                            .accessibilityHidden(true)
                        Text(context.attributes.deviceName)
                            .bold()
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .accessibilityElement(children: .combine)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    BatteryLabel(percent: context.state.batteryPercent)
                }
                DynamicIslandExpandedRegion(.center) {
                    if context.state.isConnected {
                        RXFreshnessLabel(lastRXDate: context.state.lastRXDate)
                    } else {
                        Text("Disconnected")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.isConnected, context.state.unreadCount > 0 {
                        HStack {
                            Image(systemName: "envelope.badge")
                                .accessibilityHidden(true)
                            Text("\(context.state.unreadCount) unread")
                                .contentTransition(.numericText())
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityElement(children: .combine)
                    }

                    if !context.state.isConnected, let date = context.state.disconnectedDate {
                        Text(date, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.antennaIconName)
            } compactTrailing: {
                if context.state.isConnected, let lastRX = context.state.lastRXDate {
                    Text(lastRX, style: .relative)
                        .monospacedDigit()
                        .fixedSize()
                } else {
                    Text("—")
                }
            } minimal: {
                Image(systemName: context.state.antennaIconName)
            }
            .widgetURL(URL(string: "pocketmesh://status"))
        }
    }
}
