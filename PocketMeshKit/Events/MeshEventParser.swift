// swiftlint:disable file_length
import Foundation
import OSLog

/// Parses raw BLE data into typed MeshEvents
/// Reuses existing FrameCodec decoders for payload parsing
public struct MeshEventParser: Sendable {

    private static let logger = Logger(subsystem: "com.pocketmesh", category: "EventParser")

    /// Parse raw response data into a MeshEvent
    /// - Parameter data: Raw BLE response data
    /// - Returns: Parsed MeshEvent, or nil if unrecognized
    public static func parseResponse(_ data: Data) -> MeshEvent? {
        guard !data.isEmpty else { return nil }

        let responseCode = data[0]

        // Check if it's a push notification (0x80+)
        if responseCode >= 0x80 {
            return parsePushNotification(data)
        }

        // Otherwise it's a command response
        return parseCommandResponse(data)
    }
}

// MARK: - Push Notification Parsing

extension MeshEventParser {

    // swiftlint:disable:next cyclomatic_complexity
    private static func parsePushNotification(_ data: Data) -> MeshEvent? {
        guard let pushCode = PushCode(rawValue: data[0]) else {
            logger.warning("Unknown push code: 0x\(String(format: "%02X", data[0]))")
            return nil
        }

        switch pushCode {
        case .messageWaiting:
            return MeshEvent(type: .messagesWaiting, payload: EmptyPayload())
        case .sendConfirmed:
            return parseSendConfirmed(data)
        case .advert:
            return parseAdvert(data)
        case .newAdvert:
            return parseNewAdvert(data)
        case .pathUpdated:
            return parsePathUpdated(data)
        case .loginSuccess, .loginFail:
            return parseLoginResult(data, pushCode: pushCode)
        case .statusResponse:
            return parseStatusResponse(data)
        case .telemetryResponse:
            return parseTelemetryResponse(data)
        case .binaryResponse:
            return parseBinaryResponse(data)
        case .traceData:
            return parseTraceData(data)
        case .pathDiscoveryResponse:
            return parsePathDiscoveryResponse(data)
        case .controlData:
            return parseControlData(data)
        case .logRxData:
            return MeshEvent(type: .logData, payload: data.subdata(in: 1..<data.count))
        case .rawData:
            return MeshEvent(type: .rawData, payload: data.subdata(in: 1..<data.count))
        }
    }

    private static func parseSendConfirmed(_ data: Data) -> MeshEvent? {
        guard let confirmation = try? FrameCodec.decodeSendConfirmation(from: data) else {
            return nil
        }
        return MeshEvent(
            type: .sendConfirmed,
            payload: confirmation,
            attributes: ["ackCode": String(confirmation.ackCode)]
        )
    }

    private static func parseAdvert(_ data: Data) -> MeshEvent? {
        guard data.count >= 33 else { return nil }
        let publicKey = data.subdata(in: 1..<33)
        return MeshEvent(
            type: .advertisement,
            payload: ["publicKey": publicKey],
            attributes: ["publicKey": publicKey.hexString()]
        )
    }

    private static func parseNewAdvert(_ data: Data) -> MeshEvent? {
        guard let contact = try? FrameCodec.decodeContact(from: data) else { return nil }
        return MeshEvent(
            type: .newContact,
            payload: contact,
            attributes: ["publicKey": contact.publicKey.hexString()]
        )
    }

    private static func parsePathUpdated(_ data: Data) -> MeshEvent? {
        guard data.count >= 33 else { return nil }
        let publicKey = data.subdata(in: 1..<33)
        return MeshEvent(
            type: .pathUpdate,
            payload: ["publicKey": publicKey],
            attributes: ["publicKey": publicKey.hexString()]
        )
    }

    private static func parseLoginResult(_ data: Data, pushCode: PushCode) -> MeshEvent? {
        guard let result = try? FrameCodec.decodeLoginResult(from: data) else { return nil }
        let eventType: MeshEventType = pushCode == .loginSuccess ? .loginSuccess : .loginFailed
        return MeshEvent(
            type: eventType,
            payload: result,
            attributes: ["publicKeyPrefix": result.publicKeyPrefix.hexString()]
        )
    }

    private static func parseStatusResponse(_ data: Data) -> MeshEvent? {
        guard let status = try? FrameCodec.decodeStatusResponse(from: data) else { return nil }
        return MeshEvent(
            type: .statusResponse,
            payload: status,
            attributes: ["publicKeyPrefix": status.publicKeyPrefix.hexString()]
        )
    }

    private static func parseTelemetryResponse(_ data: Data) -> MeshEvent? {
        guard let telemetry = try? FrameCodec.decodeTelemetryResponse(from: data) else { return nil }
        return MeshEvent(
            type: .telemetryResponse,
            payload: telemetry,
            attributes: ["publicKeyPrefix": telemetry.publicKeyPrefix.hexString()]
        )
    }

    private static func parseBinaryResponse(_ data: Data) -> MeshEvent? {
        guard let response = try? FrameCodec.decodeBinaryResponse(from: data) else { return nil }

        // Check for specific binary response types
        if let requestType = response.rawData.first {
            if let event = parseBinaryResponseByType(response: response, requestType: requestType) {
                return event
            }
        }

        return MeshEvent(
            type: .binaryResponse,
            payload: response,
            attributes: ["tag": response.tag.hexString()]
        )
    }

    private static func parseBinaryResponseByType(
        response: BinaryResponse,
        requestType: UInt8
    ) -> MeshEvent? {
        switch requestType {
        case BinaryRequestType.neighbours.rawValue:
            // Try to decode as neighbours response with default prefix length of 4
            if let neighbours = try? FrameCodec.decodeNeighboursResponse(
                from: Data(response.rawData.dropFirst()),
                tag: response.tag,
                pubkeyPrefixLength: 4
            ) {
                return MeshEvent(
                    type: .neighboursResponse,
                    payload: neighbours,
                    attributes: ["tag": response.tag.hexString()]
                )
            }
            return nil
        case BinaryRequestType.mma.rawValue:
            return MeshEvent(
                type: .mmaResponse,
                payload: response,
                attributes: ["tag": response.tag.hexString()]
            )
        case BinaryRequestType.acl.rawValue:
            return MeshEvent(
                type: .aclResponse,
                payload: response,
                attributes: ["tag": response.tag.hexString()]
            )
        default:
            return nil
        }
    }

    private static func parseTraceData(_ data: Data) -> MeshEvent? {
        guard let trace = try? FrameCodec.decodeTraceData(from: data) else { return nil }
        return MeshEvent(
            type: .traceData,
            payload: trace,
            attributes: ["tag": String(trace.tag)]
        )
    }

    private static func parsePathDiscoveryResponse(_ data: Data) -> MeshEvent? {
        guard let discovery = try? FrameCodec.decodePathDiscoveryResponse(from: data) else {
            return nil
        }
        return MeshEvent(
            type: .pathDiscoveryResponse,
            payload: discovery,
            attributes: ["publicKeyPrefix": discovery.publicKeyPrefix.hexString()]
        )
    }

    private static func parseControlData(_ data: Data) -> MeshEvent? {
        guard let controlData = try? FrameCodec.decodeControlData(from: data) else { return nil }

        // Check if it's a node discover response
        if controlData.payloadType & 0xF0 == ControlDataType.nodeDiscoverResponse.rawValue {
            if let discover = try? FrameCodec.decodeNodeDiscoverResponse(from: controlData) {
                return MeshEvent(
                    type: .discoverResponse,
                    payload: discover,
                    attributes: ["tag": discover.tag.hexString()]
                )
            }
        }

        return MeshEvent(
            type: .controlData,
            payload: controlData,
            attributes: ["payloadType": String(controlData.payloadType)]
        )
    }
}

// MARK: - Command Response Parsing

extension MeshEventParser {

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func parseCommandResponse(_ data: Data) -> MeshEvent? {
        guard let responseCode = ResponseCode(rawValue: data[0]) else {
            logger.warning("Unknown response code: 0x\(String(format: "%02X", data[0]))")
            return nil
        }

        switch responseCode {
        case .ok:
            return parseOkResponse(data)
        case .error:
            return parseErrorResponse(data)
        case .noMoreMessages:
            return MeshEvent(type: .noMoreMessages, payload: EmptyPayload())
        case .sent:
            return parseSentResponse(data)
        case .contactMessageReceivedV3:
            return parseContactMessage(data)
        case .channelMessageReceivedV3:
            return parseChannelMessage(data)
        case .selfInfo:
            return parseSelfInfo(data)
        case .deviceInfo:
            return parseDeviceInfo(data)
        case .batteryAndStorage:
            return parseBatteryAndStorage(data)
        case .channelInfo:
            return parseChannelInfo(data)
        case .contact:
            return parseContact(data)
        case .contactsStart:
            return parseContactsStart(data)
        case .endOfContacts:
            return MeshEvent(type: .contactsEnd, payload: EmptyPayload())
        case .currentTime:
            return parseCurrentTime(data)
        case .stats:
            return parseStatsResponse(data)
        case .privateKey:
            return parsePrivateKey(data)
        case .disabled:
            return MeshEvent(type: .disabled, payload: EmptyPayload())
        case .signStart:
            return parseSignStart(data)
        case .signature:
            return parseSignature(data)
        case .customVars:
            return parseCustomVars(data)
        case .tuningParams:
            return parseTuningParams(data)
        case .hasConnection:
            return parseHasConnection(data)
        case .advertPath:
            return parseAdvertPath(data)
        case .exportContact:
            return parseExportContact(data)
        case .contactMessageReceived, .channelMessageReceived:
            logger.debug("Legacy message format received: 0x\(String(format: "%02X", responseCode.rawValue))")
            return nil
        }
    }

    private static func parseOkResponse(_ data: Data) -> MeshEvent {
        var value: UInt32?
        if data.count >= 5 {
            value = data.subdata(in: 1..<5).withUnsafeBytes {
                $0.load(as: UInt32.self).littleEndian
            }
        }
        return MeshEvent(type: .commandOk, payload: OKPayload(value: value))
    }

    private static func parseErrorResponse(_ data: Data) -> MeshEvent {
        let errorCode = data.count > 1 ? data[1] : 0
        return MeshEvent(type: .error, payload: ErrorPayload(errorCode: errorCode))
    }

    private static func parseSentResponse(_ data: Data) -> MeshEvent? {
        guard let response = try? FrameCodec.decodeSentResponse(from: data) else { return nil }
        return MeshEvent(
            type: .messageSent,
            payload: response,
            attributes: ["ackCode": String(response.ackCode)]
        )
    }

    private static func parseContactMessage(_ data: Data) -> MeshEvent? {
        guard let frame = try? FrameCodec.decodeMessageV3(from: data) else { return nil }
        return MeshEvent(
            type: .contactMessage,
            payload: frame,
            attributes: ["publicKeyPrefix": frame.senderPublicKeyPrefix.hexString()]
        )
    }

    private static func parseChannelMessage(_ data: Data) -> MeshEvent? {
        guard let frame = try? FrameCodec.decodeChannelMessageV3(from: data) else { return nil }
        return MeshEvent(
            type: .channelMessage,
            payload: frame,
            attributes: ["channelIndex": String(frame.channelIndex)]
        )
    }

    private static func parseSelfInfo(_ data: Data) -> MeshEvent? {
        guard let info = try? FrameCodec.decodeSelfInfo(from: data) else { return nil }
        return MeshEvent(type: .selfInfo, payload: info)
    }

    private static func parseDeviceInfo(_ data: Data) -> MeshEvent? {
        guard let info = try? FrameCodec.decodeDeviceInfo(from: data) else { return nil }
        return MeshEvent(type: .deviceInfo, payload: info)
    }

    private static func parseBatteryAndStorage(_ data: Data) -> MeshEvent? {
        guard let info = try? FrameCodec.decodeBatteryAndStorage(from: data) else { return nil }
        return MeshEvent(type: .batteryAndStorage, payload: info)
    }

    private static func parseChannelInfo(_ data: Data) -> MeshEvent? {
        guard let info = try? FrameCodec.decodeChannelInfo(from: data) else { return nil }
        return MeshEvent(
            type: .channelInfo,
            payload: info,
            attributes: ["channelIndex": String(info.index)]
        )
    }

    private static func parseContact(_ data: Data) -> MeshEvent? {
        guard let contact = try? FrameCodec.decodeContact(from: data) else { return nil }
        return MeshEvent(
            type: .contact,
            payload: contact,
            attributes: ["publicKey": contact.publicKey.hexString()]
        )
    }

    private static func parseContactsStart(_ data: Data) -> MeshEvent {
        var count: UInt32 = 0
        if data.count >= 5 {
            count = data.subdata(in: 1..<5).withUnsafeBytes {
                $0.load(as: UInt32.self).littleEndian
            }
        }
        return MeshEvent(type: .contactsStart, payload: ["count": count])
    }

    private static func parseCurrentTime(_ data: Data) -> MeshEvent? {
        guard data.count >= 5 else { return nil }
        let timestamp = data.subdata(in: 1..<5).withUnsafeBytes {
            $0.load(as: UInt32.self).littleEndian
        }
        return MeshEvent(type: .currentTime, payload: CurrentTimePayload(timestamp: timestamp))
    }

    private static func parseStatsResponse(_ data: Data) -> MeshEvent? {
        guard data.count >= 2 else { return nil }

        let statsType = data[1]

        switch statsType {
        case 0:
            guard let stats = try? FrameCodec.decodeCoreStats(from: data) else { return nil }
            return MeshEvent(type: .statsCore, payload: stats)
        case 1:
            guard let stats = try? FrameCodec.decodeRadioStats(from: data) else { return nil }
            return MeshEvent(type: .statsRadio, payload: stats)
        case 2:
            guard let stats = try? FrameCodec.decodePacketStats(from: data) else { return nil }
            return MeshEvent(type: .statsPackets, payload: stats)
        default:
            logger.warning("Unknown stats type: \(statsType)")
            return nil
        }
    }

    private static func parsePrivateKey(_ data: Data) -> MeshEvent? {
        guard data.count >= 65 else { return nil }
        let privateKey = data.subdata(in: 1..<65)
        return MeshEvent(type: .privateKey, payload: PrivateKeyPayload(privateKey: privateKey))
    }

    private static func parseSignStart(_ data: Data) -> MeshEvent? {
        guard data.count >= 6 else { return nil }
        let maxLength = data.subdata(in: 2..<6).withUnsafeBytes {
            $0.load(as: UInt32.self).littleEndian
        }
        return MeshEvent(type: .signStart, payload: SignStartPayload(maxLength: maxLength))
    }

    private static func parseSignature(_ data: Data) -> MeshEvent {
        let signature = data.subdata(in: 1..<data.count)
        return MeshEvent(type: .signature, payload: SignaturePayload(signature: signature))
    }

    private static func parseCustomVars(_ data: Data) -> MeshEvent {
        let varsString = String(data: data.subdata(in: 1..<data.count), encoding: .utf8) ?? ""
        var vars: [String: String] = [:]
        for pair in varsString.split(separator: ",") {
            let parts = pair.split(separator: ":")
            if parts.count == 2 {
                vars[String(parts[0])] = String(parts[1])
            }
        }
        return MeshEvent(type: .customVars, payload: vars)
    }

    private static func parseTuningParams(_ data: Data) -> MeshEvent? {
        guard let params = try? FrameCodec.decodeTuningParams(from: data) else { return nil }
        return MeshEvent(type: .tuningParams, payload: params)
    }

    private static func parseHasConnection(_ data: Data) -> MeshEvent {
        let hasConnection = data.count > 1 && data[1] != 0
        return MeshEvent(type: .hasConnection, payload: ["hasConnection": hasConnection])
    }

    private static func parseAdvertPath(_ data: Data) -> MeshEvent? {
        guard let pathResponse = try? FrameCodec.decodeAdvertPathResponse(from: data) else {
            return nil
        }
        return MeshEvent(type: .advertPath, payload: pathResponse)
    }

    private static func parseExportContact(_ data: Data) -> MeshEvent? {
        guard let contact = try? FrameCodec.decodeContact(from: data) else { return nil }
        return MeshEvent(
            type: .contactExport,
            payload: contact,
            attributes: ["publicKey": contact.publicKey.hexString()]
        )
    }
}
