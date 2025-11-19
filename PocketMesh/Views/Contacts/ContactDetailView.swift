import SwiftUI
import MapKit
import PocketMeshKit

struct ContactDetailView: View {

    let contact: Contact

    @State private var region: MKCoordinateRegion

    init(contact: Contact) {
        self.contact = contact

        if let lat = contact.latitude, let lon = contact.longitude {
            _region = State(initialValue: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
            ))
        } else {
            _region = State(initialValue: MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10)
            ))
        }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("Name")
                    Spacer()
                    Text(contact.name)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Type")
                    Spacer()
                    Text(contact.type.rawValue)
                        .foregroundStyle(.secondary)
                }

                if let lastAdvert = contact.lastAdvertisement {
                    HStack {
                        Text("Last Advertisement")
                        Spacer()
                        Text(lastAdvert, style: .relative)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let latitude = contact.latitude, let longitude = contact.longitude {
                Section("Location") {
                    Map(coordinateRegion: $region, annotationItems: [ContactAnnotation(contact: contact)]) { annotation in
                        MapMarker(
                            coordinate: annotation.coordinate,
                            tint: .blue
                        )
                    }
                    .frame(height: 200)
                    .listRowInsets(EdgeInsets())
                }
            }

            Section("Public Key") {
                Text(contact.publicKey.hexString)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(contact.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ContactAnnotation: Identifiable {
    let id = UUID()
    let contact: Contact

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: contact.latitude ?? 0,
            longitude: contact.longitude ?? 0
        )
    }
}

