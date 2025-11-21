import Foundation

public struct ACLEntry: Identifiable, Sendable {
    public let id = UUID()
    public let publicKeyPrefix: Data // 6-byte prefix
    public let permissions: UInt8

    public init(publicKeyPrefix: Data, permissions: UInt8) {
        self.publicKeyPrefix = publicKeyPrefix
        self.permissions = permissions
    }

    // Permission flags
    public var canRead: Bool { permissions & 0x01 != 0 }
    public var canWrite: Bool { permissions & 0x02 != 0 }
    public var canExecute: Bool { permissions & 0x04 != 0 }

    static func decodeList(from data: Data) throws -> [ACLEntry] {
        var entries: [ACLEntry] = []
        var offset = 0

        while offset + 7 <= data.count {
            let keyPrefix = data.subdata(in: offset ..< offset + 6)
            let perm = data[offset + 6]

            entries.append(ACLEntry(publicKeyPrefix: keyPrefix, permissions: perm))
            offset += 7
        }

        return entries
    }
}
