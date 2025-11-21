import Foundation
import OSLog

private let logger = Logger(subsystem: "com.pocketmesh.app", category: "Authentication")

public extension MeshCoreProtocol {
    /// Send login credentials to repeater/sensor
    func login(to contact: ContactData, password: String) async throws {
        guard let passwordData = password.data(using: .utf8), passwordData.count <= 64 else {
            throw ProtocolError.invalidPayload
        }

        var payload = Data()

        // Target public key (32 bytes)
        payload.append(contact.publicKey)

        // Password length (1 byte)
        payload.append(UInt8(passwordData.count))

        // Password (variable length, max 64)
        payload.append(passwordData)

        // Create frame and send
        let frame = ProtocolFrame(code: CommandCode.sendCommand.rawValue, payload: payload)
        try await send(frame: frame.encode())

        // Wait for LOGIN_SUCCESS or LOGIN_FAIL push notification
        let result = try await waitForMultiFrameResponse(
            codes: [PushCode.loginSuccess.rawValue, PushCode.loginFail.rawValue],
            timeout: 10.0,
        )

        if result.code == PushCode.loginFail.rawValue {
            logger.error("Login failed for contact: \(contact.name)")
            throw AuthenticationError.loginFailed
        }

        logger.info("Login successful for contact: \(contact.name)")
    }

    /// Send logout to repeater/sensor
    func logout(from contact: ContactData) async throws {
        let payload = contact.publicKey // Just the 32-byte public key

        let frame = ProtocolFrame(code: CommandCode.sendCommand.rawValue, payload: payload)
        _ = try await sendCommand(frame, expectingResponse: ResponseCode.ok.rawValue)

        logger.info("Logged out from contact: \(contact.name)")
    }

    // MARK: - Access Control List (ACL) Management

    /// CMD_REQ_ACL (35): Request access control list from repeater
    func requestACL(from contact: ContactData) async throws -> [ACLEntry] {
        let payload = contact.publicKey // 32-byte target public key

        let frame = ProtocolFrame(code: CommandCode.requestACL.rawValue, payload: payload)
        try await send(frame: frame.encode())

        // Wait for ACL response (likely a push code or multi-part response)
        // Note: Actual response format needs verification from device
        let response = try await waitForResponse(code: ResponseCode.ok.rawValue, timeout: 10.0)

        // Decode ACL entries
        return try ACLEntry.decodeList(from: response.payload)
    }

    /// Set permission for contact on repeater
    func setPermission(
        on repeater: ContactData,
        for contact: ContactData,
        permission: UInt8,
    ) async throws {
        // Construct "setperm <pubkey> <perm>" command
        let command = "setperm \(contact.publicKey.hexString) \(permission)"

        guard let commandData = command.data(using: .utf8) else {
            throw ProtocolError.invalidPayload
        }

        var payload = Data()
        payload.append(repeater.publicKey) // Target repeater (32 bytes)
        payload.append(commandData) // Command text

        let frame = ProtocolFrame(code: CommandCode.sendCommand.rawValue, payload: payload)
        _ = try await sendCommand(frame, expectingResponse: ResponseCode.ok.rawValue)

        logger.info("Set permission \(permission) for \(contact.name) on \(repeater.name)")
    }
}

public enum AuthenticationError: LocalizedError {
    case loginFailed
    case notAuthenticated
    case passwordRequired

    public var errorDescription: String? {
        switch self {
        case .loginFailed: "Login failed - invalid password"
        case .notAuthenticated: "Not authenticated - login required"
        case .passwordRequired: "Password required for this operation"
        }
    }
}
