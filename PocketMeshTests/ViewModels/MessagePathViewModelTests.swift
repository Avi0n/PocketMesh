import Foundation
import Testing
@testable import PocketMesh
@testable import PocketMeshServices

@Suite("MessagePathViewModel")
@MainActor
struct MessagePathViewModelTests {

    private func createContact(prefix: [UInt8], name: String, type: ContactType = .chat) -> ContactDTO {
        ContactDTO(
            id: UUID(),
            deviceID: UUID(),
            publicKey: Data(prefix + Array(repeating: UInt8(0), count: 32 - prefix.count)),
            name: name,
            typeRawValue: type.rawValue,
            flags: 0,
            outPathLength: 0,
            outPath: Data(),
            lastAdvertTimestamp: 0,
            latitude: 0,
            longitude: 0,
            lastModified: 0,
            nickname: nil,
            isBlocked: false,
            isMuted: false,
            isFavorite: false,
            lastMessageDate: nil,
            unreadCount: 0
        )
    }

    private func createMessage(senderKeyPrefix: Data?) -> MessageDTO {
        MessageDTO(
            id: UUID(),
            deviceID: UUID(),
            contactID: UUID(),
            channelIndex: nil,
            text: "Test",
            timestamp: 0,
            createdAt: Date(),
            direction: .incoming,
            status: .delivered,
            textType: .plain,
            ackCode: nil,
            pathLength: 0,
            snr: nil,
            senderKeyPrefix: senderKeyPrefix,
            senderNodeName: nil,
            isRead: true,
            replyToID: nil,
            roundTripTime: nil,
            heardRepeats: 0,
            retryAttempt: 0,
            maxRetryAttempts: 0
        )
    }

    @Test("sender name uses full key prefix match")
    func senderNameUsesFullPrefix() {
        let viewModel = MessagePathViewModel()

        let contactA = createContact(prefix: [0xAA, 0x00, 0x00, 0x00, 0x00, 0x00], name: "Alpha")
        let contactB = createContact(prefix: [0xAA, 0x01, 0x00, 0x00, 0x00, 0x00], name: "Bravo")

        viewModel.contacts = [contactA, contactB]

        let message = createMessage(senderKeyPrefix: contactB.publicKeyPrefix)

        #expect(viewModel.senderName(for: message) == "Bravo")
    }
}
