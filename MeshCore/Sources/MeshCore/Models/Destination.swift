import Foundation
import CryptoKit

public enum Destination: Sendable {
    case data(Data)
    case hexString(String)
    case contact(MeshContact)

    public func publicKey(prefixLength: Int = 6) throws -> Data {
        switch self {
        case .data(let data):
            guard data.count >= prefixLength else {
                throw DestinationError.insufficientLength(expected: prefixLength, actual: data.count)
            }
            return Data(data.prefix(prefixLength))

        case .hexString(let hex):
            guard let data = Data(hexString: hex) else {
                throw DestinationError.invalidHexString(hex)
            }
            guard data.count >= prefixLength else {
                throw DestinationError.insufficientLength(expected: prefixLength, actual: data.count)
            }
            return Data(data.prefix(prefixLength))

        case .contact(let contact):
            guard contact.publicKey.count >= prefixLength else {
                throw DestinationError.insufficientLength(expected: prefixLength, actual: contact.publicKey.count)
            }
            return Data(contact.publicKey.prefix(prefixLength))
        }
    }

    public func fullPublicKey() throws -> Data {
        try publicKey(prefixLength: 32)
    }
}

public enum DestinationError: Error, Sendable {
    case invalidHexString(String)
    case insufficientLength(expected: Int, actual: Int)
}

public enum FloodScope: Sendable {
    case disabled
    case channelName(String)
    case rawKey(Data)

    public func scopeKey() -> Data {
        switch self {
        case .disabled:
            return Data(repeating: 0, count: 16)

        case .channelName(let name):
            let hash = SHA256.hash(data: Data(name.utf8))
            return Data(hash.prefix(16))

        case .rawKey(let key):
            var padded = key.prefix(16)
            while padded.count < 16 {
                padded.append(0)
            }
            return Data(padded)
        }
    }
}

public enum ChannelSecret: Sendable {
    case explicit(Data)
    case deriveFromName

    public func secretData(channelName: String) -> Data {
        switch self {
        case .explicit(let data):
            var padded = data.prefix(16)
            while padded.count < 16 {
                padded.append(0)
            }
            return Data(padded)

        case .deriveFromName:
            let hash = SHA256.hash(data: Data(channelName.utf8))
            return Data(hash.prefix(16))
        }
    }
}
