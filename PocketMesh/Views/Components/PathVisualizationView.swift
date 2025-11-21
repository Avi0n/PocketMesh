import SwiftUI

// Placeholder type for path visualization
struct TraceHop: Identifiable {
    let id = UUID()
    let nodeHash: String
    let snr: Double
    let rssi: Int
}

struct PathVisualizationView: View {
    let hops: [TraceHop]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(hops.enumerated()), id: \.element.id) { index, hop in
                    VStack(spacing: 4) {
                        // Node indicator
                        Circle()
                            .fill(snrColor(hop.snr))
                            .frame(width: 40, height: 40)
                            .overlay {
                                Text(hop.nodeHash)
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                            }

                        // SNR value
                        Text("\(hop.snr, specifier: "%.1f") dB")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        // RSSI value
                        Text("\(hop.rssi) dBm")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    if index < hops.count - 1 {
                        Image(systemName: "arrow.right")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding()
        }
    }

    private func snrColor(_ snr: Double) -> Color {
        switch snr {
        case 10...: .green
        case 0 ..< 10: .yellow
        default: .red
        }
    }
}
