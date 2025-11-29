import PocketMeshKit
import SwiftUI

struct AdvancedMessagingSettingsView: View {
    @ObservedObject var messageService: MessageService

    var body: some View {
        Form {
            Section("Message Retry Strategy") {
                Stepper(
                    "Max Attempts: \(messageService.maxAttempts)",
                    value: $messageService.maxAttempts,
                    in: 1 ... 5,
                )

                Stepper(
                    "Flood After: \(messageService.floodAfter)",
                    value: $messageService.floodAfter,
                    in: 1 ... messageService.maxAttempts,
                )

                Stepper(
                    "Max Flood Attempts: \(messageService.maxFloodAttempts)",
                    value: $messageService.maxFloodAttempts,
                    in: 0 ... 3,
                )
            }

            Section("Reliability") {
                Toggle("Multi-ACK Mode", isOn: $messageService.multiAckEnabled)
            }

            Section {
                Text("Direct attempts: Normal routing via established paths")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("Flood mode: Broadcast to all repeaters (slower, more reliable)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Message Delivery")
    }
}
