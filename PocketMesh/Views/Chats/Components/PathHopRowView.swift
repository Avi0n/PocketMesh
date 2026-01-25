// PocketMesh/Views/Chats/Components/PathHopRowView.swift
import SwiftUI
import PocketMeshServices

/// Type of hop in the message path.
enum PathHopType {
    case sender
    case intermediate(Int)
    case receiver
}

/// Row displaying a single hop in the message path.
struct PathHopRowView: View {
    let hopType: PathHopType
    let nodeName: String
    let nodeID: String?
    let snr: Double?

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(nodeName)
                    .font(.body)

                if let nodeID {
                    Text(nodeID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospaced()
                }

                Text(hopLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Show signal info only on receiver (where we have SNR)
            if case .receiver = hopType, let snr {
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
        .accessibilityValue(accessibilityValueText)
    }

    private var hopLabel: String {
        switch hopType {
        case .sender:
            return L10n.Chats.Chats.Path.Hop.sender
        case .intermediate(let index):
            return L10n.Chats.Chats.Path.Hop.number(index)
        case .receiver:
            return L10n.Chats.Chats.Path.Receiver.label
        }
    }

    private var accessibilityValueText: String {
        if case .receiver = hopType, let snr {
            let snrText = snr.formatted(.number.precision(.fractionLength(1)))
            return L10n.Chats.Chats.Path.Hop.signalQuality(signalQualityText, snrText)
        }
        if let nodeID {
            return L10n.Chats.Chats.Path.Hop.nodeId(nodeID)
        }
        return ""
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
        PathHopRowView(hopType: .sender, nodeName: "AlphaNode", nodeID: "A3", snr: nil)
        PathHopRowView(hopType: .intermediate(1), nodeName: "RelayNode", nodeID: "7F", snr: nil)
        PathHopRowView(hopType: .receiver, nodeName: "MyDevice", nodeID: nil, snr: 6.2)
    }
}
