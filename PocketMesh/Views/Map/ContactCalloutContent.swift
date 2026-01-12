import SwiftUI
import PocketMeshServices

/// SwiftUI content view displayed inside the native MKAnnotationView callout
struct ContactCalloutContent: View {
    let contact: ContactDTO
    let onDetail: () -> Void
    let onMessage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Type indicator only (name is in native callout title)
            HStack(spacing: 6) {
                Image(systemName: typeIconName)
                    .foregroundStyle(typeColor)
                Text(typeDisplayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Action buttons - same width
            VStack(spacing: 6) {
                Button("Details", systemImage: "info.circle", action: onDetail)
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                if contact.type == .chat || contact.type == .room {
                    Button("Message", systemImage: "message.fill", action: onMessage)
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

    private var typeIconName: String {
        switch contact.type {
        case .chat:
            "person.fill"
        case .repeater:
            "antenna.radiowaves.left.and.right"
        case .room:
            "person.3.fill"
        }
    }

    private var typeColor: Color {
        switch contact.type {
        case .chat:
            .blue
        case .repeater:
            .green
        case .room:
            .purple
        }
    }

    private var typeDisplayName: String {
        switch contact.type {
        case .chat:
            "Contact"
        case .repeater:
            "Repeater"
        case .room:
            "Room"
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
