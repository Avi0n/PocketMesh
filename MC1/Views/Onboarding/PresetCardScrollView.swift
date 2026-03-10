import SwiftUI
import PocketMeshServices

struct PresetCardScrollView: View {
    @Binding var selectedPresetID: String?
    let appliedPresetID: String?
    let currentPreset: RadioPreset?
    let presets: [RadioPreset]
    let device: DeviceDTO?
    let isDisabled: Bool

    var body: some View {
        ScrollView(.horizontal) {
            LiquidGlassContainer(spacing: 16) {
                LazyHStack(spacing: 12) {
                // Custom card (when device has non-preset settings)
                if currentPreset == nil, let device {
                    let freqMHz = Double(device.frequency) / 1000.0
                    Button {
                        selectedPresetID = nil
                    } label: {
                        PresetCard(
                            preset: nil,
                            frequency: freqMHz,
                            region: nil,
                            isSelected: selectedPresetID == nil,
                            isDisabled: isDisabled
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Preset cards
                ForEach(presets) { preset in
                    Button {
                        selectedPresetID = preset.id
                    } label: {
                        PresetCard(
                            preset: preset,
                            frequency: preset.frequencyMHz,
                            region: preset.region,
                            isSelected: selectedPresetID == preset.id,
                            isDisabled: isDisabled
                        )
                    }
                    .buttonStyle(.plain)
                }
                }
                .padding(.horizontal)
            }
        }
        .scrollIndicators(.hidden)
        .disabled(isDisabled)
    }
}
