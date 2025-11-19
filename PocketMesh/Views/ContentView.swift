import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("PocketMesh")
                .font(.largeTitle)
                .padding()
            Text("Off-grid messaging over MeshCore BLE")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
