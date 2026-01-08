import Foundation
import Network
import os

/// Errors that can occur during WiFi transport operations.
public enum WiFiTransportError: Error, Sendable, Equatable {
    case connectionFailed(String)
    case connectionTimeout
    case notConnected
    case sendFailed(String)
    case invalidHost
    case invalidPort
    case notConfigured
}

/// TCP transport for connecting to MeshCore devices over WiFi.
///
/// Configure connection info before calling `connect()`:
/// ```swift
/// let transport = WiFiTransport()
/// await transport.setConnectionInfo(host: "192.168.1.50", port: 5000)
/// try await transport.connect()
/// ```
public actor WiFiTransport: MeshTransport {

    private let logger = Logger(subsystem: "MeshCore", category: "WiFiTransport")

    private var connection: NWConnection?
    private var frameDecoder = WiFiFrameDecoder()

    // AsyncStream created in init, matching BLETransport pattern
    private let dataStream: AsyncStream<Data>
    private let dataContinuation: AsyncStream<Data>.Continuation

    private var _isConnected = false

    // Connection configuration (set before connect())
    private var configuredHost: String?
    private var configuredPort: UInt16?

    // Thread-safe continuation state (protects against multiple resumes)
    private var connectContinuation: CheckedContinuation<Void, Error>?

    // MARK: - Configuration

    /// Connection timeout duration
    public static let connectionTimeout: Duration = .seconds(10)

    /// Write timeout duration
    public static let writeTimeout: Duration = .seconds(5)

    // MARK: - MeshTransport Protocol

    public var receivedData: AsyncStream<Data> {
        dataStream
    }

    public var isConnected: Bool {
        _isConnected
    }

    public init() {
        // Create stream in init, matching BLETransport pattern
        let (stream, continuation) = AsyncStream<Data>.makeStream()
        self.dataStream = stream
        self.dataContinuation = continuation
    }

    /// Configures the connection target. Must be called before `connect()`.
    public func setConnectionInfo(host: String, port: UInt16) {
        self.configuredHost = host
        self.configuredPort = port
    }

    /// Establishes a TCP connection to the configured host and port.
    /// Call `setConnectionInfo(host:port:)` first.
    public func connect() async throws {
        guard let host = configuredHost, let port = configuredPort else {
            throw WiFiTransportError.notConfigured
        }

        logger.info("Connecting to \(host):\(port)")

        let hostEndpoint = NWEndpoint.Host(host)
        guard let portEndpoint = NWEndpoint.Port(rawValue: port) else {
            throw WiFiTransportError.invalidPort
        }

        let endpoint = NWEndpoint.hostPort(host: hostEndpoint, port: portEndpoint)
        let parameters = NWParameters.tcp

        let newConnection = NWConnection(to: endpoint, using: parameters)
        connection = newConnection

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Store continuation for safe one-time resume
            self.connectContinuation = continuation

            newConnection.stateUpdateHandler = { [weak self] state in
                Task { [weak self] in
                    await self?.handleStateChange(state)
                }
            }

            newConnection.start(queue: .global(qos: .userInitiated))
        }

        startReceiving()
    }

    public func disconnect() async {
        logger.info("Disconnecting")
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        _isConnected = false
        frameDecoder.reset()
        dataContinuation.finish()

        // Clear any pending continuation
        if let continuation = connectContinuation {
            continuation.resume(throwing: WiFiTransportError.connectionFailed("Disconnected"))
            connectContinuation = nil
        }
    }

    public func send(_ data: Data) async throws {
        guard let connection, _isConnected else {
            throw WiFiTransportError.notConnected
        }

        let frame = WiFiFrameCodec.encode(data)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: frame, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: WiFiTransportError.sendFailed(error.localizedDescription))
                } else {
                    continuation.resume()
                }
            })
        }
    }

    // MARK: - Private

    /// Handles NWConnection state changes with safe one-time continuation resume.
    private func handleStateChange(_ state: NWConnection.State) {
        switch state {
        case .ready:
            logger.info("Connection ready")
            _isConnected = true
            // Safe one-time resume: consume and nil the continuation
            if let continuation = connectContinuation {
                connectContinuation = nil
                continuation.resume()
            }

        case .failed(let error):
            logger.error("Connection failed: \(error.localizedDescription)")
            _isConnected = false
            // Safe one-time resume: consume and nil the continuation
            if let continuation = connectContinuation {
                connectContinuation = nil
                continuation.resume(throwing: WiFiTransportError.connectionFailed(error.localizedDescription))
            }

        case .cancelled:
            logger.info("Connection cancelled")
            _isConnected = false

        case .waiting(let error):
            logger.warning("Connection waiting: \(error.localizedDescription)")
            // For invalid addresses, the connection goes to waiting state with an error
            // Treat this as a connection failure
            _isConnected = false
            if let continuation = connectContinuation {
                connectContinuation = nil
                continuation.resume(throwing: WiFiTransportError.connectionFailed(error.localizedDescription))
            }

        default:
            break
        }
    }

    private func startReceiving() {
        guard let connection else { return }

        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            Task { [weak self] in
                guard let self else { return }

                if let data = content {
                    await self.processReceivedData(data)
                }

                if let error {
                    await self.logger.error("Receive error: \(error.localizedDescription)")
                    return
                }

                if !isComplete {
                    await self.startReceiving()
                }
            }
        }
    }

    private func processReceivedData(_ data: Data) {
        let frames = frameDecoder.decode(data)
        for frame in frames {
            dataContinuation.yield(frame)
        }
    }
}
