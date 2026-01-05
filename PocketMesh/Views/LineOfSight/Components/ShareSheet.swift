import MapKit
import SwiftUI

/// A SwiftUI wrapper for UIActivityViewController
struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Extension to make MKMapItem work with sheet(item:)
extension MKMapItem: @retroactive Identifiable {
    public var id: String {
        "\(placemark.coordinate.latitude),\(placemark.coordinate.longitude)"
    }
}
