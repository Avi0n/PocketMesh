import Testing
import Foundation
@testable import PocketMeshServices
@testable import MeshCore

@Suite("ChannelService Tests")
struct ChannelServiceTests {

    // MARK: - Secret Hashing Tests

    @Test("hashSecret produces 16-byte output")
    func hashSecretProduces16Bytes() {
        let secret = ChannelService.hashSecret("test passphrase")
        #expect(secret.count == ProtocolLimits.channelSecretSize)
    }

    @Test("hashSecret is deterministic")
    func hashSecretIsDeterministic() {
        let secret1 = ChannelService.hashSecret("same passphrase")
        let secret2 = ChannelService.hashSecret("same passphrase")
        #expect(secret1 == secret2)
    }

    @Test("hashSecret differs for different inputs")
    func hashSecretDiffersForDifferentInputs() {
        let secret1 = ChannelService.hashSecret("passphrase one")
        let secret2 = ChannelService.hashSecret("passphrase two")
        #expect(secret1 != secret2)
    }

    @Test("hashSecret handles empty string")
    func hashSecretHandlesEmptyString() {
        let secret = ChannelService.hashSecret("")
        #expect(secret.count == ProtocolLimits.channelSecretSize)
        #expect(secret == Data(repeating: 0, count: ProtocolLimits.channelSecretSize))
    }

    @Test("hashSecret handles unicode")
    func hashSecretHandlesUnicode() {
        let secret = ChannelService.hashSecret("🔐 secure 密码")
        #expect(secret.count == ProtocolLimits.channelSecretSize)
    }

    @Test("validateSecret accepts 16-byte secrets")
    func validateSecretAccepts16Bytes() {
        let validSecret = Data(repeating: 0xAB, count: ProtocolLimits.channelSecretSize)
        #expect(ChannelService.validateSecret(validSecret))
    }

    @Test("validateSecret rejects wrong-sized secrets")
    func validateSecretRejectsWrongSize() {
        let tooShort = Data(repeating: 0xAB, count: 15)
        let tooLong = Data(repeating: 0xAB, count: 17)
        #expect(!ChannelService.validateSecret(tooShort))
        #expect(!ChannelService.validateSecret(tooLong))
    }
}
