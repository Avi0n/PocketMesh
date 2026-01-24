import SwiftUI

/// Shown when no device is connected
struct NoDeviceSection: View {
    @Binding var showingDeviceSelection: Bool

    var body: some View {
        Section {
            Button {
                showingDeviceSelection = true
            } label: {
                Label(L10n.Settings.Device.connect, systemImage: "antenna.radiowaves.left.and.right")
            }
        } header: {
            Text(L10n.Settings.Device.header)
        } footer: {
            Text(L10n.Settings.Device.noDeviceConnected)
        }
    }
}
