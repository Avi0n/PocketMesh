import SwiftUI
import MC1Services

/// SwiftUI content view displayed inside the native MKAnnotationView callout
struct ContactCalloutContent: View {
    let contact: ContactDTO
    let onDetail: () -> Void
    let onMessage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(contact.displayName)
                .font(.headline)

            HStack(spacing: 6) {
                Image(systemName: contact.type.iconSystemName)
                    .foregroundStyle(contact.type.displayColor)
                Text(typeDisplayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Action buttons - same width
            VStack(spacing: 6) {
                Button(L10n.Map.Map.Callout.details, systemImage: "info.circle", action: onDetail)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                if contact.type == .chat || contact.type == .room {
                    Button(L10n.Map.Map.Callout.message, systemImage: "message.fill", action: onMessage)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .frame(width: 160)
    }

    // MARK: - Computed Properties

    private var typeDisplayName: String {
        switch contact.type {
        case .chat:
            L10n.Map.Map.Callout.NodeKind.contact
        case .repeater:
            L10n.Map.Map.Callout.NodeKind.repeater
        case .room:
            L10n.Map.Map.Callout.NodeKind.room
        }
    }
}

// MARK: - Preview

#Preview {
    ContactCalloutContent(
        contact: ContactDTO(
            from: Contact(
                deviceID: UUID(),
                publicKey: Data(repeating: 0x01, count: 32),
                name: "Alice",
                typeRawValue: 0,
                latitude: 37.7749,
                longitude: -122.4194,
                isFavorite: true
            )
        ),
        onDetail: {},
        onMessage: {}
    )
    .background(Color(.systemBackground))
}
