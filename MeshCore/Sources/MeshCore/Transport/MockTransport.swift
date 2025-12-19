import Foundation

/// Mock transport for unit testing
/// Allows simulating device responses without real BLE hardware
public actor MockTransport: MeshTransport {
    public var sentData: [Data] = []

    private let dataStream: AsyncStream<Data>
    private let dataContinuation: AsyncStream<Data>.Continuation

    public var receivedData: AsyncStream<Data> { dataStream }
    public private(set) var isConnected = false

    public init() {
        let (stream, continuation) = AsyncStream.makeStream(of: Data.self)
        self.dataStream = stream
        self.dataContinuation = continuation
    }

    public func connect() async throws {
        isConnected = true
    }

    public func disconnect() async {
        isConnected = false
        dataContinuation.finish()
    }

    public func send(_ data: Data) async throws {
        guard isConnected else {
            throw MeshTransportError.notConnected
        }
        sentData.append(data)
    }

    /// Simulate receiving data from the device
    public func simulateReceive(_ data: Data) {
        dataContinuation.yield(data)
    }

    /// Simulate receiving a parsed event (builds the raw packet)
    public func simulateOK(value: UInt32? = nil) {
        var data = Data([ResponseCode.ok.rawValue])
        if let value = value {
            data.append(contentsOf: withUnsafeBytes(of: value.littleEndian) { Array($0) })
        }
        simulateReceive(data)
    }

    /// Simulate an error response
    public func simulateError(code: UInt8) {
        simulateReceive(Data([ResponseCode.error.rawValue, code]))
    }

    /// Clear sent data history
    public func clearSentData() {
        sentData.removeAll()
    }
}
