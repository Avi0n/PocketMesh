@preconcurrency import ActivityKit
import Foundation
import MeshCore
import OSLog
import PocketMeshServices

@Observable
@MainActor
public final class LiveActivityManager {

    static let enabledKey = "liveActivityEnabled"

    private let logger = Logger(subsystem: "com.pocketmesh", category: "LiveActivityManager")

    private var currentActivity: Activity<MeshStatusAttributes>?
    private var disconnectTimer: Task<Void, Never>?
    private var enablementTask: Task<Void, Never>?
    private var ocvArray: [Int] = []

    var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
    }

    // MARK: - Lifecycle

    func startObservingEnablement() {
        enablementTask?.cancel()
        enablementTask = Task { [weak self] in
            for await enabled in ActivityAuthorizationInfo().activityEnablementUpdates {
                guard let self else { break }
                if !enabled {
                    await self.endActivity()
                }
            }
        }
    }

    func handleConnectionReady(
        device: DeviceDTO,
        ocvArray: [Int],
        unreadCount: Int
    ) async {
        self.ocvArray = ocvArray

        // If reconnecting to same device within grace period, restore connected state
        if let activity = currentActivity,
           activity.attributes.deviceName == device.nodeName {
            disconnectTimer?.cancel()
            disconnectTimer = nil
            await updateActivity(
                isConnected: true,
                battery: .some(nil),
                lastRXDate: .some(nil),
                unreadCount: unreadCount,
                disconnectedDate: .some(nil)
            )
            return
        }

        // If reconnecting to a different device, end the old activity first
        if currentActivity != nil {
            await endActivity()
        }

        await startActivity(
            device: device,
            unreadCount: unreadCount
        )
    }

    func handleConnectionLost() async {
        guard currentActivity != nil else { return }

        await updateActivity(
            isConnected: false,
            battery: .some(nil),
            lastRXDate: .some(nil),
            unreadCount: 0,
            disconnectedDate: .some(.now)
        )

        disconnectTimer?.cancel()
        disconnectTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(300))
            guard !Task.isCancelled else { return }
            await self?.endActivity()
        }
    }

    func handlePacketReceived() async {
        await updateActivity(lastRXDate: .some(.now))
    }

    func handleBatteryChanged(battery: BatteryInfo) async {
        let percent = battery.percentage(using: ocvArray)
        await updateActivity(battery: .some(percent))
    }

    func handleUnreadCountChanged(unreadCount: Int) async {
        await updateActivity(unreadCount: unreadCount)
    }

    func setEnabled(_ enabled: Bool) async {
        UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
        if !enabled {
            await endActivity()
        }
    }

    // MARK: - App relaunch recovery

    func recoverExistingActivity() async {
        currentActivity = Activity<MeshStatusAttributes>.activities.first

        guard let activity = currentActivity,
              !activity.content.state.isConnected,
              let disconnectedDate = activity.content.state.disconnectedDate else {
            return
        }

        let elapsed = Date.now.timeIntervalSince(disconnectedDate)
        let remaining = 300 - elapsed

        if remaining > 0 {
            disconnectTimer = Task { [weak self] in
                try? await Task.sleep(for: .seconds(remaining))
                guard !Task.isCancelled else { return }
                await self?.endActivity()
            }
        } else {
            await endActivity()
        }
    }

    // MARK: - Private

    private func startActivity(
        device: DeviceDTO,
        unreadCount: Int
    ) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              isEnabled,
              !DemoModeManager.shared.isEnabled,
              Activity<MeshStatusAttributes>.activities.isEmpty else {
            return
        }

        let attributes = MeshStatusAttributes(deviceName: device.nodeName)
        let state = MeshStatusAttributes.ContentState(
            isConnected: true,
            batteryPercent: nil,
            lastRXDate: nil,
            unreadCount: unreadCount,
            disconnectedDate: nil
        )
        let staleDate = Calendar.current.date(byAdding: .minute, value: 5, to: .now)
        let content = ActivityContent(state: state, staleDate: staleDate)

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            LiveActivityTip.radioConnected.sendDonation()
            logger.info("Started Live Activity for \(device.nodeName, privacy: .public)")
        } catch {
            logger.error("Failed to start Live Activity: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Updates the Live Activity state. Pass `nil` to keep the current value, `.some(value)` to override.
    private func updateActivity(
        isConnected: Bool? = nil,
        battery: Int?? = nil,
        lastRXDate: Date?? = nil,
        unreadCount: Int? = nil,
        disconnectedDate: Date?? = nil
    ) async {
        guard let current = currentActivity?.content.state else { return }
        let state = MeshStatusAttributes.ContentState(
            isConnected: isConnected ?? current.isConnected,
            batteryPercent: battery ?? current.batteryPercent,
            lastRXDate: lastRXDate ?? current.lastRXDate,
            unreadCount: unreadCount ?? current.unreadCount,
            disconnectedDate: disconnectedDate ?? current.disconnectedDate
        )
        let staleDate = Calendar.current.date(byAdding: .minute, value: 5, to: .now)
        let content = ActivityContent(state: state, staleDate: staleDate)
        await currentActivity?.update(content)
    }

    func endActivity() async {
        disconnectTimer?.cancel()
        disconnectTimer = nil
        for activity in Activity<MeshStatusAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        currentActivity = nil
        logger.info("Ended Live Activity")
    }
}
