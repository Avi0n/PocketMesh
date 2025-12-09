import SwiftUI
import MapKit
import PocketMeshKit

/// Custom annotation view for displaying contacts on the map
struct ContactAnnotationView: View {
    let contact: ContactDTO
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Background circle
                Circle()
                    .fill(backgroundColor)
                    .frame(width: circleSize, height: circleSize)

                // Border for selected state
                if isSelected {
                    Circle()
                        .stroke(lineWidth: 3)
                        .foregroundStyle(.white)
                        .frame(width: circleSize, height: circleSize)
                }

                // Icon
                Image(systemName: iconName)
                    .font(.system(size: iconSize, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: .black.opacity(0.3), radius: 2, y: 2)

            // Pointer triangle
            Image(systemName: "triangle.fill")
                .font(.system(size: 10))
                .foregroundStyle(backgroundColor)
                .rotationEffect(.degrees(180))
                .offset(y: -3)
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }

    // MARK: - Computed Properties

    private var backgroundColor: Color {
        switch contact.type {
        case .chat:
            contact.isFavorite ? .orange : .blue
        case .repeater:
            .green
        case .room:
            .purple
        }
    }

    private var iconName: String {
        switch contact.type {
        case .chat:
            "person.fill"
        case .repeater:
            "antenna.radiowaves.left.and.right"
        case .room:
            "person.3.fill"
        }
    }

    private var circleSize: CGFloat {
        isSelected ? 44 : 36
    }

    private var iconSize: CGFloat {
        isSelected ? 20 : 16
    }
}

// MARK: - Contact Info Callout

/// Callout view shown when a contact annotation is selected
struct ContactAnnotationCallout: View {
    let contact: ContactDTO
    let onMessageTap: () -> Void
    let onDetailTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                // Contact type indicator
                Image(systemName: typeIconName)
                    .foregroundStyle(typeColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(contact.displayName)
                        .font(.headline)
                        .lineLimit(1)

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }

            Divider()

            // Action buttons - stacked vertically for smaller screens
            VStack(spacing: 8) {
                Button(action: onDetailTap) {
                    Label("Details", systemImage: "info.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                if contact.type == .chat || contact.type == .room {
                    Button(action: onMessageTap) {
                        Label("Message", systemImage: "message.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding()
        .frame(width: 200)
        .adaptiveGlassBackground(in: .rect(cornerRadius: 12))
        .shadow(radius: 4)
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

    private var subtitle: String? {
        switch contact.type {
        case .chat:
            contact.isFavorite ? "Favorite" : nil
        case .repeater:
            "Repeater"
        case .room:
            "Room"
        }
    }
}

// MARK: - Glass Effect Extension

extension View {
    /// Applies Liquid Glass effect on iOS 26+, falls back to solid color on older versions
    @ViewBuilder
    func adaptiveGlassBackground(in shape: some Shape = .rect(cornerRadius: 12)) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(Color(.secondarySystemBackground), in: shape)
        }
    }
}

// MARK: - Preview

#Preview("Chat Contact") {
    let contact = ContactDTO(
        from: Contact(
            deviceID: UUID(),
            publicKey: Data(repeating: 0x01, count: 32),
            name: "Alice",
            typeRawValue: 0,
            latitude: 37.7749,
            longitude: -122.4194,
            isFavorite: false
        )
    )

    return ContactAnnotationView(contact: contact, isSelected: false)
        .padding()
        .background(Color.gray.opacity(0.2))
}

#Preview("Repeater Selected") {
    let contact = ContactDTO(
        from: Contact(
            deviceID: UUID(),
            publicKey: Data(repeating: 0x02, count: 32),
            name: "Hilltop Repeater",
            typeRawValue: 1,
            latitude: 37.7749,
            longitude: -122.4194
        )
    )

    return ContactAnnotationView(contact: contact, isSelected: true)
        .padding()
        .background(Color.gray.opacity(0.2))
}

#Preview("Callout") {
    let contact = ContactDTO(
        from: Contact(
            deviceID: UUID(),
            publicKey: Data(repeating: 0x03, count: 32),
            name: "Emergency Room",
            typeRawValue: 2,
            latitude: 37.7749,
            longitude: -122.4194
        )
    )

    return ContactAnnotationCallout(
        contact: contact,
        onMessageTap: {},
        onDetailTap: {}
    )
    .padding()
}
