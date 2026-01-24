// PocketMesh/Views/Chats/Components/PathHopRowView.swift
import SwiftUI
import PocketMeshServices

/// Row displaying a single hop in the message path.
struct PathHopRowView: View {
    let hopByte: UInt8
    let hopIndex: Int
    let isLastHop: Bool
    let snr: Double?
    let contacts: [ContactDTO]

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(nodeName)
                    .font(.body)

                Text(String(format: "%02X", hopByte))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospaced()

                Text(hopLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Show signal info only on last hop (where we have SNR)
            if isLastHop, let snr {
                VStack(alignment: .trailing, spacing: 2) {
                    Image(systemName: "cellularbars", variableValue: snrLevel(snr))
                        .foregroundStyle(signalColor(snr))

                    Text("SNR \(snr, format: .number.precision(.fractionLength(1))) dB")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(hopLabel): \(nodeName)")
        .accessibilityValue(isLastHop && snr != nil
            ? L10n.Chats.Chats.Path.Hop.signalQuality(signalQualityText, snr!.formatted(.number.precision(.fractionLength(1))))
            : L10n.Chats.Chats.Path.Hop.nodeId(String(format: "%02X", hopByte)))
    }

    private var nodeName: String {
        if let contact = contacts.first(where: { contact in
            guard let firstByte = contact.publicKey.first else { return false }
            return firstByte == hopByte
        }) {
            return contact.displayName
        }
        return L10n.Chats.Chats.Path.Hop.unknown
    }

    private var hopLabel: String {
        hopIndex == 0 ? L10n.Chats.Chats.Path.Hop.sender : L10n.Chats.Chats.Path.Hop.number(hopIndex)
    }

    private var signalQualityText: String {
        guard let snr else { return L10n.Chats.Chats.Path.Hop.signalUnknown }
        if snr > 10 { return L10n.Chats.Chats.Signal.excellent }
        if snr > 5 { return L10n.Chats.Chats.Signal.good }
        if snr > 0 { return L10n.Chats.Chats.Signal.fair }
        if snr > -10 { return L10n.Chats.Chats.Signal.poor }
        return L10n.Chats.Chats.Signal.veryPoor
    }

    private func snrLevel(_ snr: Double) -> Double {
        if snr > 10 { return 1.0 }
        if snr > 5 { return 0.75 }
        if snr > 0 { return 0.5 }
        if snr > -10 { return 0.25 }
        return 0
    }

    private func signalColor(_ snr: Double) -> Color {
        if snr > 10 { return .green }
        if snr > 5 { return .yellow }
        return .red
    }
}

#Preview {
    List {
        PathHopRowView(hopByte: 0xA3, hopIndex: 0, isLastHop: false, snr: nil, contacts: [])
        PathHopRowView(hopByte: 0x7F, hopIndex: 1, isLastHop: false, snr: nil, contacts: [])
        PathHopRowView(hopByte: 0x42, hopIndex: 2, isLastHop: true, snr: 6.2, contacts: [])
    }
}
