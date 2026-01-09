import Foundation
import MeshCore
import OSLog
import PocketMeshServices
import UIKit

/// Service for exporting debug logs and app state for troubleshooting
enum LogExportService {
    private static let logger = Logger(subsystem: "com.pocketmesh", category: "LogExportService")
    private static let subsystem = "com.pocketmesh"

    /// Generates a debug export containing app logs and current state
    @MainActor
    static func generateExport(appState: AppState) async -> String {
        var sections: [String] = []

        // Header
        sections.append(generateHeader())

        // Connection info
        sections.append(generateConnectionSection(appState: appState))

        // Device info (if connected)
        if let device = appState.connectedDevice {
            sections.append(generateDeviceSection(device: device))
        }

        // Battery info
        if let battery = appState.deviceBattery {
            sections.append(generateBatterySection(battery: battery))
        }

        // Logs
        sections.append(await generateLogsSection())

        return sections.joined(separator: "\n\n")
    }

    /// Creates a temporary file with the export content and returns its URL
    @MainActor
    static func createExportFile(appState: AppState) async -> URL? {
        let content = await generateExport(appState: appState)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let timestamp = formatter.string(from: Date())
        let filename = "PocketMesh-Debug-\(timestamp).txt"

        let tempURL = FileManager.default.temporaryDirectory.appending(path: filename)

        do {
            try content.write(to: tempURL, atomically: true, encoding: .utf8)
            return tempURL
        } catch {
            logger.error("Failed to write export file: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Section Generators

    private static func generateHeader() -> String {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        let deviceModel = UIDevice.current.model
        let systemVersion = UIDevice.current.systemVersion

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let exportedAt = formatter.string(from: Date())

        return """
            === PocketMesh Debug Export ===
            Exported: \(exportedAt)
            App Version: \(appVersion) (\(buildNumber))
            Device: \(deviceModel), iOS \(systemVersion)
            """
    }

    @MainActor
    private static func generateConnectionSection(appState: AppState) -> String {
        let state = appState.connectionState
        let stateString: String
        switch state {
        case .disconnected: stateString = "disconnected"
        case .connecting: stateString = "connecting"
        case .connected: stateString = "connected"
        case .ready: stateString = "ready"
        }

        var lines = [
            "=== Connection ===",
            "State: \(stateString)"
        ]

        if let device = appState.connectedDevice {
            lines.append("Device: \(device.nodeName) (\(device.id.uuidString.prefix(8))...)")

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            lines.append("Last Connected: \(formatter.string(from: device.lastConnected))")
        }

        return lines.joined(separator: "\n")
    }

    private static func generateDeviceSection(device: DeviceDTO) -> String {
        let frequencyMHz = Double(device.frequency) / 1000.0
        let bandwidthKHz = device.bandwidth

        return """
            === Device Info ===
            Name: \(device.nodeName)
            Firmware: \(device.firmwareVersionString) (v\(device.firmwareVersion))
            Manufacturer: \(device.manufacturerName)
            Build Date: \(device.buildDate)
            Radio: \(String(format: "%.3f", frequencyMHz)) MHz, BW \(bandwidthKHz) kHz, SF\(device.spreadingFactor), CR\(device.codingRate)
            TX Power: \(device.txPower) dBm (max \(device.maxTxPower))
            Max Contacts: \(device.maxContacts)
            Max Channels: \(device.maxChannels)
            Manual Add Contacts: \(device.manualAddContacts)
            Multi-ACKs: \(device.multiAcks)
            """
    }

    private static func generateBatterySection(battery: BatteryInfo) -> String {
        return """
            === Battery ===
            Level: \(battery.percentage)%
            Voltage: \(String(format: "%.2f", battery.voltage)) V
            Raw: \(battery.level) mV
            """
    }

    private static func generateLogsSection() async -> String {
        var lines = ["=== Logs (Last Hour) ==="]

        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let oneHourAgo = Date().addingTimeInterval(-3600)
            let position = store.position(date: oneHourAgo)

            let entries = try store.getEntries(at: position)
                .compactMap { $0 as? OSLogEntryLog }
                .filter { $0.subsystem == subsystem }
                .sorted { $0.date > $1.date }

            if entries.isEmpty {
                lines.append("(No logs found)")
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

                for entry in entries {
                    let timestamp = formatter.string(from: entry.date)
                    let level = levelLabel(for: entry.level)
                    let message = entry.composedMessage
                    lines.append("\(timestamp) [\(level)] \(entry.category): \(message)")
                }

                lines.append("")
                lines.append("Total entries: \(entries.count)")
            }
        } catch {
            lines.append("(Failed to fetch logs: \(error.localizedDescription))")
            logger.error("OSLogStore query failed: \(error.localizedDescription)")
        }

        return lines.joined(separator: "\n")
    }

    private static func levelLabel(for level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .error: return "ERROR"
        case .fault: return "FAULT"
        @unknown default: return "LOG"
        }
    }
}
