import Foundation
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh.app", category: "Contacts")

public extension MeshCoreProtocol {
    /// CMD_SEND_SELF_ADVERT (7): Transmit advertisement
    func sendSelfAdvertisement(floodMode: Bool) async throws {
        var payload = Data()
        payload.append(floodMode ? 1 : 0)

        let frame = ProtocolFrame(code: CommandCode.sendSelfAdvert.rawValue, payload: payload)
        _ = try await sendCommand(frame, expectingResponse: ResponseCode.ok.rawValue)
    }

    /// CMD_SET_ADVERT_NAME (8): Update node name
    func setAdvertisementName(_ name: String) async throws {
        guard let nameData = name.data(using: .utf8), nameData.count <= 32 else {
            throw ProtocolError.invalidPayload
        }

        let frame = ProtocolFrame(code: CommandCode.setAdvertName.rawValue, payload: nameData)
        _ = try await sendCommand(frame, expectingResponse: ResponseCode.ok.rawValue)
    }

    /// CMD_SET_ADVERT_LATLON (14): Set location
    func setAdvertisementLocation(latitude: Double, longitude: Double, altitude: Int16?) async throws {
        var payload = Data()

        // Latitude and longitude multiplied by 1E6, as int32 little-endian
        let latInt = Int32(latitude * 1_000_000)
        let lonInt = Int32(longitude * 1_000_000)

        withUnsafeBytes(of: latInt.littleEndian) { payload.append(contentsOf: $0) }
        withUnsafeBytes(of: lonInt.littleEndian) { payload.append(contentsOf: $0) }

        // Altitude (optional, int16)
        if let altitude {
            withUnsafeBytes(of: altitude.littleEndian) { payload.append(contentsOf: $0) }
        }

        let frame = ProtocolFrame(code: CommandCode.setAdvertLatLon.rawValue, payload: payload)
        _ = try await sendCommand(frame, expectingResponse: ResponseCode.ok.rawValue)
    }

    /// CMD_GET_CONTACTS (4): Sync contacts with optional timestamp watermark
    func getContacts(since: Date?) async throws -> [ContactData] {
        var payload = Data()

        if let since {
            let timestamp = UInt32(since.timeIntervalSince1970)
            withUnsafeBytes(of: timestamp.littleEndian) { payload.append(contentsOf: $0) }
        }

        let frame = ProtocolFrame(code: CommandCode.getContacts.rawValue, payload: payload)

        // Contact sync is multi-frame: CONTACTS_START → CONTACT (multiple) → END_OF_CONTACTS
        var contacts: [ContactData] = []

        // Send command and wait for CONTACTS_START
        try await send(frame: frame.encode())

        // Wait for CONTACTS_START response
        let startResponse = try await waitForResponse(code: ResponseCode.contactsStart.rawValue, timeout: 5.0)

        logger.debug("Contact sync started")

        // Read CONTACT frames until END_OF_CONTACTS
        var syncComplete = false
        while !syncComplete {
            // Wait for next frame (either CONTACT or END_OF_CONTACTS)
            let response = try await waitForMultiFrameResponse(
                codes: [ResponseCode.contact.rawValue, ResponseCode.endOfContacts.rawValue],
                timeout: 5.0,
            )

            switch response.code {
            case ResponseCode.contact.rawValue:
                let contact = try ContactData.decode(from: response.payload)
                contacts.append(contact)
                logger.debug("Received contact: \(contact.name)")

            case ResponseCode.endOfContacts.rawValue:
                syncComplete = true
                logger.info("Contact sync complete: \(contacts.count) contacts")

            default:
                throw ProtocolError.unsupportedCommand
            }
        }

        return contacts
    }

    /// CMD_ADD_UPDATE_CONTACT (9): Manually add or update contact
    func addOrUpdateContact(_ contact: ContactData) async throws {
        let payload = contact.encode()
        let frame = ProtocolFrame(code: CommandCode.addUpdateContact.rawValue, payload: payload)
        _ = try await sendCommand(frame, expectingResponse: ResponseCode.ok.rawValue)
    }

    /// CMD_REMOVE_CONTACT (15): Delete contact by public key
    func removeContact(publicKey: Data) async throws {
        guard publicKey.count == 32 else {
            throw ProtocolError.invalidPayload
        }

        let frame = ProtocolFrame(code: CommandCode.removeContact.rawValue, payload: publicKey)
        _ = try await sendCommand(frame, expectingResponse: ResponseCode.ok.rawValue)
    }

    // Helper function to send a frame (exposed for multi-frame operations)
    func send(frame: Data) async throws {
        try await bleManager.send(frame: frame)
    }
}

// MARK: - Contact Data

public struct ContactData: Sendable {
    let publicKey: Data // 32 bytes
    let name: String // 32 chars max
    let type: ContactType
    let flags: UInt8
    let outPathLength: UInt8
    let outPath: Data? // Up to 64 bytes
    let lastAdvertisement: Date
    let latitude: Double?
    let longitude: Double?
    let lastModified: Date

    public init(
        publicKey: Data,
        name: String,
        type: ContactType,
        flags: UInt8,
        outPathLength: UInt8,
        outPath: Data?,
        lastAdvertisement: Date,
        latitude: Double?,
        longitude: Double?,
        lastModified: Date,
    ) {
        self.publicKey = publicKey
        self.name = name
        self.type = type
        self.flags = flags
        self.outPathLength = outPathLength
        self.outPath = outPath
        self.lastAdvertisement = lastAdvertisement
        self.latitude = latitude
        self.longitude = longitude
        self.lastModified = lastModified
    }

    static func decode(from data: Data) throws -> ContactData {
        guard data.count >= 32 + 1 + 1 + 1 + 64 + 32 + 4 + 4 + 4 + 4 else {
            throw ProtocolError.invalidPayload
        }

        var offset = 0

        // Public key (32 bytes)
        let publicKey = data.subdata(in: offset ..< offset + 32)
        offset += 32

        // Type (1 byte)
        let typeRaw = data[offset]
        let type: ContactType = switch typeRaw {
        case 1: .companion // Changed from .chat
        case 2: .repeater
        case 3: .room
        case 4: .sensor // NEW
        default: .none
        }
        offset += 1

        // Flags (1 byte)
        let flags = data[offset]
        offset += 1

        // Out path length (1 byte)
        let outPathLength = data[offset]
        offset += 1

        // Out path (64 bytes)
        let outPath = outPathLength > 0 ? data.subdata(in: offset ..< offset + Int(outPathLength)) : nil
        offset += 64

        // Name (32 chars, null-terminated)
        let nameData = data.subdata(in: offset ..< offset + 32)
        let name = String(data: nameData, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\0")) ?? "Unknown"
        offset += 32

        // Last advertisement (uint32)
        let lastAdvert = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
        let lastAdvertisement = Date(timeIntervalSince1970: TimeInterval(lastAdvert))
        offset += 4

        // Latitude (int32 * 1E6)
        let latRaw = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Int32.self) }
        let latitude: Double? = latRaw != 0 ? Double(latRaw) / 1_000_000.0 : nil
        offset += 4

        // Longitude (int32 * 1E6)
        let lonRaw = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: Int32.self) }
        let longitude: Double? = lonRaw != 0 ? Double(lonRaw) / 1_000_000.0 : nil
        offset += 4

        // Last modified (uint32)
        let lastMod = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
        let lastModified = Date(timeIntervalSince1970: TimeInterval(lastMod))

        return ContactData(
            publicKey: publicKey,
            name: name,
            type: type,
            flags: flags,
            outPathLength: outPathLength,
            outPath: outPath,
            lastAdvertisement: lastAdvertisement,
            latitude: latitude,
            longitude: longitude,
            lastModified: lastModified,
        )
    }

    public func encode() -> Data {
        var data = Data()

        // Public key (32 bytes)
        data.append(publicKey)

        // Type (1 byte)
        let typeValue: UInt8 = switch type {
        case .none: 0
        case .companion: 1 // Changed from .chat
        case .repeater: 2
        case .room: 3
        case .sensor: 4 // NEW
        }
        data.append(typeValue)

        // Flags (1 byte)
        data.append(flags)

        // Out path length (1 byte)
        data.append(outPathLength)

        // Out path (64 bytes, padded with zeros if shorter)
        var pathData = Data(count: 64)
        if let outPath {
            let copyLength = min(outPath.count, 64)
            pathData.replaceSubrange(0 ..< copyLength, with: outPath.prefix(copyLength))
        }
        data.append(pathData)

        // Name (32 chars, null-terminated)
        var nameData = Data(count: 32)
        if let nameBytes = name.data(using: .utf8) {
            let copyLength = min(nameBytes.count, 31) // Leave room for null terminator
            nameData.replaceSubrange(0 ..< copyLength, with: nameBytes.prefix(copyLength))
        }
        data.append(nameData)

        // Last advertisement (uint32 little-endian)
        let lastAdvert = UInt32(lastAdvertisement.timeIntervalSince1970)
        withUnsafeBytes(of: lastAdvert.littleEndian) { data.append(contentsOf: $0) }

        // Latitude (int32 * 1E6 little-endian)
        let latInt = Int32((latitude ?? 0) * 1_000_000)
        withUnsafeBytes(of: latInt.littleEndian) { data.append(contentsOf: $0) }

        // Longitude (int32 * 1E6 little-endian)
        let lonInt = Int32((longitude ?? 0) * 1_000_000)
        withUnsafeBytes(of: lonInt.littleEndian) { data.append(contentsOf: $0) }

        // Last modified (uint32 little-endian)
        let lastMod = UInt32(lastModified.timeIntervalSince1970)
        withUnsafeBytes(of: lastMod.littleEndian) { data.append(contentsOf: $0) }

        return data
    }
}
