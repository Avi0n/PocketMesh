@preconcurrency import Combine
import Foundation

/// Mock BLE Manager for testing (conforms to existing BLEManagerProtocol)
public final class MockBLEManager: BLEManagerProtocol {
    private let radio: MockBLERadio
    public let (frameStream, frameContinuation) = AsyncStream<Data>.makeStream(
        bufferingPolicy: .bufferingNewest(10)
    )
    private var frameSubscriptionTask: Task<Void, Never>?

    // Keep for backward compatibility during transition
    private let frameSubject = PassthroughSubject<Data, Never>()
    public var framePublisher: AnyPublisher<Data, Never> {
        frameSubject.eraseToAnyPublisher()
    }

    public init(radio: MockBLERadio) {
        self.radio = radio

        // Subscribe to RX notifications using AsyncStream
        self.frameSubscriptionTask = Task {
            for await frame in radio.rxNotifications {
                // Send via AsyncStream
                frameContinuation.yield(frame)

                // Also send via Combine for backward compatibility
                frameSubject.send(frame)
            }
        }
    }

    deinit {
        frameSubscriptionTask?.cancel()
        // Properly clean up AsyncStream continuation
        frameContinuation.finish()
    }

    @preconcurrency
    public func send(frame: Data) async throws {
        // Get the TX characteristic (nonisolated property)
        let txChar = radio.txCharacteristic
        let peripheral = await radio.peripheral

        try await peripheral.writeValue(frame, for: txChar, type: .withoutResponse)
    }

    /// Access to underlying radio for test control
    public func getRadio() -> MockBLERadio {
        radio
    }
}
