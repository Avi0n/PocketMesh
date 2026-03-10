import SwiftUI

/// Sub-page wrapping RadioPresetSection for the settings navigation
struct RadioSettingsView: View {
    var body: some View {
        List {
            RadioPresetSection()
        }
        .navigationTitle(L10n.Settings.Radio.header)
        .navigationBarTitleDisplayMode(.inline)
    }
}
