import Foundation
@testable import PocketMeshKit

/// A complete mock of a MeshCore BLE device for testing.
/// Implements the full Companion Radio Protocol to enable testing without hardware.
public actor MockBLEPeripheral {

    // MARK: - Device State

    private var isConnected = false
    private var protocolVersion: UInt8 = 0

    // Device identity
    private let publicKey: Data
    private var nodeName: String
    private var latitude: Double = 0.0
    private var longitude: Double = 0.0

    // Radio configuration
    private var frequency: UInt32 = 915_000
    private var bandwidth: UInt32 = 250_000
    private var spreadingFactor: UInt8 = 10
    private var codingRate: UInt8 = 5
    private var txPower: UInt8 = 20

    // Telemetry modes
    private var telemetryModeBase: UInt8 = 2
    private var telemetryModeLoc: UInt8 = 0
    private var telemetryModeEnv: UInt8 = 0
    private var advertLocationPolicy: UInt8 = 0
    private var manualAddContacts: UInt8 = 0
    private var multiAcks: UInt8 = 0

    // Device info
    private let firmwareVersion: UInt8 = 8
    private let maxContacts: UInt8 = 50
    private let maxChannels: UInt8 = 8
    private var blePin: UInt32 = 123456

    // Tuning params
    private var rxDelayBase: Float = 0.0
    private var airtimeFactor: Float = 1.0

    // Contacts
    private var contacts: [Data: ContactFrame] = [:]
    private var contactIterator: Array<ContactFrame>.Iterator?
    private var contactFilterSince: UInt32 = 0

    // Channels
    private var channels: [UInt8: ChannelInfo] = [:]

    // Message queue
    private var messageQueue: [Data] = []

    // Pending ACKs
    private var pendingAcks: [UInt32: ContactFrame] = [:]
    private var nextAckCode: UInt32 = 1000

    // Response handler for push notifications
    private var responseHandler: (@Sendable (Data) -> Void)?

    // MARK: - Initialization

    public init(publicKey: Data? = nil, nodeName: String = "MockNode") {
        self.publicKey = publicKey ?? Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        self.nodeName = nodeName

        // Pre-configure public channel
        let publicSecret = Data(repeating: 0, count: 16)
        channels[0] = ChannelInfo(index: 0, name: "Public", secret: publicSecret)
    }

    // MARK: - Connection

    public func connect() {
        isConnected = true
    }

    public func disconnect() {
        isConnected = false
        protocolVersion = 0
        contactIterator = nil
    }

    public func setResponseHandler(_ handler: @escaping @Sendable (Data) -> Void) {
        responseHandler = handler
    }

    public var connected: Bool {
        isConnected
    }

    // MARK: - Command Processing

    public func processCommand(_ data: Data) throws -> Data? {
        guard isConnected, !data.isEmpty else {
            throw ProtocolError.badState
        }

        guard let command = CommandCode(rawValue: data[0]) else {
            return makeErrorFrame(.unsupportedCommand)
        }

        switch command {
        case .deviceQuery:
            return handleDeviceQuery(data)
        case .appStart:
            return handleAppStart(data)
        case .getContacts:
            return handleGetContacts(data)
        case .syncNextMessage:
            return handleSyncNextMessage()
        case .sendTextMessage:
            return handleSendTextMessage(data)
        case .sendChannelTextMessage:
            return handleSendChannelTextMessage(data)
        case .sendSelfAdvert:
            return handleSendSelfAdvert(data)
        case .setAdvertName:
            return handleSetAdvertName(data)
        case .setAdvertLatLon:
            return handleSetAdvertLatLon(data)
        case .setRadioParams:
            return handleSetRadioParams(data)
        case .setRadioTxPower:
            return handleSetRadioTxPower(data)
        case .getBatteryAndStorage:
            return handleGetBatteryAndStorage()
        case .getDeviceTime:
            return handleGetDeviceTime()
        case .setDeviceTime:
            return handleSetDeviceTime(data)
        case .getChannel:
            return handleGetChannel(data)
        case .setChannel:
            return handleSetChannel(data)
        case .addUpdateContact:
            return handleAddUpdateContact(data)
        case .removeContact:
            return handleRemoveContact(data)
        case .resetPath:
            return handleResetPath(data)
        case .shareContact:
            return handleShareContact(data)
        case .getContactByKey:
            return handleGetContactByKey(data)
        case .setOtherParams:
            return handleSetOtherParams(data)
        case .setDevicePin:
            return handleSetDevicePin(data)
        case .reboot:
            return handleReboot(data)
        case .getTuningParams:
            return handleGetTuningParams()
        case .setTuningParams:
            return handleSetTuningParams(data)
        case .getStats:
            return handleGetStats(data)
        case .factoryReset:
            return handleFactoryReset(data)
        default:
            return makeErrorFrame(.unsupportedCommand)
        }
    }

    // MARK: - Command Handlers

    private func handleDeviceQuery(_ data: Data) -> Data {
        guard data.count >= 2 else {
            return makeErrorFrame(.illegalArgument)
        }
        protocolVersion = data[1]

        var response = Data([ResponseCode.deviceInfo.rawValue])
        response.append(firmwareVersion)
        response.append(maxContacts)
        response.append(maxChannels)
        response.append(contentsOf: withUnsafeBytes(of: blePin.littleEndian) { Array($0) })

        // Build date (12 bytes)
        var buildDate = "06 Dec 2025".data(using: .utf8) ?? Data()
        buildDate.append(Data(repeating: 0, count: max(0, 12 - buildDate.count)))
        response.append(buildDate.prefix(12))

        // Manufacturer name (40 bytes)
        var manufacturer = "MockBLE".data(using: .utf8) ?? Data()
        manufacturer.append(Data(repeating: 0, count: max(0, 40 - manufacturer.count)))
        response.append(manufacturer.prefix(40))

        // Firmware version string (20 bytes)
        var fwVersion = "v1.11.0-mock".data(using: .utf8) ?? Data()
        fwVersion.append(Data(repeating: 0, count: max(0, 20 - fwVersion.count)))
        response.append(fwVersion.prefix(20))

        return response
    }

    private func handleAppStart(_ data: Data) -> Data {
        var response = Data([ResponseCode.selfInfo.rawValue])
        response.append(0x00)
        response.append(txPower)
        response.append(20)
        response.append(publicKey)

        let latInt = Int32(latitude * 1_000_000)
        let lonInt = Int32(longitude * 1_000_000)
        response.append(contentsOf: withUnsafeBytes(of: latInt.littleEndian) { Array($0) })
        response.append(contentsOf: withUnsafeBytes(of: lonInt.littleEndian) { Array($0) })

        response.append(multiAcks)
        response.append(advertLocationPolicy)
        response.append((telemetryModeEnv << 4) | (telemetryModeLoc << 2) | telemetryModeBase)
        response.append(manualAddContacts)

        response.append(contentsOf: withUnsafeBytes(of: frequency.littleEndian) { Array($0) })
        response.append(contentsOf: withUnsafeBytes(of: bandwidth.littleEndian) { Array($0) })
        response.append(spreadingFactor)
        response.append(codingRate)

        response.append(nodeName.data(using: .utf8) ?? Data())

        return response
    }

    private func handleGetContacts(_ data: Data) -> Data {
        if data.count >= 5 {
            contactFilterSince = data.subdata(in: 1..<5).withUnsafeBytes {
                $0.load(as: UInt32.self).littleEndian
            }
        } else {
            contactFilterSince = 0
        }

        let filteredContacts = contacts.values.filter { $0.lastModified > contactFilterSince }
        contactIterator = Array(filteredContacts).makeIterator()

        var response = Data([ResponseCode.contactsStart.rawValue])
        let count = UInt32(filteredContacts.count)
        response.append(contentsOf: withUnsafeBytes(of: count.littleEndian) { Array($0) })

        return response
    }

    /// Call this repeatedly after getContacts to iterate through contacts
    public func getNextContact() -> Data? {
        guard var iterator = contactIterator else { return nil }

        if let contact = iterator.next() {
            contactIterator = iterator
            return encodeContactFrame(contact)
        } else {
            contactIterator = nil

            var response = Data([ResponseCode.endOfContacts.rawValue])
            let mostRecent = contacts.values.map { $0.lastModified }.max() ?? 0
            response.append(contentsOf: withUnsafeBytes(of: mostRecent.littleEndian) { Array($0) })
            return response
        }
    }

    private func handleSyncNextMessage() -> Data {
        if let message = messageQueue.first {
            messageQueue.removeFirst()
            return message
        }
        return Data([ResponseCode.noMoreMessages.rawValue])
    }

    private func handleSendTextMessage(_ data: Data) -> Data {
        guard data.count >= 14 else {
            return makeErrorFrame(.illegalArgument)
        }

        let recipientPrefix = data.subdata(in: 7..<13)

        // Find contact by prefix
        let contact = contacts.first { key, _ in
            key.prefix(6) == recipientPrefix
        }

        guard contact != nil else {
            return makeErrorFrame(.notFound)
        }

        let ackCode = nextAckCode
        nextAckCode += 1

        var response = Data([ResponseCode.sent.rawValue])
        response.append(0)
        response.append(contentsOf: withUnsafeBytes(of: ackCode.littleEndian) { Array($0) })
        let timeout: UInt32 = 5000
        response.append(contentsOf: withUnsafeBytes(of: timeout.littleEndian) { Array($0) })

        return response
    }

    private func handleSendChannelTextMessage(_ data: Data) -> Data {
        guard data.count >= 7 else {
            return makeErrorFrame(.illegalArgument)
        }

        let channelIdx = data[2]
        guard channels[channelIdx] != nil else {
            return makeErrorFrame(.notFound)
        }

        return Data([ResponseCode.ok.rawValue])
    }

    private func handleSendSelfAdvert(_ data: Data) -> Data {
        Data([ResponseCode.ok.rawValue])
    }

    private func handleSetAdvertName(_ data: Data) -> Data {
        guard data.count >= 2 else {
            return makeErrorFrame(.illegalArgument)
        }

        let nameData = data.suffix(from: 1)
        if let name = String(data: nameData, encoding: .utf8) {
            nodeName = String(name.prefix(31))
        }

        return Data([ResponseCode.ok.rawValue])
    }

    private func handleSetAdvertLatLon(_ data: Data) -> Data {
        guard data.count >= 9 else {
            return makeErrorFrame(.illegalArgument)
        }

        let latInt = data.subdata(in: 1..<5).withUnsafeBytes { $0.load(as: Int32.self).littleEndian }
        let lonInt = data.subdata(in: 5..<9).withUnsafeBytes { $0.load(as: Int32.self).littleEndian }

        guard latInt >= -90_000_000 && latInt <= 90_000_000 &&
              lonInt >= -180_000_000 && lonInt <= 180_000_000 else {
            return makeErrorFrame(.illegalArgument)
        }

        latitude = Double(latInt) / 1_000_000.0
        longitude = Double(lonInt) / 1_000_000.0

        return Data([ResponseCode.ok.rawValue])
    }

    private func handleSetRadioParams(_ data: Data) -> Data {
        guard data.count >= 11 else {
            return makeErrorFrame(.illegalArgument)
        }

        let freq = data.subdata(in: 1..<5).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let bw = data.subdata(in: 5..<9).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let sf = data[9]
        let cr = data[10]

        guard freq >= 300_000 && freq <= 2_500_000 &&
              bw >= 7_000 && bw <= 500_000 &&
              sf >= 5 && sf <= 12 &&
              cr >= 5 && cr <= 8 else {
            return makeErrorFrame(.illegalArgument)
        }

        frequency = freq
        bandwidth = bw
        spreadingFactor = sf
        codingRate = cr

        return Data([ResponseCode.ok.rawValue])
    }

    private func handleSetRadioTxPower(_ data: Data) -> Data {
        guard data.count >= 2 else {
            return makeErrorFrame(.illegalArgument)
        }

        let power = data[1]
        guard power >= 1 && power <= 20 else {
            return makeErrorFrame(.illegalArgument)
        }

        txPower = power
        return Data([ResponseCode.ok.rawValue])
    }

    private func handleGetBatteryAndStorage() -> Data {
        var response = Data([ResponseCode.batteryAndStorage.rawValue])
        let battery: UInt16 = 4200
        let used: UInt32 = 128
        let total: UInt32 = 1024

        response.append(contentsOf: withUnsafeBytes(of: battery.littleEndian) { Array($0) })
        response.append(contentsOf: withUnsafeBytes(of: used.littleEndian) { Array($0) })
        response.append(contentsOf: withUnsafeBytes(of: total.littleEndian) { Array($0) })

        return response
    }

    private func handleGetDeviceTime() -> Data {
        var response = Data([ResponseCode.currentTime.rawValue])
        let time = UInt32(Date().timeIntervalSince1970)
        response.append(contentsOf: withUnsafeBytes(of: time.littleEndian) { Array($0) })
        return response
    }

    private func handleSetDeviceTime(_ data: Data) -> Data {
        guard data.count >= 5 else {
            return makeErrorFrame(.illegalArgument)
        }
        return Data([ResponseCode.ok.rawValue])
    }

    private func handleGetChannel(_ data: Data) -> Data {
        guard data.count >= 2 else {
            return makeErrorFrame(.illegalArgument)
        }

        let idx = data[1]
        guard let channel = channels[idx] else {
            return makeErrorFrame(.notFound)
        }

        var response = Data([ResponseCode.channelInfo.rawValue])
        response.append(idx)

        var nameData = channel.name.data(using: .utf8) ?? Data()
        nameData.append(Data(repeating: 0, count: max(0, 32 - nameData.count)))
        response.append(nameData.prefix(32))
        response.append(channel.secret.prefix(16))

        return response
    }

    private func handleSetChannel(_ data: Data) -> Data {
        guard data.count >= 50 else {
            return makeErrorFrame(.illegalArgument)
        }

        let idx = data[1]
        guard idx < 8 else {
            return makeErrorFrame(.notFound)
        }

        let nameData = data.subdata(in: 2..<34)
        let name = String(data: nameData, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters) ?? ""
        let secret = data.subdata(in: 34..<50)

        channels[idx] = ChannelInfo(index: idx, name: name, secret: secret)

        return Data([ResponseCode.ok.rawValue])
    }

    private func handleAddUpdateContact(_ data: Data) -> Data {
        guard data.count >= 147 else {
            return makeErrorFrame(.illegalArgument)
        }

        // Build contact frame with response code prefix for decoding
        let contactData = Data([ResponseCode.contact.rawValue]) + data.suffix(from: 1)

        do {
            let contact = try FrameCodec.decodeContact(from: contactData)
            contacts[contact.publicKey] = contact
            return Data([ResponseCode.ok.rawValue])
        } catch {
            return makeErrorFrame(.illegalArgument)
        }
    }

    private func handleRemoveContact(_ data: Data) -> Data {
        guard data.count >= 33 else {
            return makeErrorFrame(.illegalArgument)
        }

        let publicKey = data.subdata(in: 1..<33)

        if contacts.removeValue(forKey: publicKey) != nil {
            return Data([ResponseCode.ok.rawValue])
        }

        return makeErrorFrame(.notFound)
    }

    private func handleResetPath(_ data: Data) -> Data {
        guard data.count >= 33 else {
            return makeErrorFrame(.illegalArgument)
        }

        let publicKey = data.subdata(in: 1..<33)

        guard var contact = contacts[publicKey] else {
            return makeErrorFrame(.notFound)
        }

        // Reset path to flood routing
        let updatedContact = ContactFrame(
            publicKey: contact.publicKey,
            type: contact.type,
            flags: contact.flags,
            outPathLength: -1,  // Flood routing
            outPath: Data(),
            name: contact.name,
            lastAdvertTimestamp: contact.lastAdvertTimestamp,
            latitude: contact.latitude,
            longitude: contact.longitude,
            lastModified: UInt32(Date().timeIntervalSince1970)
        )
        contacts[publicKey] = updatedContact

        return Data([ResponseCode.ok.rawValue])
    }

    private func handleShareContact(_ data: Data) -> Data {
        guard data.count >= 33 else {
            return makeErrorFrame(.illegalArgument)
        }

        let publicKey = data.subdata(in: 1..<33)

        guard contacts[publicKey] != nil else {
            return makeErrorFrame(.notFound)
        }

        // In a real device, this would broadcast the contact
        return Data([ResponseCode.ok.rawValue])
    }

    private func handleGetContactByKey(_ data: Data) -> Data {
        guard data.count >= 33 else {
            return makeErrorFrame(.illegalArgument)
        }

        let publicKey = data.subdata(in: 1..<33)

        if let contact = contacts[publicKey] {
            return encodeContactFrame(contact)
        }

        return makeErrorFrame(.notFound)
    }

    private func handleSetOtherParams(_ data: Data) -> Data {
        guard data.count >= 2 else {
            return makeErrorFrame(.illegalArgument)
        }

        manualAddContacts = data[1]

        if data.count >= 3 {
            let modes = data[2]
            telemetryModeBase = modes & 0x03
            telemetryModeLoc = (modes >> 2) & 0x03
            telemetryModeEnv = (modes >> 4) & 0x03
        }

        if data.count >= 4 {
            advertLocationPolicy = data[3]
        }

        if data.count >= 5 {
            multiAcks = data[4]
        }

        return Data([ResponseCode.ok.rawValue])
    }

    private func handleSetDevicePin(_ data: Data) -> Data {
        guard data.count >= 5 else {
            return makeErrorFrame(.illegalArgument)
        }

        let pin = data.subdata(in: 1..<5).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

        guard pin == 0 || (pin >= 100_000 && pin <= 999_999) else {
            return makeErrorFrame(.illegalArgument)
        }

        blePin = pin
        return Data([ResponseCode.ok.rawValue])
    }

    private func handleReboot(_ data: Data) -> Data {
        guard data.count >= 7 else {
            return makeErrorFrame(.illegalArgument)
        }

        let confirmData = data.subdata(in: 1..<7)
        guard String(data: confirmData, encoding: .utf8) == "reboot" else {
            return makeErrorFrame(.illegalArgument)
        }

        disconnect()
        return Data([ResponseCode.ok.rawValue])
    }

    private func handleGetTuningParams() -> Data {
        var response = Data([ResponseCode.tuningParams.rawValue])
        let rxDelayInt = UInt32(rxDelayBase * 1000)
        let airtimeInt = UInt32(airtimeFactor * 1000)
        response.append(contentsOf: withUnsafeBytes(of: rxDelayInt.littleEndian) { Array($0) })
        response.append(contentsOf: withUnsafeBytes(of: airtimeInt.littleEndian) { Array($0) })
        return response
    }

    private func handleSetTuningParams(_ data: Data) -> Data {
        guard data.count >= 9 else {
            return makeErrorFrame(.illegalArgument)
        }

        let rxDelayInt = data.subdata(in: 1..<5).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
        let airtimeInt = data.subdata(in: 5..<9).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }

        rxDelayBase = Float(rxDelayInt) / 1000.0
        airtimeFactor = Float(airtimeInt) / 1000.0

        return Data([ResponseCode.ok.rawValue])
    }

    private func handleGetStats(_ data: Data) -> Data {
        guard data.count >= 2 else {
            return makeErrorFrame(.illegalArgument)
        }

        let statsType = data[1]

        switch StatsType(rawValue: statsType) {
        case .core:
            var response = Data([ResponseCode.stats.rawValue, StatsType.core.rawValue])
            let battery: UInt16 = 4200
            let uptime: UInt32 = 3600
            let errors: UInt16 = 0
            let queue: UInt8 = UInt8(messageQueue.count)
            response.append(contentsOf: withUnsafeBytes(of: battery.littleEndian) { Array($0) })
            response.append(contentsOf: withUnsafeBytes(of: uptime.littleEndian) { Array($0) })
            response.append(contentsOf: withUnsafeBytes(of: errors.littleEndian) { Array($0) })
            response.append(queue)
            return response

        case .radio:
            var response = Data([ResponseCode.stats.rawValue, StatsType.radio.rawValue])
            let noise: Int16 = -120
            let rssi: Int8 = -60
            let snr: Int8 = 40
            let txAir: UInt32 = 100
            let rxAir: UInt32 = 200
            response.append(contentsOf: withUnsafeBytes(of: noise.littleEndian) { Array($0) })
            response.append(UInt8(bitPattern: rssi))
            response.append(UInt8(bitPattern: snr))
            response.append(contentsOf: withUnsafeBytes(of: txAir.littleEndian) { Array($0) })
            response.append(contentsOf: withUnsafeBytes(of: rxAir.littleEndian) { Array($0) })
            return response

        case .packets:
            var response = Data([ResponseCode.stats.rawValue, StatsType.packets.rawValue])
            let recv: UInt32 = 50
            let sent: UInt32 = 30
            let floodSent: UInt32 = 10
            let directSent: UInt32 = 20
            let floodRecv: UInt32 = 25
            let directRecv: UInt32 = 25
            response.append(contentsOf: withUnsafeBytes(of: recv.littleEndian) { Array($0) })
            response.append(contentsOf: withUnsafeBytes(of: sent.littleEndian) { Array($0) })
            response.append(contentsOf: withUnsafeBytes(of: floodSent.littleEndian) { Array($0) })
            response.append(contentsOf: withUnsafeBytes(of: directSent.littleEndian) { Array($0) })
            response.append(contentsOf: withUnsafeBytes(of: floodRecv.littleEndian) { Array($0) })
            response.append(contentsOf: withUnsafeBytes(of: directRecv.littleEndian) { Array($0) })
            return response

        default:
            return makeErrorFrame(.illegalArgument)
        }
    }

    private func handleFactoryReset(_ data: Data) -> Data {
        guard data.count >= 8 else {
            return makeErrorFrame(.illegalArgument)
        }

        let confirmData = data.subdata(in: 1..<8)
        guard String(data: confirmData, encoding: .utf8) == "factory" else {
            return makeErrorFrame(.illegalArgument)
        }

        // Reset to defaults
        contacts.removeAll()
        channels.removeAll()
        channels[0] = ChannelInfo(index: 0, name: "Public", secret: Data(repeating: 0, count: 16))
        messageQueue.removeAll()
        nodeName = "MockNode"
        latitude = 0.0
        longitude = 0.0

        disconnect()
        return Data([ResponseCode.ok.rawValue])
    }

    // MARK: - Test Helpers

    public func addContact(_ contact: ContactFrame) {
        contacts[contact.publicKey] = contact
    }

    public func queueIncomingMessage(_ message: Data) {
        messageQueue.append(message)
    }

    public func simulatePush(_ pushCode: PushCode, data: Data) {
        var frame = Data([pushCode.rawValue])
        frame.append(data)
        responseHandler?(frame)
    }

    public func simulateMessageReceived(from senderPrefix: Data, text: String, timestamp: UInt32 = 0) {
        let ts = timestamp > 0 ? timestamp : UInt32(Date().timeIntervalSince1970)

        var frame = Data([ResponseCode.contactMessageReceivedV3.rawValue])
        frame.append(40)
        frame.append(0)
        frame.append(0)
        frame.append(senderPrefix.prefix(6))
        frame.append(2)
        frame.append(TextType.plain.rawValue)
        frame.append(contentsOf: withUnsafeBytes(of: ts.littleEndian) { Array($0) })
        frame.append(text.data(using: .utf8) ?? Data())

        messageQueue.append(frame)

        responseHandler?(Data([PushCode.messageWaiting.rawValue]))
    }

    public func simulateSendConfirmed(ackCode: UInt32, roundTrip: UInt32 = 500) {
        var frame = Data([PushCode.sendConfirmed.rawValue])
        frame.append(contentsOf: withUnsafeBytes(of: ackCode.littleEndian) { Array($0) })
        frame.append(contentsOf: withUnsafeBytes(of: roundTrip.littleEndian) { Array($0) })
        responseHandler?(frame)
    }

    public var contactCount: Int {
        contacts.count
    }

    public var channelCount: Int {
        channels.count
    }

    public var currentNodeName: String {
        nodeName
    }

    public var currentFrequency: UInt32 {
        frequency
    }

    public var currentTxPower: UInt8 {
        txPower
    }

    // MARK: - Private Helpers

    private func makeErrorFrame(_ error: ProtocolError) -> Data {
        Data([ResponseCode.error.rawValue, error.rawValue])
    }

    private func encodeContactFrame(_ contact: ContactFrame) -> Data {
        var response = Data([ResponseCode.contact.rawValue])
        response.append(contact.publicKey)
        response.append(contact.type.rawValue)
        response.append(contact.flags)
        response.append(UInt8(bitPattern: Int8(contact.outPathLength)))

        var pathData = contact.outPath
        if pathData.count < 64 {
            pathData.append(Data(repeating: 0, count: 64 - pathData.count))
        }
        response.append(pathData.prefix(64))

        var nameData = contact.name.data(using: .utf8) ?? Data()
        if nameData.count < 32 {
            nameData.append(Data(repeating: 0, count: 32 - nameData.count))
        }
        response.append(nameData.prefix(32))

        response.append(contentsOf: withUnsafeBytes(of: contact.lastAdvertTimestamp.littleEndian) { Array($0) })
        response.append(contentsOf: withUnsafeBytes(of: contact.latitude) { Array($0) })
        response.append(contentsOf: withUnsafeBytes(of: contact.longitude) { Array($0) })
        response.append(contentsOf: withUnsafeBytes(of: contact.lastModified.littleEndian) { Array($0) })

        return response
    }
}
