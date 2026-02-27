import SwiftUI

struct GeocodingSettingsSection: View {
    @AppStorage("geocodingEnabled") private var geocodingEnabled = true

    var body: some View {
        Section {
            Toggle(isOn: $geocodingEnabled) {
                TintedLabel(L10n.Settings.Geocoding.nodeLocationLookup, systemImage: "map")
            }
        } header: {
            Text(L10n.Settings.Geocoding.header)
        } footer: {
            Text(L10n.Settings.Geocoding.footer)
        }
    }
}
