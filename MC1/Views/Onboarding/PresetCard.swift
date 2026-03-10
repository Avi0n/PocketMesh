import SwiftUI
import PocketMeshServices

struct PresetCard: View {
    let preset: RadioPreset?
    let frequency: Double
    let region: RadioRegion?
    let isSelected: Bool
    let isDisabled: Bool

    var body: some View {
        VStack(spacing: 8) {
            // Region badge
            HStack {
                Spacer()
                if let region {
                    Text(region.shortCode)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: .capsule)
                }
            }

            Spacer()

            // Preset name
            Text(preset?.name ?? L10n.Onboarding.RadioPreset.custom)
                .font(.headline)
                .lineLimit(1)

            // Frequency
            Text(frequency.formatted(.number.precision(.fractionLength(3)).locale(.posix)))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            + Text(" MHz")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(width: 150, height: 100)
        .padding(12)
        .liquidGlass(in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 2.5)
        }
        .opacity(isDisabled ? 0.5 : 1.0)
    }
}
