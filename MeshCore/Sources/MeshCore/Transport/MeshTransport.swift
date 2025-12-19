import Foundation

/// Protocol for MeshCore transport implementations.
///
/// `MeshTransport` defines the interface for communication with a MeshCore device.
/// Implement this protocol to support different transport mechanisms (e.g., Bluetooth LE,
/// Serial, TCP/IP).
///
/// ## Built-in Implementations
///
/// - ``BLETransport``: Bluetooth Low Energy transport for iOS/macOS
/// - ``MockTransport``: In-memory transport for testing
///
/// ## Custom Implementations
///
/// To create a custom transport:
///
/// ```swift
/// actor MyTransport: MeshTransport {
///     private var continuation: AsyncStream<Data>.Continuation?
///     private var _isConnected = false
///
///     var isConnected: Bool { _isConnected }
///
///     var receivedData: AsyncStream<Data> {
///         AsyncStream { continuation in
///             self.continuation = continuation
///         }
///     }
///
///     func connect() async throws {
///         // Establish connection
///         _isConnected = true
///     }
///
///     func disconnect() async {
///         continuation?.finish()
///         _isConnected = false
///     }
///
///     func send(_ data: Data) async throws {
///         guard _isConnected else {
///             throw MeshTransportError.notConnected
///         }
///         // Send data over your transport
///     }
///
///     // Call when data is received from the device
///     func didReceive(_ data: Data) {
///         continuation?.yield(data)
///     }
/// }
/// ```
///
/// ## Thread Safety
///
/// Implementations must be `Sendable`. Using an `actor` is recommended for complex
/// state management, though simpler implementations can use other concurrency-safe patterns.
public protocol MeshTransport: Sendable {
    /// Connects to the MeshCore device.
    ///
    /// This method should establish the underlying transport connection and prepare
    /// for data exchange. It should throw if the connection cannot be established.
    ///
    /// - Throws: ``MeshTransportError`` if the connection fails.
    func connect() async throws

    /// Disconnects from the device.
    ///
    /// This method should cleanly close the transport connection and release resources.
    /// It should be safe to call multiple times.
    func disconnect() async

    /// Sends data to the device.
    ///
    /// - Parameter data: The raw bytes to send.
    /// - Throws: ``MeshTransportError/notConnected`` if not connected.
    ///           ``MeshTransportError/sendFailed(_:)`` if the send fails.
    func send(_ data: Data) async throws

    /// An async stream of data received from the device.
    ///
    /// This stream yields raw data packets as they are received from the device.
    /// The stream ends when the connection is closed.
    var receivedData: AsyncStream<Data> { get async }

    /// Whether the transport is currently connected.
    var isConnected: Bool { get async }
}
