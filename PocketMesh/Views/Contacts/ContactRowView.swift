import SwiftUI
import CoreLocation
import PocketMeshServices

struct ContactRowView: View {
    let contact: ContactDTO
    let showTypeLabel: Bool
    let userLocation: CLLocation?
    let index: Int
    let isTogglingFavorite: Bool

    @State private var locality: String?

    init(
        contact: ContactDTO,
        showTypeLabel: Bool = false,
        userLocation: CLLocation? = nil,
        index: Int = 0,
        isTogglingFavorite: Bool = false
    ) {
        self.contact = contact
        self.showTypeLabel = showTypeLabel
        self.userLocation = userLocation
        self.index = index
        self.isTogglingFavorite = isTogglingFavorite
    }

    var body: some View {
        HStack(spacing: 12) {
            avatarView

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(contact.displayName)
                        .font(.body)
                        .fontWeight(.medium)

                    if contact.isBlocked {
                        Image(systemName: "hand.raised.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityLabel(L10n.Contacts.Contacts.Row.blocked)
                    }

                    Spacer()

                    if isTogglingFavorite {
                        ProgressView()
                            .controlSize(.small)
                    } else if contact.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .accessibilityLabel(L10n.Contacts.Contacts.Row.favorite)
                    }

                    RelativeTimestampText(timestamp: contact.lastAdvertTimestamp)
                }

                HStack(spacing: 4) {
                    // Show type label only in search results
                    if showTypeLabel {
                        Text(contactTypeLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Locality from reverse geocode
                    if let locality {
                        Text(locality)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Route indicator
                    Text(routeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Distance to contact
                    if let distance = distanceToContact {
                        Text(distance)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .alignmentGuide(.listRowSeparatorLeading) { dimensions in
                dimensions[.leading]
            }
        }
        .padding(.vertical, 4)
        .task(id: "\(contact.id)-\(contact.latitude)-\(contact.longitude)") {
            guard contact.hasLocation else { return }
            let coordinate = CLLocationCoordinate2D(
                latitude: contact.latitude,
                longitude: contact.longitude
            )
            locality = await ReverseGeocodeCache.shared.locality(for: coordinate)
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        switch contact.type {
        case .chat:
            ContactAvatar(contact: contact, size: 44)
        case .repeater:
            NodeAvatar(publicKey: contact.publicKey, role: .repeater, size: 44, index: index)
        case .room:
            NodeAvatar(publicKey: contact.publicKey, role: .roomServer, size: 44)
        }
    }

    private var contactTypeLabel: String {
        switch contact.type {
        case .chat: return L10n.Contacts.Contacts.NodeKind.contact
        case .repeater: return L10n.Contacts.Contacts.NodeKind.repeater
        case .room: return L10n.Contacts.Contacts.NodeKind.room
        }
    }

    private var routeLabel: String {
        if contact.isFloodRouted {
            return L10n.Contacts.Contacts.Route.flood
        } else if contact.pathHopCount == 0 {
            return L10n.Contacts.Contacts.Route.direct
        } else if contact.pathHopCount == 1 {
            return L10n.Contacts.Contacts.Route.hop(contact.pathHopCount)
        } else {
            return L10n.Contacts.Contacts.Route.hops(contact.pathHopCount)
        }
    }

    private var distanceToContact: String? {
        guard let userLocation, contact.hasLocation else { return nil }

        let contactLocation = CLLocation(
            latitude: contact.latitude,
            longitude: contact.longitude
        )
        let meters = userLocation.distance(from: contactLocation)
        let measurement = Measurement(value: meters, unit: UnitLength.meters)

        let formattedDistance = measurement.formatted(.measurement(
            width: .abbreviated,
            usage: .road
        ))
        return L10n.Contacts.Contacts.Row.away(formattedDistance)
    }
}
