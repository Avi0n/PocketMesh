// PocketMesh/Views/Chats/Components/RepeatRowView.swift
import SwiftUI
import PocketMeshServices

/// Row displaying a single heard repeat with repeater info and signal quality.
struct RepeatRowView: View {
    let repeatEntry: MessageRepeatDTO
    let contacts: [ContactDTO]

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
        .accessibilityLabel("Repeat from \(repeaterName)")
        .accessibilityValue("\(signalQuality) signal, SNR \(repeatEntry.snrFormatted), RSSI \(repeatEntry.rssiFormatted)")
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
        guard let snr = repeatEntry.snr else { return "Unknown" }
        if snr > 10 { return "Excellent" }
        if snr > 5 { return "Good" }
        return "Poor"
    }

    /// Hop count text with proper pluralization
    private var hopCountText: String {
        let count = repeatEntry.hopCount
        return count == 1 ? "1 Hop" : "\(count) Hops"
    }

    /// Resolve repeater name from contacts or show placeholder
    private var repeaterName: String {
        guard let repeaterByte = repeatEntry.repeaterByte else {
            return "<unknown repeater>"
        }

        // Try to find contact with matching public key prefix
        if let contact = contacts.first(where: { contact in
            guard let firstByte = contact.publicKey.first else { return false }
            return firstByte == repeaterByte
        }) {
            return contact.displayName
        }

        return "<unknown repeater>"
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
            contacts: []
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
            contacts: []
        )
    }
}
