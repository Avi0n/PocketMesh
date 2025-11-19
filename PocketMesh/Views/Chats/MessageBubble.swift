import SwiftUI
import PocketMeshKit

struct MessageBubble: View {

    let message: Message
    let onReply: () -> Void

    var body: some View {
        HStack {
            if message.isOutgoing {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.isOutgoing ? .trailing : .leading, spacing: 4) {
                // Message content
                Text(message.text)
                    .padding(12)
                    .background(message.isOutgoing ? Color.blue : Color(.systemGray5))
                    .foregroundStyle(message.isOutgoing ? .white : .primary)
                    .cornerRadius(16)

                // Metadata
                HStack(spacing: 4) {
                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if message.isOutgoing {
                        deliveryStatusIcon
                    }
                }
            }

            if !message.isOutgoing {
                Spacer(minLength: 60)
            }
        }
    }

    @ViewBuilder
    private var deliveryStatusIcon: some View {
        switch message.deliveryStatus {
        case .queued:
            Image(systemName: "clock.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .sending:
            ProgressView()
                .scaleEffect(0.5)
        case .sent:
            Image(systemName: "checkmark")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .acknowledged:
            Image(systemName: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
        case .received:
            EmptyView()
        }
    }
}
