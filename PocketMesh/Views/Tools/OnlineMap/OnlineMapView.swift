import Network
import SwiftUI

struct OnlineMapView: View {
    private static let mapURL = URL(string: "https://meshcore.co.uk/map.html")!

    @State private var isLoading = true
    @State private var isOnline = true
    @State private var networkMonitor: NWPathMonitor?

    var body: some View {
        Group {
            if isOnline {
                ZStack {
                    OnlineMapWebView(url: Self.mapURL, isLoading: $isLoading)

                    if isLoading {
                        ProgressView()
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Internet Connection",
                    systemImage: "wifi.slash",
                    description: Text("The online map requires an internet connection.")
                )
            }
        }
        .onAppear {
            startNetworkMonitoring()
        }
        .onDisappear {
            stopNetworkMonitoring()
        }
    }

    private func startNetworkMonitoring() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { path in
            Task { @MainActor in
                isOnline = path.status == .satisfied
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .background))
        networkMonitor = monitor
    }

    private func stopNetworkMonitoring() {
        networkMonitor?.cancel()
        networkMonitor = nil
    }
}

#Preview {
    NavigationStack {
        OnlineMapView()
            .navigationTitle("Online Map")
    }
}
