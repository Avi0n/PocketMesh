import SwiftUI

/// Shown when no device is connected
struct NoDeviceSection: View {
    @Binding var showingDeviceSelection: Bool

    var body: some View {
        Section {
            Button {
                showingDeviceSelection = true
            } label: {
                Label("Connect Device", systemImage: "antenna.radiowaves.left.and.right")
            }
        } header: {
            Text("Device")
        } footer: {
            Text("No MeshCore device connected")
        }
    }
}
