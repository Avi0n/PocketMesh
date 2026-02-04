import CoreLocation
import OSLog
import PocketMeshServices
import SwiftUI

@Observable
@MainActor
final class MessagePathViewModel {
    var contacts: [ContactDTO] = []
    var repeaters: [ContactDTO] = []
    var isLoading = true

    private let logger = Logger(subsystem: "com.pocketmesh", category: "MessagePathViewModel")

    func loadContacts(services: ServiceContainer?, deviceID: UUID) async {
        isLoading = true
        guard let services else {
            isLoading = false
            return
        }

        do {
            let fetched = try await services.dataStore.fetchContacts(deviceID: deviceID)
            contacts = fetched
            repeaters = fetched.filter { $0.type == .repeater }
        } catch {
            logger.error("Failed to load contacts: \(error.localizedDescription)")
            contacts = []
            repeaters = []
        }

        isLoading = false
    }

    func senderName(for message: MessageDTO) -> String {
        if message.isChannelMessage, let nodeName = message.senderNodeName {
            return nodeName
        }

        if let keyPrefix = message.senderKeyPrefix,
           let match = contacts.first(where: { $0.publicKeyPrefix == keyPrefix }) {
            return match.displayName
        }

        return L10n.Chats.Chats.Path.Hop.unknown
    }

    func senderNodeID(for message: MessageDTO) -> String? {
        guard let keyPrefix = message.senderKeyPrefix,
              let firstByte = keyPrefix.first else { return nil }
        return String(format: "%02X", firstByte)
    }

    func repeaterName(for hopByte: UInt8, userLocation: CLLocation?) -> String {
        if let match = RepeaterResolver.bestMatch(for: hopByte, in: repeaters, userLocation: userLocation) {
            return match.displayName
        }
        return L10n.Chats.Chats.Path.Hop.unknown
    }
}
