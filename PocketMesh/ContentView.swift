import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)

                Text("PocketMesh")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Off-grid mesh messaging")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("PocketMesh")
        }
    }
}

#Preview {
    ContentView()
}
