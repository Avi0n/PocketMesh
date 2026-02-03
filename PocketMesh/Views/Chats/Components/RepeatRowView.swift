// PocketMesh/Views/Chats/Components/RepeatRowView.swift
import CoreLocation
import PocketMeshServices
import SwiftUI

/// Row displaying a single heard repeat with repeater info and signal quality.
struct RepeatRowView: View {
    let repeatEntry: MessageRepeatDTO
    let repeaters: [ContactDTO]
    let userLocation: CLLocation?

    var body: some View {
        HStack(alignment: .top) {
            // Left side: Repeater name, hash, and hop count
            VStack(alignment: .leading, spacing: 2) {
                Text(repeaterName)
                    .font(.body)

                Text(repeatEntry.repeaterHashFormatted)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospaced()

                Text(hopCountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Right side: Signal bars and metrics
            VStack(alignment: .trailing, spacing: 2) {
                Image(systemName: "cellularbars", variableValue: repeatEntry.snrLevel)
                    .foregroundStyle(signalColor)

                Text("SNR \(repeatEntry.snrFormatted)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("RSSI \(repeatEntry.rssiFormatted)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.Chats.Chats.Repeats.Row.accessibility(repeaterName))
        .accessibilityValue(L10n.Chats.Chats.Repeats.Row.accessibilityValue(signalQuality, repeatEntry.snrFormatted, repeatEntry.rssiFormatted))
    }

    // MARK: - Helpers

    /// Signal color based on SNR quality thresholds
    private var signalColor: Color {
        guard let snr = repeatEntry.snr else { return .secondary }
        if snr > 10 { return .green }
        if snr > 5 { return .yellow }
        return .red
    }

    /// Signal quality description for accessibility
    private var signalQuality: String {
        guard let snr = repeatEntry.snr else { return L10n.Chats.Chats.Path.Hop.signalUnknown }
        if snr > 10 { return L10n.Chats.Chats.Signal.excellent }
        if snr > 5 { return L10n.Chats.Chats.Signal.good }
        return L10n.Chats.Chats.Signal.poor
    }

    /// Hop count text with proper pluralization
    private var hopCountText: String {
        let count = repeatEntry.hopCount
        return count == 1 ? L10n.Chats.Chats.Repeats.Hop.singular : L10n.Chats.Chats.Repeats.Hop.plural(count)
    }

    /// Resolve repeater name from repeaters list or show placeholder
    private var repeaterName: String {
        guard let repeaterByte = repeatEntry.repeaterByte else {
            return L10n.Chats.Chats.Repeats.unknownRepeater
        }

        if let repeater = RepeaterResolver.bestMatch(for: repeaterByte, in: repeaters, userLocation: userLocation) {
            return repeater.displayName
        }

        return L10n.Chats.Chats.Repeats.unknownRepeater
    }
}

#Preview {
    List {
        RepeatRowView(
            repeatEntry: MessageRepeatDTO(
                messageID: UUID(),
                receivedAt: Date(),
                pathNodes: Data([0xA3]),
                snr: 6.2,
                rssi: -85,
                rxLogEntryID: nil
            ),
            repeaters: [],
            userLocation: nil
        )

        RepeatRowView(
            repeatEntry: MessageRepeatDTO(
                messageID: UUID(),
                receivedAt: Date(),
                pathNodes: Data([0x7F]),
                snr: 2.1,
                rssi: -102,
                rxLogEntryID: nil
            ),
            repeaters: [],
            userLocation: nil
        )
    }
}
