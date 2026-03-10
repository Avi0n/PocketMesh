import SwiftUI
import PocketMeshServices

struct PresetDetailsView: View {
    let selectedPresetID: String?
    let presets: [RadioPreset]
    let device: DeviceDTO?

    var body: some View {
        if let preset = presets.first(where: { $0.id == selectedPresetID }) {
            RadioParameterText(
                frequencyMHz: preset.frequencyMHz,
                bandwidthKHz: preset.bandwidthKHz,
                spreadingFactor: preset.spreadingFactor,
                codingRate: preset.codingRate
            )
            .foregroundStyle(.secondary)
        } else if let device {
            RadioParameterText(
                frequencyMHz: Double(device.frequency) / 1000.0,
                bandwidthKHz: Double(device.bandwidth) / 1000.0,
                spreadingFactor: device.spreadingFactor,
                codingRate: device.codingRate
            )
            .foregroundStyle(.secondary)
        }
    }
}
