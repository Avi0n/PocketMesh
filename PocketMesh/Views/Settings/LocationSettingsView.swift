import SwiftUI

/// Sub-page wrapping LocationSettingsSection for the settings navigation
struct LocationSettingsView: View {
    @Environment(\.appState) private var appState
    @State private var showingLocationPicker = false

    var body: some View {
        List {
            LocationSettingsSection(showingLocationPicker: $showingLocationPicker)
        }
        .navigationTitle(L10n.Settings.Location.header)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingLocationPicker) {
            LocationPickerView.forLocalDevice(appState: appState)
        }
    }
}
