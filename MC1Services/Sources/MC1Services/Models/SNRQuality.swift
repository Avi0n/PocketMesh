/// Signal quality classification based on LoRa SNR (Signal-to-Noise Ratio) in dB.
///
/// Standard 5-tier scale for individual packet reception quality.
/// Note: Trace path views (PathLineOverlay, TraceHop) intentionally use a different
/// 3-tier scale with wider thresholds (±5 dB) since path segments span longer distances.
public enum SNRQuality: Sendable, Equatable {
    case excellent  // SNR > 10 dB
    case good       // SNR > 5 dB
    case fair       // SNR > 0 dB
    case poor       // SNR > -10 dB
    case veryPoor   // SNR <= -10 dB
    case unknown    // nil SNR

    public init(snr: Double?) {
        guard let snr else {
            self = .unknown
            return
        }
        if snr > 10 { self = .excellent }
        else if snr > 5 { self = .good }
        else if snr > 0 { self = .fair }
        else if snr > -10 { self = .poor }
        else { self = .veryPoor }
    }

    /// Bar level for SF Symbol `cellularbars` variableValue (0–1).
    public var barLevel: Double {
        switch self {
        case .excellent: 1.0
        case .good: 0.75
        case .fair: 0.5
        case .poor: 0.25
        case .veryPoor: 0.1
        case .unknown: 0
        }
    }

    /// Human-readable quality label for accessibility.
    public var qualityLabel: String {
        switch self {
        case .excellent: "Excellent"
        case .good: "Good"
        case .fair: "Fair"
        case .poor: "Weak"
        case .veryPoor: "Marginal"
        case .unknown: "Unknown"
        }
    }
}
