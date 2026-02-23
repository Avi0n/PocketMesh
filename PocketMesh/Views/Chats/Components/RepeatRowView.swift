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

    private var snrQuality: SNRQuality { repeatEntry.snrQuality }

    private var signalColor: Color { snrQuality.color }

    /// Signal quality description for accessibility
    private var signalQuality: String {
        switch snrQuality {
        case .excellent: L10n.Chats.Chats.Signal.excellent
        case .good: L10n.Chats.Chats.Signal.good
        case .fair: L10n.Chats.Chats.Signal.fair
        case .poor: L10n.Chats.Chats.Signal.poor
        case .veryPoor: L10n.Chats.Chats.Signal.veryPoor
        case .unknown: L10n.Chats.Chats.Path.Hop.signalUnknown
        }
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
