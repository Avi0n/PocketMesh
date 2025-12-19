import Foundation

/// Stateless packet builder for constructing MeshCore protocol commands.
///
/// `PacketBuilder` provides static methods to construct the binary command packets
/// sent to a MeshCore device. Each method returns a `Data` object ready to send
/// via the transport layer.
///
/// ## Usage
///
/// These methods are typically called internally by ``MeshCoreSession``, but can be
/// used directly for low-level protocol access:
///
/// ```swift
/// // Build an appStart command
/// let packet = PacketBuilder.appStart(clientId: "MyApp")
///
/// // Build a message command
/// let message = PacketBuilder.sendMessage(
///     to: contactPublicKey,
///     text: "Hello, mesh!",
///     timestamp: Date()
/// )
///
/// // Send via transport
/// try await transport.send(packet)
/// ```
///
/// ## Protocol Format
///
/// All commands follow the format:
/// - Byte 0: Command code (see ``CommandCode``)
/// - Bytes 1+: Command-specific payload
///
/// Multi-byte integers are little-endian. Strings are UTF-8 encoded.
public enum PacketBuilder: Sendable {

    // MARK: - Device Commands

    /// Builds an appStart command to initialize the session.
    ///
    /// - Parameter clientId: Client identifier string (max 12 characters).
    /// - Returns: The command packet data.
    public static func appStart(clientId: String = "MeshCore") -> Data {
        var data = Data([CommandCode.appStart.rawValue, 0x03])
        let paddedId = clientId.padding(toLength: 12, withPad: " ", startingAt: 0)
        data.append(paddedId.data(using: .utf8) ?? Data())
        return data
    }

    /// Builds a deviceQuery command to request device capabilities.
    ///
    /// - Returns: The command packet data.
    public static func deviceQuery() -> Data {
        Data([CommandCode.deviceQuery.rawValue, 0x03])
    }

    /// Builds a getBattery command.
    ///
    /// - Returns: The command packet data.
    public static func getBattery() -> Data {
        Data([CommandCode.getBattery.rawValue])
    }

    /// Builds a getTime command to request the device's current time.
    ///
    /// - Returns: The command packet data.
    public static func getTime() -> Data {
        Data([CommandCode.getTime.rawValue])
    }

    /// Builds a setTime command to set the device's clock.
    ///
    /// - Parameter date: The date to set.
    /// - Returns: The command packet data.
    public static func setTime(_ date: Date) -> Data {
        var data = Data([CommandCode.setTime.rawValue])
        let timestamp = UInt32(date.timeIntervalSince1970)
        data.append(contentsOf: withUnsafeBytes(of: timestamp.littleEndian) { Array($0) })
        return data
    }

    public static func setName(_ name: String) -> Data {
        var data = Data([CommandCode.setName.rawValue])
        data.append(name.data(using: .utf8) ?? Data())
        return data
    }

    public static func setCoordinates(latitude: Double, longitude: Double) -> Data {
        var data = Data([CommandCode.setCoordinates.rawValue])
        let lat = Int32(latitude * 1_000_000)
        let lon = Int32(longitude * 1_000_000)
        data.append(contentsOf: withUnsafeBytes(of: lat.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: lon.littleEndian) { Array($0) })
        data.append(contentsOf: [0, 0, 0, 0]) // altitude placeholder
        return data
    }

    public static func setTxPower(_ power: Int) -> Data {
        var data = Data([CommandCode.setTxPower.rawValue])
        let powerValue = UInt32(power)
        data.append(contentsOf: withUnsafeBytes(of: powerValue.littleEndian) { Array($0) })
        return data
    }

    public static func setRadio(
        frequency: Double,
        bandwidth: Double,
        spreadingFactor: UInt8,
        codingRate: UInt8
    ) -> Data {
        var data = Data([CommandCode.setRadio.rawValue])
        let freq = UInt32(frequency * 1000)
        let bw = UInt32(bandwidth * 1000)
        data.append(contentsOf: withUnsafeBytes(of: freq.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: bw.littleEndian) { Array($0) })
        data.append(spreadingFactor)
        data.append(codingRate)
        return data
    }

    public static func sendAdvertisement(flood: Bool = false) -> Data {
        flood ? Data([CommandCode.sendAdvertisement.rawValue, 0x01]) : Data([CommandCode.sendAdvertisement.rawValue])
    }

    public static func reboot() -> Data {
        var data = Data([CommandCode.reboot.rawValue])
        data.append("reboot".data(using: .utf8) ?? Data())
        return data
    }

    // MARK: - Contact Commands

    public static func getContacts(since lastModified: Date? = nil) -> Data {
        var data = Data([CommandCode.getContacts.rawValue])
        if let lastMod = lastModified {
            let timestamp = UInt32(lastMod.timeIntervalSince1970)
            data.append(contentsOf: withUnsafeBytes(of: timestamp.littleEndian) { Array($0) })
        }
        return data
    }

    public static func resetPath(publicKey: Data) -> Data {
        var data = Data([CommandCode.resetPath.rawValue])
        data.append(publicKey.prefix(32))
        return data
    }

    public static func removeContact(publicKey: Data) -> Data {
        var data = Data([CommandCode.removeContact.rawValue])
        data.append(publicKey.prefix(32))
        return data
    }

    public static func shareContact(publicKey: Data) -> Data {
        var data = Data([CommandCode.shareContact.rawValue])
        data.append(publicKey.prefix(32))
        return data
    }

    public static func exportContact(publicKey: Data? = nil) -> Data {
        var data = Data([CommandCode.exportContact.rawValue])
        if let key = publicKey {
            data.append(key.prefix(32))
        }
        return data
    }

    // MARK: - Messaging Commands

    /// Builds a getMessage command to fetch the next pending message.
    ///
    /// - Returns: The command packet data.
    public static func getMessage() -> Data {
        Data([CommandCode.getMessage.rawValue])
    }

    /// Builds a sendMessage command.
    ///
    /// - Parameters:
    ///   - destination: Destination public key (first 6 bytes used).
    ///   - text: Message text (UTF-8 encoded).
    ///   - timestamp: Message timestamp.
    ///   - attempt: Retry attempt number (for duplicate detection).
    /// - Returns: The command packet data.
    public static func sendMessage(
        to destination: Data,
        text: String,
        timestamp: Date = Date(),
        attempt: UInt8 = 0
    ) -> Data {
        var data = Data([CommandCode.sendMessage.rawValue, 0x00, attempt])
        let ts = UInt32(timestamp.timeIntervalSince1970)
        data.append(contentsOf: withUnsafeBytes(of: ts.littleEndian) { Array($0) })
        data.append(destination.prefix(6))
        data.append(text.data(using: .utf8) ?? Data())
        return data
    }

    public static func sendCommand(
        to destination: Data,
        command: String,
        timestamp: Date = Date()
    ) -> Data {
        var data = Data([CommandCode.sendMessage.rawValue, 0x01, 0x00])
        let ts = UInt32(timestamp.timeIntervalSince1970)
        data.append(contentsOf: withUnsafeBytes(of: ts.littleEndian) { Array($0) })
        data.append(destination.prefix(6))
        data.append(command.data(using: .utf8) ?? Data())
        return data
    }

    public static func sendChannelMessage(
        channel: UInt8,
        text: String,
        timestamp: Date = Date()
    ) -> Data {
        var data = Data([CommandCode.sendChannelMessage.rawValue, 0x00, channel])
        let ts = UInt32(timestamp.timeIntervalSince1970)
        data.append(contentsOf: withUnsafeBytes(of: ts.littleEndian) { Array($0) })
        data.append(text.data(using: .utf8) ?? Data())
        return data
    }

    public static func sendLogin(to destination: Data, password: String) -> Data {
        var data = Data([CommandCode.sendLogin.rawValue])
        data.append(destination.prefix(32))
        data.append(password.data(using: .utf8) ?? Data())
        return data
    }

    public static func sendLogout(to destination: Data) -> Data {
        var data = Data([CommandCode.sendLogout.rawValue])
        data.append(destination.prefix(32))
        return data
    }

    public static func sendStatusRequest(to destination: Data) -> Data {
        var data = Data([CommandCode.sendStatusRequest.rawValue])
        data.append(destination.prefix(32))
        return data
    }

    // MARK: - Binary Protocol Commands

    public static func binaryRequest(
        to destination: Data,
        type: BinaryRequestType,
        payload: Data? = nil
    ) -> Data {
        var data = Data([CommandCode.binaryRequest.rawValue])
        data.append(destination.prefix(32))
        data.append(type.rawValue)
        if let payload = payload {
            data.append(payload)
        }
        return data
    }

    // MARK: - Channel Commands

    public static func getChannel(index: UInt8) -> Data {
        Data([CommandCode.getChannel.rawValue, index])
    }

    public static func setChannel(
        index: UInt8,
        name: String,
        secret: Data
    ) -> Data {
        var data = Data([CommandCode.setChannel.rawValue, index])

        // Pad name to 32 bytes
        var nameData = (name.data(using: .utf8) ?? Data()).prefix(32)
        while nameData.count < 32 {
            nameData.append(0)
        }
        data.append(nameData)

        // Secret must be 16 bytes
        data.append(secret.prefix(16))
        return data
    }

    // MARK: - Stats Commands

    public static func getStatsCore() -> Data {
        Data([CommandCode.getStats.rawValue, StatsType.core.rawValue])
    }

    public static func getStatsRadio() -> Data {
        Data([CommandCode.getStats.rawValue, StatsType.radio.rawValue])
    }

    public static func getStatsPackets() -> Data {
        Data([CommandCode.getStats.rawValue, StatsType.packets.rawValue])
    }

    // MARK: - Additional Commands (from Python reference)

    /// Update a contact's path or flags
    public static func updateContact(publicKey: Data, flags: UInt8? = nil, pathLen: Int8? = nil, path: Data? = nil) -> Data {
        var data = Data([CommandCode.updateContact.rawValue])
        data.append(publicKey.prefix(32))
        // Flags and path update logic based on Python reference
        if let flags = flags {
            data.append(flags)
        }
        if let pathLen = pathLen, let path = path {
            data.append(UInt8(bitPattern: pathLen))
            data.append(path.prefix(64))
        }
        return data
    }

    /// Set tuning parameters (rx_delay, af) per Python device.py
    /// Both fields are 4 bytes, followed by 2 reserved bytes
    public static func setTuning(rxDelay: UInt32, af: UInt32) -> Data {
        var data = Data([CommandCode.setTuning.rawValue])
        data.append(contentsOf: withUnsafeBytes(of: rxDelay.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: af.littleEndian) { Array($0) })
        data.append(contentsOf: [0, 0])  // 2 reserved bytes
        return data
    }

    /// Set other parameters (telemetry mode, adv_loc_policy, etc.)
    /// Per Python device.py:95-128, format is:
    /// - 1 byte: command code (0x26)
    /// - 1 byte: manual_add_contacts (bool as 0/1)
    /// - 1 byte: telemetry_mode (combined env|loc|base)
    /// - 1 byte: adv_loc_policy
    /// - 1 byte: multi_acks (optional, for newer firmware)
    public static func setOtherParams(
        manualAddContacts: Bool,
        telemetryModeEnvironment: UInt8,
        telemetryModeLocation: UInt8,
        telemetryModeBase: UInt8,
        advertisementLocationPolicy: UInt8,
        multiAcks: UInt8? = nil
    ) -> Data {
        var data = Data([CommandCode.setOtherParams.rawValue])
        data.append(manualAddContacts ? 1 : 0)
        // Combine telemetry modes into single byte: env(2) | loc(2) | base(2)
        let telemetryMode = ((telemetryModeEnvironment & 0b11) << 4) |
                           ((telemetryModeLocation & 0b11) << 2) |
                           (telemetryModeBase & 0b11)
        data.append(telemetryMode)
        data.append(advertisementLocationPolicy)
        if let multiAcks = multiAcks {
            data.append(multiAcks)
        }
        return data
    }

    public static func getSelfTelemetry(destination: Data? = nil) -> Data {
        var data = Data([CommandCode.getSelfTelemetry.rawValue, 0x00, 0x00, 0x00])
        if let dest = destination {
            data.append(dest.prefix(32))
        }
        return data
    }

    // MARK: - Security Commands

    /// Set device PIN for BLE pairing
    public static func setDevicePin(_ pin: UInt32) -> Data {
        var data = Data([CommandCode.setDevicePin.rawValue])
        data.append(contentsOf: withUnsafeBytes(of: pin.littleEndian) { Array($0) })
        return data
    }

    /// Get custom variables
    public static func getCustomVars() -> Data {
        Data([CommandCode.getCustomVars.rawValue])
    }

    /// Set a custom variable
    public static func setCustomVar(key: String, value: String) -> Data {
        var data = Data([CommandCode.setCustomVar.rawValue])
        data.append((key + ":" + value).data(using: .utf8) ?? Data())
        return data
    }

    /// Export device private key (requires PIN auth & enabled firmware)
    public static func exportPrivateKey() -> Data {
        Data([CommandCode.exportPrivateKey.rawValue])
    }

    /// Import a private key
    public static func importPrivateKey(_ key: Data) -> Data {
        var data = Data([CommandCode.importPrivateKey.rawValue])
        data.append(key)
        return data
    }

    // MARK: - Signing Commands

    /// Start a signing session
    public static func signStart() -> Data {
        Data([CommandCode.signStart.rawValue])
    }

    /// Send data chunk for signing
    public static func signData(_ chunk: Data) -> Data {
        var data = Data([CommandCode.signData.rawValue])
        data.append(chunk)
        return data
    }

    /// Finish signing session and get signature
    public static func signFinish() -> Data {
        Data([CommandCode.signFinish.rawValue])
    }

    // MARK: - Path Discovery Commands

    /// Request path discovery to a destination
    public static func sendPathDiscovery(to destination: Data) -> Data {
        var data = Data([CommandCode.pathDiscovery.rawValue, 0x00])
        data.append(destination.prefix(32))
        return data
    }

    /// Send a trace packet for route testing
    /// - Parameters:
    ///   - tag: 32-bit identifier for this trace
    ///   - authCode: 32-bit authentication code
    ///   - flags: 8-bit flags field
    ///   - path: Optional path data (repeater pubkey bytes)
    public static func sendTrace(
        tag: UInt32,
        authCode: UInt32,
        flags: UInt8,
        path: Data? = nil
    ) -> Data {
        var data = Data([CommandCode.sendTrace.rawValue])
        data.append(contentsOf: withUnsafeBytes(of: tag.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: authCode.littleEndian) { Array($0) })
        data.append(flags)
        if let path = path {
            data.append(path)
        }
        return data
    }

    /// Set flood scope for message routing
    /// - Parameter scopeKey: 16-byte scope key (or zeros to disable)
    public static func setFloodScope(_ scopeKey: Data) -> Data {
        var data = Data([CommandCode.setFloodScope.rawValue, 0x00])
        data.append(scopeKey.prefix(16))
        return data
    }

    /// Factory reset the device
    public static func factoryReset() -> Data {
        Data([CommandCode.factoryReset.rawValue])
    }

    // MARK: - Control Data Commands

    /// Send control data
    public static func sendControlData(type: UInt8, payload: Data) -> Data {
        var data = Data([CommandCode.sendControlData.rawValue, type])
        data.append(payload)
        return data
    }

    public static func sendNodeDiscoverRequest(
        filter: UInt8,
        prefixOnly: Bool = true,
        tag: UInt32? = nil,
        since: UInt32? = nil
    ) -> Data {
        let actualTag = tag ?? UInt32.random(in: 1...UInt32.max)
        let flags: UInt8 = prefixOnly ? 1 : 0
        let controlType = ControlType.nodeDiscoverRequest.rawValue | flags

        var data = Data([CommandCode.sendControlData.rawValue, controlType])
        data.append(filter)
        data.append(contentsOf: withUnsafeBytes(of: actualTag.littleEndian) { Array($0) })
        if let since = since {
            data.append(contentsOf: withUnsafeBytes(of: since.littleEndian) { Array($0) })
        }
        return data
    }
}
