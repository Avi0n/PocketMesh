// PocketMesh/Views/Chats/Components/MessagePathContent.swift
import CoreLocation
import PocketMeshServices
import SwiftUI

/// Inline content for message path visualization, extracted from MessagePathSheet.
/// Shows sender, intermediate hops, receiver, raw path hex, and a copy button.
struct MessagePathContent: View {
    let message: MessageDTO
    let viewModel: MessagePathViewModel
    let receiverName: String
    let userLocation: CLLocation?

    @State private var copyHapticTrigger = 0

    private var pathBytes: [UInt8] {
        guard let pathNodes = message.pathNodes else { return [] }
        return Array(pathNodes)
    }

    var body: some View {
        if viewModel.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
        } else if message.pathNodes == nil {
            ContentUnavailableView(
                L10n.Chats.Chats.Path.Unavailable.title,
                systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                description: Text(L10n.Chats.Chats.Path.Unavailable.description)
            )
        } else {
            // Sender
            PathHopRowView(
                hopType: .sender,
                nodeName: viewModel.senderName(for: message),
                nodeID: viewModel.senderNodeID(for: message),
                snr: nil
            )

            // Intermediate hops
            ForEach(Array(pathBytes.enumerated()), id: \.offset) { index, byte in
                PathHopRowView(
                    hopType: .intermediate(index + 1),
                    nodeName: viewModel.repeaterName(
                        for: byte,
                        userLocation: userLocation
                    ),
                    nodeID: String(format: "%02X", byte),
                    snr: nil
                )
            }

            // Receiver
            PathHopRowView(
                hopType: .receiver,
                nodeName: receiverName,
                nodeID: nil,
                snr: message.snr
            )

            // Raw path hex + copy button
            if !pathBytes.isEmpty {
                HStack {
                    Text(message.pathString)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button(L10n.Chats.Chats.Path.copyButton, systemImage: "doc.on.doc") {
                        copyHapticTrigger += 1
                        UIPasteboard.general.string = message.pathStringForClipboard
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .accessibilityLabel(L10n.Chats.Chats.Path.copyAccessibility)
                    .accessibilityHint(L10n.Chats.Chats.Path.copyHint)
                }
                .padding(.top, 8)
                .sensoryFeedback(.success, trigger: copyHapticTrigger)
            }
        }
    }
}
