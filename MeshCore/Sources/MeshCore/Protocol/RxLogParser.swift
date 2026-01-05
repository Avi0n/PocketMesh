import Foundation

/// Parser for raw RF packets from rxLogData events.
public enum RxLogParser {

    /// Parse raw payload bytes into structured ParsedRxLogData.
    public static func parse(snr: Double?, rssi: Int?, payload: Data) -> ParsedRxLogData? {
        guard !payload.isEmpty else { return nil }

        var offset = 0

        // Parse header byte
        let header = payload[offset]
        offset += 1

        let routeTypeBits = header & 0x03
        let payloadTypeBits = (header >> 2) & 0x0F
        let payloadVersion = (header >> 6) & 0x03

        guard let routeType = RouteType(rawValue: routeTypeBits) else {
            return nil
        }
        let payloadType = PayloadType(fromBits: payloadTypeBits)

        // Parse transport code if present
        var transportCode: Data?
        if routeType.hasTransportCode {
            guard payload.count >= offset + 4 else { return nil }
            transportCode = payload[offset..<offset + 4]
            offset += 4
        }

        // Parse path length
        guard payload.count > offset else { return nil }
        let pathLength = payload[offset]
        offset += 1

        // Parse path nodes
        var pathNodes: [UInt8] = []
        if pathLength > 0 {
            guard payload.count >= offset + Int(pathLength) else { return nil }
            pathNodes = Array(payload[offset..<offset + Int(pathLength)])
            offset += Int(pathLength)
        }

        // Remaining bytes are packet payload
        let packetPayload = payload.count > offset ? Data(payload[offset...]) : Data()

        // Extract dest and src hashes for direct text messages
        // Payload format: [dest: 1B] [src: 1B] [MAC + encrypted content]
        // dest = recipient pubkey hash, src = sender pubkey hash
        var senderPubkeyPrefix: Data?
        var recipientPubkeyPrefix: Data?
        if (routeType == .direct || routeType == .tcDirect) && payloadType == .textMessage && packetPayload.count >= 2 {
            senderPubkeyPrefix = Data([packetPayload[1]])      // src is byte 1
            recipientPubkeyPrefix = Data([packetPayload[0]])   // dest is byte 0
        }

        return ParsedRxLogData(
            snr: snr,
            rssi: rssi,
            rawPayload: payload,
            routeType: routeType,
            payloadType: payloadType,
            payloadVersion: payloadVersion,
            transportCode: transportCode,
            pathLength: pathLength,
            pathNodes: pathNodes,
            packetPayload: packetPayload,
            senderPubkeyPrefix: senderPubkeyPrefix,
            recipientPubkeyPrefix: recipientPubkeyPrefix
        )
    }
}
