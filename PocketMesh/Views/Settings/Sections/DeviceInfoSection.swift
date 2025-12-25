import SwiftUI
import PocketMeshServices

/// Read-only device information header
struct DeviceInfoSection: View {
    let device: DeviceDTO

    var body: some View {
        Section {
            NavigationLink {
                DeviceInfoView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "cpu.fill")
                        .font(.title2)
                        .foregroundStyle(.tint)
                        .frame(width: 40, height: 40)
                        .background(.tint.opacity(0.1), in: .circle)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(device.nodeName)
                            .font(.headline)

                        HStack(spacing: 4) {
                            Circle()
                                .fill(.green)
                                .frame(width: 6, height: 6)
                            Text("Connected")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            if !device.manufacturerName.isEmpty {
                                Text("\u{2022}")
                                    .foregroundStyle(.tertiary)

                                Text(device.manufacturerName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
        } header: {
            Text("Device")
        }
    }
}
