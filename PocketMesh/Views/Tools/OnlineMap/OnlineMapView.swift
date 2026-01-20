import Network
import SwiftUI

struct OnlineMapView: View {
    private static let mapURL = URL(string: "https://meshcore.co.uk/map.html")!

    @State private var isLoading = true
    @State private var isOnline = true
    @State private var loadError: Error?
    @State private var networkMonitor: NWPathMonitor?

    var body: some View {
        Group {
            if isOnline {
                if let error = loadError {
                    ContentUnavailableView {
                        Label("Failed to Load Map", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error.localizedDescription)
                    } actions: {
                        Button("Try Again") {
                            loadError = nil
                            isLoading = true
                        }
                    }
                } else {
                    ZStack {
                        OnlineMapWebView(url: Self.mapURL, isLoading: $isLoading, loadError: $loadError)

                        if isLoading {
                            ProgressView()
                        }
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
        isOnline = monitor.currentPath.status == .satisfied
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
