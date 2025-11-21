import Charts
import PocketMeshKit
import SwiftUI

struct TelemetryChartView: View {
    let mmaData: MMAData

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sensor Data Summary")
                .font(.headline)

            // Temperature Chart
            if let minTemp = mmaData.minTemperature,
               let maxTemp = mmaData.maxTemperature,
               let avgTemp = mmaData.avgTemperature
            {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Temperature Range")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack {
                        VStack {
                            Text("Min")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f°C", minTemp))
                                .font(.caption)
                                .fontWeight(.medium)
                        }

                        Spacer()

                        VStack {
                            Text("Average")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f°C", avgTemp))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.blue)
                        }

                        Spacer()

                        VStack {
                            Text("Max")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f°C", maxTemp))
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            }

            // Humidity Chart
            if let minHumidity = mmaData.minHumidity,
               let maxHumidity = mmaData.maxHumidity,
               let avgHumidity = mmaData.avgHumidity
            {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Humidity Range")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    HStack {
                        VStack {
                            Text("Min")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f%%", minHumidity))
                                .font(.caption)
                                .fontWeight(.medium)
                        }

                        Spacer()

                        VStack {
                            Text("Average")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f%%", avgHumidity))
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.blue)
                        }

                        Spacer()

                        VStack {
                            Text("Max")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(String(format: "%.1f%%", maxHumidity))
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            }

            // Sample count and time range
            HStack {
                VStack {
                    Text("Samples")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(mmaData.sampleCount)")
                        .font(.caption)
                        .fontWeight(.medium)
                }

                Spacer()

                VStack {
                    Text("Duration")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(formatDuration(mmaData.fromTime, mmaData.toTime))
                        .font(.caption)
                        .fontWeight(.medium)
                }
            }
            .padding()
            .background(Color(.systemGray5))
            .cornerRadius(8)
        }
        .padding()
    }

    private func formatDuration(_ from: Date, _ toDate: Date) -> String {
        let duration = toDate.timeIntervalSince(from)
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

// Note: Preview disabled due to internal MMAData initializer
// #Preview {
//     TelemetryChartView(mmaData: /* mockMMAData */)
//         .padding()
// }
