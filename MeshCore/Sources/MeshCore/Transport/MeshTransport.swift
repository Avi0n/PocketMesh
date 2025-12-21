import Foundation

/// Defines the interface for communicating with a MeshCore device across various physical layers.
///
/// `MeshTransport` serves as a primary extensibility point for the MeshCore library, allowing
/// different transport mechanisms (such as Bluetooth Low Energy, Serial, or TCP/IP) to be
/// plugged into a ``MeshCoreSession``.
///
/// ## Built-in Implementations
///
/// - ``BLETransport``: Bluetooth Low Energy transport for iOS and macOS.
/// - ``MockTransport``: In-memory transport for unit testing and simulation.
///
/// ## Custom Implementations
///
/// To support a new physical layer, implement this protocol in a thread-safe manner (ideally using an `actor`):
///
/// ```swift
/// actor MyCustomTransport: MeshTransport {
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
///         // Establish connection to the hardware
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
///         // Write data to the physical medium
///     }
///
///     // Internal helper to bridge hardware callbacks to the stream
///     func handleIncomingData(_ data: Data) {
///         continuation?.yield(data)
///     }
/// }
/// ```
///
/// ## Thread Safety
///
/// Implementations must conform to `Sendable`. Using an `actor` is the recommended way to
/// manage internal state and ensure concurrency safety in a modern Swift environment.
public protocol MeshTransport: Sendable {
    /// Establishes a connection to the MeshCore device.
    ///
    /// This method initializes the underlying physical layer and prepares the transport
    /// for data exchange.
    ///
    /// - Throws: A ``MeshTransportError`` if the connection cannot be established or if
    ///   the hardware is unavailable.
    func connect() async throws

    /// Terminates the connection to the device.
    ///
    /// Cleans up resources, closes the physical connection, and finishes the `receivedData` stream.
    /// This method is idempotent and safe to call even if already disconnected.
    func disconnect() async

    /// Transmits raw data to the connected MeshCore device.
    ///
    /// - Parameter data: The raw bytes to be sent over the transport.
    /// - Throws:
    ///   - ``MeshTransportError/notConnected`` if called while the transport is disconnected.
    ///   - ``MeshTransportError/sendFailed(_:)`` if the underlying physical layer fails to transmit.
    func send(_ data: Data) async throws

    /// Provides an asynchronous stream of raw data received from the device.
    ///
    /// Each element in the stream represents a discrete chunk of data received from the
    /// physical layer. The stream terminates when the transport is disconnected.
    ///
    /// - Returns: An `AsyncStream` yielding `Data` objects.
    var receivedData: AsyncStream<Data> { get async }

    /// Indicates whether the transport is currently connected to a device.
    ///
    /// This property should accurately reflect the status of the underlying physical connection.
    var isConnected: Bool { get async }
}
