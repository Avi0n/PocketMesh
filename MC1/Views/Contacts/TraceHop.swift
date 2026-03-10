import SwiftUI

/// Represents a single hop in a trace result
struct TraceHop: Identifiable {
    let id = UUID()
    let hashBytes: Data?          // nil for start/end node (local device)
    let resolvedName: String?     // From contacts lookup
    let snr: Double
    let isStartNode: Bool
    let isEndNode: Bool
    let latitude: Double?
    let longitude: Double?

    /// Display string for hash (shows all bytes)
    var hashDisplayString: String? {
        hashBytes?.map { $0.hexString }.joined()
    }

    /// Whether this hop has a valid (non-zero) location.
    /// Uses OR logic to match ContactDTO.hasLocation - if either coordinate is non-zero,
    /// we have some location data. (0,0) is "Null Island" and extremely unlikely.
    var hasLocation: Bool {
        guard let lat = latitude, let lon = longitude else { return false }
        return lat != 0 || lon != 0
    }

    /// Map SNR to 0-1 range for cellularbars variableValue
    var signalLevel: Double {
        Self.signalLevel(for: snr)
    }

    var signalColor: Color {
        Self.signalColor(for: snr)
    }

    /// Shared signal level calculation for any SNR value
    static func signalLevel(for snr: Double) -> Double {
        if snr >= 5 { return 1.0 }
        if snr >= -5 { return 0.66 }
        return 0.33
    }

    /// Shared signal color calculation for any SNR value
    static func signalColor(for snr: Double) -> Color {
        if snr >= 5 { return .green }
        if snr >= -5 { return .yellow }
        return .red
    }
}
