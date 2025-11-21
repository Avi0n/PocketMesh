import PocketMeshKit
import SwiftUI

struct TelemetryDetailView: View {
    let contact: Contact
    @ObservedObject var telemetryService: TelemetryService

    @State private var telemetry: TelemetryData?
    @State private var status: StatusData?
    @State private var neighbours: [NeighbourEntry] = []
    @State private var mmaData: MMAData?
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("Actions") {
                Button("Request Telemetry") {
                    Task { await requestTelemetry() }
                }
                .disabled(isLoading)

                if contact.type == .repeater || contact.type == .room {
                    Button("Request Status") {
                        Task { await requestStatus() }
                    }
                    .disabled(isLoading)

                    Button("Request Neighbours") {
                        Task { await requestNeighbours() }
                    }
                    .disabled(isLoading)
                }

                Button("Request MMA (Last Hour)") {
                    Task { await requestMMA(minutes: 60) }
                }
                .disabled(isLoading)
            }

            // Display sections for received data
            if let telemetry {
                Section("Latest Telemetry") {
                    if let temp = telemetry.temperature {
                        LabeledContent("Temperature", value: String(format: "%.1f°C", temp))
                    }
                    if let humidity = telemetry.humidity {
                        LabeledContent("Humidity", value: String(format: "%.1f%%", humidity))
                    }
                    if let pressure = telemetry.pressure {
                        LabeledContent("Pressure", value: String(format: "%.1f hPa", pressure))
                    }
                    if let battery = telemetry.batteryVoltage {
                        LabeledContent("Battery", value: String(format: "%.2fV", battery))
                    }

                    LabeledContent("Received", value: {
                        let formatter = DateFormatter()
                        formatter.dateStyle = .short
                        formatter.timeStyle = .short
                        return formatter.string(from: telemetry.timestamp)
                    }())
                }
            }

            if let status {
                Section("Device Status") {
                    LabeledContent("Uptime", value: formatUptime(status.uptime))
                    LabeledContent("Battery", value: "\(status.batteryPercent)%")
                    LabeledContent("Free Memory", value: "\(status.freeMemory) KB")
                    LabeledContent("Radio Config", value: status.radioConfig)
                }
            }

            if !neighbours.isEmpty {
                Section("Neighbours (\(neighbours.count))") {
                    ForEach(neighbours) { neighbour in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(neighbour.publicKeyPrefix.hexString)
                                .font(.system(.caption, design: .monospaced))

                            HStack {
                                Label(
                                    String(format: "%.1f dB", neighbour.snr),
                                    systemImage: "antenna.radiowaves.left.and.right",
                                )
                                .font(.caption2)
                                Spacer()
                                Text(neighbour.lastSeen, format: .relative(presentation: .named))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if let mma = mmaData {
                Section("Historical Data (Last Hour)") {
                    LabeledContent("Samples", value: "\(mma.sampleCount)")
                    LabeledContent("Time Range", value: {
                        let formatter = DateFormatter()
                        formatter.dateStyle = .short
                        formatter.timeStyle = .short
                        return "\(formatter.string(from: mma.fromTime)) - \(formatter.string(from: mma.toTime))"
                    }())

                    if let minTemp = mma.minTemperature,
                       let maxTemp = mma.maxTemperature,
                       let avgTemp = mma.avgTemperature
                    {
                        GroupBox("Temperature") {
                            LabeledContent("Min", value: String(format: "%.1f°C", minTemp))
                            LabeledContent("Max", value: String(format: "%.1f°C", maxTemp))
                            LabeledContent("Avg", value: String(format: "%.1f°C", avgTemp))
                        }
                    }

                    if let minHumidity = mma.minHumidity,
                       let maxHumidity = mma.maxHumidity,
                       let avgHumidity = mma.avgHumidity
                    {
                        GroupBox("Humidity") {
                            LabeledContent("Min", value: String(format: "%.1f%%", minHumidity))
                            LabeledContent("Max", value: String(format: "%.1f%%", maxHumidity))
                            LabeledContent("Avg", value: String(format: "%.1f%%", avgHumidity))
                        }
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Telemetry: \(contact.name)")
        .overlay {
            if isLoading {
                ProgressView()
            }
        }
    }

    // MARK: - Async request methods with proper error handling

    @MainActor
    private func requestTelemetry() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            telemetry = try await telemetryService.requestTelemetry(for: contact)
        } catch {
            errorMessage = "Telemetry request failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func requestStatus() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            status = try await telemetryService.requestStatus(for: contact)
        } catch {
            errorMessage = "Status request failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func requestNeighbours() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            neighbours = try await telemetryService.requestNeighbours(for: contact)
        } catch {
            errorMessage = "Neighbours request failed: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func requestMMA(minutes: Int) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            mmaData = try await telemetryService.requestMMA(for: contact, last: minutes)
        } catch {
            errorMessage = "Historical data request failed: \(error.localizedDescription)"
        }
    }

    private func formatUptime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        return "\(hours)h \(minutes)m"
    }
}
