import Foundation
import os

/// Main session actor for MeshCore device communication.
///
/// `MeshCoreSession` coordinates all communication with a MeshCore mesh networking device
/// over a transport layer (typically Bluetooth LE). It provides high-level APIs for:
///
/// - **Connection management**: Start and stop device sessions
/// - **Contact discovery**: Query and manage the device's contact list
/// - **Messaging**: Send and receive messages to/from mesh contacts
/// - **Device configuration**: Set device name, coordinates, radio parameters
/// - **Telemetry**: Request sensor data and device statistics
///
/// ## Usage
///
/// ```swift
/// // Create a session with a transport
/// let transport = BLETransport(peripheral: peripheral)
/// let session = MeshCoreSession(transport: transport)
///
/// // Connect and start the session
/// try await session.start()
///
/// // Get contacts from the device
/// let contacts = try await session.getContacts()
///
/// // Send a message to a contact
/// if let contact = contacts.first {
///     let result = try await session.sendMessage(
///         to: contact.publicKey,
///         text: "Hello from Swift!"
///     )
/// }
///
/// // Stop when done
/// await session.stop()
/// ```
///
/// ## Event Streaming
///
/// Subscribe to device events using the async event stream:
///
/// ```swift
/// Task {
///     for await event in await session.events() {
///         switch event {
///         case .contactMessageReceived(let msg):
///             print("Message: \(msg.text)")
///         case .advertisement(let publicKey):
///             print("Saw advertisement from \(publicKey.hexString)")
///         default:
///             break
///         }
///     }
/// }
/// ```
///
/// ## Thread Safety
///
/// `MeshCoreSession` is an actor, ensuring all operations are serialized and thread-safe.
/// All public methods are async and can be called safely from any context.
///
/// ## Testing
///
/// Inject a custom `Clock` to control timing in tests:
///
/// ```swift
/// let testClock = TestClock()
/// let session = MeshCoreSession(
///     transport: MockTransport(),
///     clock: testClock
/// )
/// ```
public actor MeshCoreSession: MeshCoreSessionProtocol {

    // MARK: - Properties

    private let logger = Logger(subsystem: "MeshCore", category: "Session")

    private let transport: any MeshTransport
    private let configuration: SessionConfiguration
    private let clock: any Clock<Duration>
    private let dispatcher = EventDispatcher()
    private let pendingRequests = PendingRequests()
    private let binaryRequestSerializer = BinaryRequestSerializer()

    // State
    private var contactManager = ContactManager()
    private var selfInfo: SelfInfo?
    private var cachedTime: Date?

    /// Returns the device's self info after session start.
    ///
    /// This is populated after `start()` completes successfully.
    public var currentSelfInfo: SelfInfo? { selfInfo }
    private var isRunning = false
    private var receiveTask: Task<Void, Never>?
    private var autoMessageFetchTask: Task<Void, Never>?
    private var isAutoFetchingMessages = false

    // MARK: - Connection State

    private var _connectionState: ConnectionState = .disconnected
    private var connectionStateContinuations: [UUID: AsyncStream<ConnectionState>.Continuation] = [:]

    /// Provides an observable connection state stream for UI binding.
    ///
    /// The stream yields the current state immediately upon subscription,
    /// and then yields subsequent state changes as they occur.
    public var connectionState: AsyncStream<ConnectionState> {
        AsyncStream { continuation in
            let id = UUID()
            // Yield current state immediately
            continuation.yield(_connectionState)
            // Store continuation for future updates
            Task { await self.addConnectionStateContinuation(id: id, continuation: continuation) }
            continuation.onTermination = { _ in
                Task { await self.removeConnectionStateContinuation(id: id) }
            }
        }
    }

    private func addConnectionStateContinuation(id: UUID, continuation: AsyncStream<ConnectionState>.Continuation) {
        connectionStateContinuations[id] = continuation
    }

    private func removeConnectionStateContinuation(id: UUID) {
        connectionStateContinuations.removeValue(forKey: id)
    }

    private func updateConnectionState(_ state: ConnectionState) {
        _connectionState = state
        for continuation in connectionStateContinuations.values {
            continuation.yield(state)
        }
    }

    // MARK: - Lifecycle

    /// Creates a new MeshCore session.
    ///
    /// The session is created in a disconnected state. Call ``start()`` to connect
    /// to the device and begin communication.
    ///
    /// - Parameters:
    ///   - transport: The transport layer for device communication (e.g., ``BLETransport``).
    ///   - configuration: Session configuration options. Defaults to ``SessionConfiguration/default``.
    ///   - clock: The clock for timing operations. Defaults to `ContinuousClock` for production use.
    ///            Inject a test clock for deterministic testing of timeouts.
    public init(
        transport: any MeshTransport,
        configuration: SessionConfiguration = .default,
        clock: (any Clock<Duration>)? = nil
    ) {
        self.transport = transport
        self.configuration = configuration
        self.clock = clock ?? ContinuousClock()
    }

    /// Connects to the device and starts the session.
    ///
    /// This method performs the following steps:
    /// 1. Connects via the transport layer
    /// 2. Sends the `appStart` command to initialize communication
    /// 3. Receives device self-info (public key, name, capabilities)
    /// 4. Starts the background receive loop for incoming data
    ///
    /// The session becomes ready for use after this method returns successfully.
    /// Subscribe to events via ``events()`` to receive incoming messages and notifications.
    ///
    /// - Throws: ``MeshTransportError`` if the transport connection fails.
    ///           ``MeshCoreError/timeout`` if the device doesn't respond to appStart.
    public func start() async throws {
        // Guard against being called multiple times
        if isRunning {
            logger.warning("Session already running - skipping redundant start()")
            return
        }

        logger.info("Starting MeshCore session...")
        updateConnectionState(.connecting)
        do {
            try await transport.connect()
        } catch {
            updateConnectionState(.failed(error as? MeshTransportError ?? .connectionFailed(error.localizedDescription)))
            throw error
        }
        isRunning = true
        updateConnectionState(.connected)

        // Start receiving data with weak self to prevent retain cycle
        receiveTask = Task { [weak self] in
            guard let self else { return }
            await self.receiveLoop()
        }

        // Send appstart
        selfInfo = try await sendAppStart()
        logger.info("MeshCore session started")
    }

    /// Stops the session and disconnects from the device.
    ///
    /// This method is safe to call multiple times. It cancels all pending operations,
    /// stops the receive loop, and closes the transport connection.
    ///
    /// After calling this method, the session cannot be reused. Create a new session
    /// to reconnect.
    public func stop() async {
        logger.info("Stopping MeshCore session...")
        isRunning = false
        receiveTask?.cancel()
        await transport.disconnect()
        updateConnectionState(.disconnected)
        logger.info("MeshCore session stopped")
    }

    // MARK: - Events

    /// Subscribes to all events from the device.
    ///
    /// Each subscriber receives all events independently. Supports bounded buffering of up to 100 events.
    ///
    /// - Returns: An async stream of mesh events that yields ``MeshEvent`` values as they are received.
    public func events() async -> AsyncStream<MeshEvent> {
        await dispatcher.subscribe()
    }

    // MARK: - Contact Management

    /// Returns the currently cached contacts.
    ///
    /// This property returns contacts from the local cache without making a device request.
    /// Use ``getContacts(since:)`` or ``ensureContacts(force:)`` to refresh from the device.
    public var cachedContacts: [MeshContact] {
        contactManager.cachedContacts
    }

    /// Returns pending contacts awaiting confirmation.
    ///
    /// These are contacts that have been discovered but not yet added to the device's
    /// contact list. Use ``addContact(_:)`` to add them permanently.
    public var cachedPendingContacts: [MeshContact] {
        contactManager.cachedPendingContacts
    }

    /// Returns the last known device time.
    ///
    /// This is updated when the device reports its current time. Returns `nil` if
    /// the time has not been queried. Use ``getTime()`` to explicitly request it.
    public var deviceTime: Date? { cachedTime }

    /// Finds a contact by advertised name.
    ///
    /// - Parameters:
    ///   - name: The name to search for.
    ///   - exactMatch: If `true`, requires exact match. If `false`, uses case-insensitive
    ///                 localized search (default).
    /// - Returns: The matching contact, or `nil` if not found.
    public func getContactByName(_ name: String, exactMatch: Bool = false) -> MeshContact? {
        contactManager.getByName(name, exactMatch: exactMatch)
    }

    /// Removes and returns a pending contact.
    ///
    /// - Parameter publicKey: The hex string of the contact's public key.
    /// - Returns: The removed contact, or `nil` if not found in pending contacts.
    public func popPendingContact(publicKey: String) -> MeshContact? {
        contactManager.popPending(publicKey: publicKey)
    }

    /// Removes all pending contacts from the cache.
    public func flushPendingContacts() {
        contactManager.flushPending()
    }

    /// Finds a contact by public key prefix (hex string).
    ///
    /// - Parameter prefix: The hex string prefix to match (e.g., "a1b2c3").
    /// - Returns: The matching contact, or `nil` if not found.
    public func getContactByKeyPrefix(_ prefix: String) -> MeshContact? {
        contactManager.getByKeyPrefix(prefix)
    }

    /// Finds a contact by public key prefix (raw data).
    ///
    /// - Parameter prefix: The raw bytes of the public key prefix to match.
    /// - Returns: The matching contact, or `nil` if not found.
    public func getContactByKeyPrefix(_ prefix: Data) -> MeshContact? {
        contactManager.getByKeyPrefix(prefix)
    }

    /// Indicates whether the contact cache needs refreshing.
    ///
    /// Returns `true` if contacts have been modified since the last fetch,
    /// or if the cache has never been populated.
    public var isContactsDirty: Bool { contactManager.needsRefresh }

    /// Enables or disables automatic contact updates.
    ///
    /// When enabled, the session automatically refreshes contacts when it
    /// receives advertisements or path updates from the device.
    ///
    /// - Parameter enabled: Whether to enable auto-updates.
    public func setAutoUpdateContacts(_ enabled: Bool) {
        contactManager.setAutoUpdate(enabled)
    }

    /// Ensures contacts are loaded, fetching from device if needed.
    ///
    /// - Parameter force: If `true`, always fetches from device. If `false`,
    ///                    uses cached contacts if available and not dirty.
    /// - Returns: The current contacts.
    /// - Throws: ``MeshCoreError`` if the fetch fails.
    public func ensureContacts(force: Bool = false) async throws -> [MeshContact] {
        if force || contactManager.needsRefresh || contactManager.isEmpty {
            return try await getContacts(since: contactManager.contactsLastModified)
        }
        return cachedContacts
    }

    // MARK: - Auto Message Fetching

    /// Starts automatic message fetching.
    ///
    /// When enabled, the session automatically fetches pending messages from the
    /// device whenever it receives a `messagesWaiting` notification.
    ///
    /// Call ``stopAutoMessageFetching()`` to disable.
    public func startAutoMessageFetching() async {
        guard !isAutoFetchingMessages else { return }
        isAutoFetchingMessages = true
        
        autoMessageFetchTask = Task { [weak self] in
            guard let self else { return }
            await self.autoMessageFetchLoop()
        }

        // The auto-fetch loop polls messages in response to messagesWaiting events.
        // For immediate polling, callers should use getMessage() or consume the events directly.
    }

    /// Stops automatic message fetching.
    ///
    /// Call this to disable the automatic fetching started by ``startAutoMessageFetching()``.
    public func stopAutoMessageFetching() {
        isAutoFetchingMessages = false
        autoMessageFetchTask?.cancel()
        autoMessageFetchTask = nil
    }

    private func autoMessageFetchLoop() async {
        for await event in await dispatcher.subscribe() {
            guard isAutoFetchingMessages else { break }

            if case .messagesWaiting = event {
                do {
                    while isAutoFetchingMessages {
                        let result = try await getMessage()
                        if case .noMoreMessages = result { break }
                        try await Task.sleep(for: .milliseconds(100))
                    }
                } catch {
                    logger.debug("Auto message fetch error: \(error.localizedDescription)")
                }
            }
        }
    }

    // MARK: - Event Waiting

    /// Waits for a specific event type with optional filtering.
    ///
    /// Prefer ``sendAndWait(_:matching:timeout:)`` for command/response patterns to avoid race conditions.
    ///
    /// - Parameters:
    ///   - predicate: A closure that returns `true` for the event you're waiting for.
    ///   - timeout: Maximum time to wait in seconds. Uses `configuration.defaultTimeout` if `nil`.
    /// - Returns: The matching event, or `nil` if timeout occurred.
    public func waitForEvent(
        matching predicate: @escaping @Sendable (MeshEvent) -> Bool,
        timeout: TimeInterval? = nil
    ) async -> MeshEvent? {
        let effectiveTimeout = timeout ?? configuration.defaultTimeout

        return await withTaskGroup(of: MeshEvent?.self) { group in
            group.addTask {
                for await event in await self.events() {
                    if Task.isCancelled { return nil }
                    if predicate(event) {
                        return event
                    }
                }
                return nil
            }

            group.addTask { [clock = self.clock] in
                try? await clock.sleep(for: .seconds(effectiveTimeout))
                return nil
            }

            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    /// Waits for an event matching an ``EventFilter`` with timeout.
    ///
    /// This method subscribes to events using a filtered subscription for efficiency,
    /// then waits for the first matching event or timeout.
    ///
    /// - Parameters:
    ///   - filter: The event filter to apply.
    ///   - timeout: Maximum time to wait. Uses `configuration.defaultTimeout` if `nil`.
    /// - Returns: The matching event, or `nil` if timeout occurred.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Wait for acknowledgement with specific code
    /// let filter = EventFilter.acknowledgement(code: expectedAck)
    /// if let event = await session.waitForEvent(filter: filter, timeout: 10.0) {
    ///     print("Received acknowledgement")
    /// }
    /// ```
    public func waitForEvent(
        filter: EventFilter,
        timeout: TimeInterval? = nil
    ) async -> MeshEvent? {
        let effectiveTimeout = timeout ?? configuration.defaultTimeout

        return await withTaskGroup(of: MeshEvent?.self) { group in
            group.addTask {
                // Use filtered subscription for efficiency
                let stream = await self.dispatcher.subscribe(filter: filter.matches)
                for await event in stream {
                    if Task.isCancelled { return nil }
                    // Event already passed filter, return immediately
                    return event
                }
                return nil
            }

            group.addTask { [clock = self.clock] in
                try? await clock.sleep(for: .seconds(effectiveTimeout))
                return nil
            }

            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    /// Sends a command and waits for a matching response.
    ///
    /// This method avoids race conditions by subscribing to events before sending the command.
    ///
    /// - Parameters:
    ///   - data: The command data to send.
    ///   - predicate: A closure that matches and extracts the desired result from an event.
    ///   - timeout: The maximum time to wait for a response. Defaults to `configuration.defaultTimeout`.
    /// - Returns: The extracted result of type `T`.
    /// - Throws: ``MeshCoreError/timeout`` if no matching event is received within the timeout.
    public func sendAndWait<T: Sendable>(
        _ data: Data,
        matching predicate: @escaping @Sendable (MeshEvent) -> T?,
        timeout: TimeInterval? = nil
    ) async throws -> T {
        let effectiveTimeout = timeout ?? configuration.defaultTimeout

        // Subscribe BEFORE sending to avoid race condition
        let events = await dispatcher.subscribe()

        // Send after subscribing
        try await transport.send(data)

        // Now wait for matching event
        return try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask {
                for await event in events {
                    if Task.isCancelled { return nil }
                    if let result = predicate(event) {
                        return result
                    }
                }
                return nil
            }

            group.addTask { [clock = self.clock] in
                try await clock.sleep(for: .seconds(effectiveTimeout))
                return nil
            }

            if let result = try await group.next() ?? nil {
                group.cancelAll()
                return result
            }
            group.cancelAll()
            throw MeshCoreError.timeout
        }
    }

    /// Sends a command and waits for either a success response or error.
    ///
    /// - Parameters:
    ///   - data: Command data to send.
    ///   - successPredicate: Predicate to match success events and extract result.
    ///   - timeout: Optional timeout override.
    /// - Returns: The extracted result on success.
    /// - Throws: ``MeshCoreError/deviceError(code:)`` on error response,
    ///           ``MeshCoreError/timeout`` on timeout.
    private func sendAndWaitWithError<T: Sendable>(
        _ data: Data,
        matching successPredicate: @escaping @Sendable (MeshEvent) -> T?,
        timeout: TimeInterval? = nil
    ) async throws -> T {
        let effectiveTimeout = timeout ?? configuration.defaultTimeout

        // Subscribe BEFORE sending to avoid race condition
        let events = await dispatcher.subscribe()

        // Send after subscribing
        try await transport.send(data)

        // Now wait for matching event
        return try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask {
                for await event in events {
                    if Task.isCancelled { return nil }
                    // Check for error response first
                    if case .error(let code) = event {
                        throw MeshCoreError.deviceError(code: code ?? 0)
                    }
                    if let result = successPredicate(event) {
                        return result
                    }
                }
                return nil
            }

            group.addTask { [clock = self.clock] in
                try await clock.sleep(for: .seconds(effectiveTimeout))
                return nil
            }

            if let result = try await group.next() ?? nil {
                group.cancelAll()
                return result
            }
            group.cancelAll()
            throw MeshCoreError.timeout
        }
    }

    // MARK: - Commands

    /// Sends the app-start command to initialize communication with the device.
    ///
    /// This is typically called automatically by ``start()``.
    ///
    /// - Returns: Information about the device itself.
    /// - Throws: ``MeshCoreError/timeout`` if the device doesn't respond.
    ///           ``MeshCoreError/deviceError(code:)`` if the device returns an error.
    public func sendAppStart() async throws -> SelfInfo {
        let data = PacketBuilder.appStart(clientId: configuration.clientIdentifier)
        return try await sendAndWaitWithError(data) { event in
            if case .selfInfo(let info) = event { return info }
            return nil
        }
    }

    /// Queries the device for its capabilities and system information.
    ///
    /// - Returns: Information about the device hardware, firmware, and supported features.
    /// - Throws: ``MeshCoreError/timeout`` if the device doesn't respond.
    ///           ``MeshCoreError/deviceError(code:)`` if the device returns an error.
    public func queryDevice() async throws -> DeviceCapabilities {
        let data = PacketBuilder.deviceQuery()
        return try await sendAndWaitWithError(data) { event in
            if case .deviceInfo(let info) = event { return info }
            return nil
        }
    }

    /// Retrieves the current battery status from the device.
    ///
    /// - Returns: Battery voltage and charge level information.
    /// - Throws: ``MeshCoreError/timeout`` if the device doesn't respond.
    ///           ``MeshCoreError/deviceError(code:)`` if the device returns an error.
    public func getBattery() async throws -> BatteryInfo {
        let data = PacketBuilder.getBattery()
        return try await sendAndWaitWithError(data) { event in
            if case .battery(let info) = event { return info }
            return nil
        }
    }

    /// Fetches contacts from the device.
    ///
    /// This method queries the device for its contact list, optionally filtering
    /// to contacts modified since a given date.
    ///
    /// - Parameter lastModified: If provided, only returns contacts modified after this date.
    ///                          Use `nil` to fetch all contacts.
    /// - Returns: Array of contacts from the device.
    /// - Throws: ``MeshCoreError/timeout`` if the device doesn't respond.
    ///           ``MeshCoreError/deviceError(code:)`` if the device returns an error.
    public func getContacts(since lastModified: Date? = nil) async throws -> [MeshContact] {
        let data = PacketBuilder.getContacts(since: lastModified)
        let events = await dispatcher.subscribe()
        try await transport.send(data)

        var receivedContacts: [MeshContact] = []

        for await event in events {
            switch event {
            case .contactsStart(let count):
                receivedContacts.reserveCapacity(count)
            case .contact(let contact):
                receivedContacts.append(contact)
                contactManager.store(contact)
            case .contactsEnd(let modifiedDate):
                contactManager.markClean(lastModified: modifiedDate)
                return receivedContacts
            case .error(let code):
                throw MeshCoreError.deviceError(code: code ?? 0)
            default:
                continue
            }
        }

        throw MeshCoreError.timeout
    }

    /// Sends a text message to a contact.
    ///
    /// - Parameters:
    ///   - destination: The destination public key (6+ bytes, uses first 6 as prefix).
    ///   - text: The message text to send.
    ///   - timestamp: Message timestamp. Defaults to current time.
    /// - Returns: Information about the sent message, including the expected ACK code.
    /// - Throws: ``MeshCoreError/timeout`` if no response.
    ///           ``MeshCoreError/deviceError(code:)`` on error.
    public func sendMessage(
        to destination: Data,
        text: String,
        timestamp: Date = Date()
    ) async throws -> MessageSentInfo {
        let data = PacketBuilder.sendMessage(to: destination, text: text, timestamp: timestamp)
        return try await sendAndWaitWithError(data) { event in
            if case .messageSent(let info) = event { return info }
            return nil
        }
    }

    /// Sends a text message to a destination.
    ///
    /// - Parameters:
    ///   - destination: The destination (contact or public key).
    ///   - text: The message text to send.
    ///   - timestamp: Message timestamp. Defaults to current time.
    /// - Returns: Information about the sent message, including the expected ACK code.
    /// - Throws: ``MeshCoreError`` on failure.
    public func sendMessage(
        to destination: Destination,
        text: String,
        timestamp: Date = Date()
    ) async throws -> MessageSentInfo {
        let publicKey = try destination.publicKey(prefixLength: 6)
        return try await sendMessage(to: publicKey, text: text, timestamp: timestamp)
    }

    /// Sends a message with automatic retry logic and optional path reset.
    ///
    /// This method attempts to send a message multiple times. If initial attempts fail,
    /// it can optionally reset the routing path to "flood" mode to increase delivery
    /// probability.
    ///
    /// - Parameters:
    ///   - destination: The full 32-byte public key of the recipient. A full key is
    ///                  required if path reset is enabled.
    ///   - text: The message text to send.
    ///   - timestamp: The message timestamp. Defaults to current time.
    ///   - maxAttempts: The maximum number of total attempts to make. Defaults to 3.
    ///   - floodAfter: The number of failed attempts after which to reset the path to flood.
    ///                 Defaults to 2.
    ///   - maxFloodAttempts: The maximum number of attempts to make while in flood mode.
    ///                       Defaults to 2.
    ///   - timeout: The acknowledgment timeout per attempt. If `nil`, uses the suggested
    ///              timeout provided by the device.
    /// - Returns: Information about the sent message if an acknowledgment was received,
    ///            otherwise `nil` if all attempts failed.
    /// - Throws: ``MeshCoreError/invalidInput`` if the destination key is not 32 bytes.
    public func sendMessageWithRetry(
        to destination: Data,
        text: String,
        timestamp: Date = Date(),
        maxAttempts: Int = 3,
        floodAfter: Int = 2,
        maxFloodAttempts: Int = 2,
        timeout: TimeInterval? = nil
    ) async throws -> MessageSentInfo? {
        guard destination.count >= 32 else {
            throw MeshCoreError.invalidInput("Full 32-byte public key required for retry with path reset")
        }

        var attempts = 0
        var floodAttempts = 0
        var isFloodMode = false

        while attempts < maxAttempts && (!isFloodMode || floodAttempts < maxFloodAttempts) {
            if attempts == floodAfter && !isFloodMode {
                logger.info("Resetting path to flood after \(attempts) failed attempts")
                do {
                    try await resetPath(publicKey: destination)
                    isFloodMode = true
                } catch {
                    logger.warning("Failed to reset path: \(error.localizedDescription), continuing...")
                }
            }

            if attempts > 0 {
                logger.info("Retry sending message: attempt \(attempts + 1)/\(maxAttempts)")
            }

            let sentInfo = try await sendMessage(to: destination.prefix(6), text: text, timestamp: timestamp)

            let ackTimeout = timeout ?? (Double(sentInfo.suggestedTimeoutMs) / 1000.0 * 1.2)
            let ackEvent = await waitForEvent(matching: { event in
                if case .acknowledgement(let code) = event {
                    return code == sentInfo.expectedAck
                }
                return false
            }, timeout: ackTimeout)

            if ackEvent != nil {
                logger.info("Message acknowledged on attempt \(attempts + 1)")
                return sentInfo
            }

            attempts += 1
            if isFloodMode {
                floodAttempts += 1
            }
        }

        logger.warning("Message delivery failed after \(attempts) attempts")
        return nil
    }

    /// Sends an advertisement broadcast.
    ///
    /// - Parameter flood: If `true`, the advertisement is broadcast using flood routing.
    /// - Throws: ``MeshCoreError/timeout`` or ``MeshCoreError/deviceError(code:)`` on failure.
    public func sendAdvertisement(flood: Bool = false) async throws {
        let data = PacketBuilder.sendAdvertisement(flood: flood)
        let _: Bool = try await sendAndWaitWithError(data) { event in
            if case .ok = event { return true }
            return nil
        }
    }

    /// Requests status information from a remote node using the binary protocol.
    ///
    /// - Parameter publicKey: The full 32-byte public key of the remote node.
    /// - Returns: A status response containing battery, uptime, and other metrics.
    /// - Throws: ``MeshCoreError/timeout`` if no response within the timeout period.
    ///           ``MeshCoreError/invalidResponse`` if an unexpected response is received.
    public func requestStatus(from publicKey: Data) async throws -> StatusResponse {
        // Serialize binary requests to prevent messageSent race conditions
        try await binaryRequestSerializer.withSerialization { [self] in
            try await performStatusRequest(from: publicKey)
        }
    }

    /// Internal implementation of status request, called within serialization.
    private func performStatusRequest(from publicKey: Data) async throws -> StatusResponse {
        let data = PacketBuilder.binaryRequest(to: publicKey, type: .status)
        let publicKeyPrefix = Data(publicKey.prefix(6))
        let effectiveTimeout = configuration.defaultTimeout

        // Subscribe BEFORE sending to avoid race condition where binaryResponse
        // arrives before we can register the pending request
        let events = await dispatcher.subscribe()

        // Send after subscribing
        try await transport.send(data)

        // Wait for messageSent (to get expectedAck) then binaryResponse (the actual response)
        return try await withThrowingTaskGroup(of: StatusResponse?.self) { group in
            group.addTask {
                var expectedAck: Data?

                for await event in events {
                    if Task.isCancelled { return nil }

                    switch event {
                    case .messageSent(let info):
                        // Capture the expectedAck from firmware's MSG_SENT response
                        expectedAck = info.expectedAck

                    case .binaryResponse(let tag, let responseData):
                        // Match by expectedAck (4-byte tag from firmware)
                        guard let expected = expectedAck, tag == expected else { continue }

                        guard let response = Parsers.StatusResponse.parseFromBinaryResponse(
                            responseData,
                            publicKeyPrefix: publicKeyPrefix
                        ) else {
                            return nil
                        }
                        return response

                    case .statusResponse(let response):
                        // Handle already-routed response (if routing happens elsewhere)
                        return response

                    default:
                        continue
                    }
                }
                return nil
            }

            group.addTask { [clock = self.clock] in
                try await clock.sleep(for: .seconds(effectiveTimeout))
                return nil
            }

            if let result = try await group.next() ?? nil {
                group.cancelAll()
                return result
            }
            group.cancelAll()
            throw MeshCoreError.timeout
        }
    }

    /// Requests status information from a remote node.
    ///
    /// - Parameter destination: The destination (contact or public key).
    /// - Returns: Status response from the remote node.
    /// - Throws: ``MeshCoreError`` on failure.
    public func requestStatus(from destination: Destination) async throws -> StatusResponse {
        let publicKey = try destination.fullPublicKey()
        return try await requestStatus(from: publicKey)
    }

    // MARK: - Device Configuration Commands

    /// Gets the current device time.
    ///
    /// - Returns: The device's current time.
    /// - Throws: ``MeshCoreError/timeout`` if the device doesn't respond.
    public func getTime() async throws -> Date {
        try await sendAndWait(PacketBuilder.getTime()) { event in
            if case .currentTime(let date) = event { return date }
            return nil
        }
    }

    /// Sets the device's current time.
    ///
    /// - Parameter date: The time to set on the device.
    /// - Throws: ``MeshCoreError/timeout`` or ``MeshCoreError/deviceError(code:)`` on failure.
    public func setTime(_ date: Date) async throws {
        try await sendSimpleCommand(PacketBuilder.setTime(date))
    }

    /// Sets the device's advertised name.
    ///
    /// - Parameter name: The name to advertise (max 32 bytes UTF-8).
    /// - Throws: ``MeshCoreError/timeout`` or ``MeshCoreError/deviceError(code:)`` on failure.
    public func setName(_ name: String) async throws {
        try await sendSimpleCommand(PacketBuilder.setName(name))
    }

    /// Sets the device's GPS coordinates.
    ///
    /// - Parameters:
    ///   - latitude: Latitude in degrees (-90 to 90).
    ///   - longitude: Longitude in degrees (-180 to 180).
    /// - Throws: ``MeshCoreError/timeout`` or ``MeshCoreError/deviceError(code:)`` on failure.
    public func setCoordinates(latitude: Double, longitude: Double) async throws {
        try await sendSimpleCommand(PacketBuilder.setCoordinates(latitude: latitude, longitude: longitude))
    }

    /// Sets the radio transmission power level.
    ///
    /// - Parameter power: Power level in dBm (device-specific range, typically 1-20).
    /// - Throws: ``MeshCoreError/timeout`` or ``MeshCoreError/deviceError(code:)`` on failure.
    public func setTxPower(_ power: Int) async throws {
        try await sendSimpleCommand(PacketBuilder.setTxPower(power))
    }

    /// Configures radio parameters for LoRa communication.
    ///
    /// - Parameters:
    ///   - frequency: Center frequency in MHz (e.g., 915.0).
    ///   - bandwidth: Signal bandwidth in kHz (e.g., 125.0, 250.0, 500.0).
    ///   - spreadingFactor: LoRa spreading factor (7-12, higher = longer range but slower).
    ///   - codingRate: Error correction coding rate (5-8).
    /// - Throws: ``MeshCoreError/timeout`` or ``MeshCoreError/deviceError(code:)`` on failure.
    public func setRadio(
        frequency: Double,
        bandwidth: Double,
        spreadingFactor: UInt8,
        codingRate: UInt8
    ) async throws {
        try await sendSimpleCommand(PacketBuilder.setRadio(
            frequency: frequency,
            bandwidth: bandwidth,
            spreadingFactor: spreadingFactor,
            codingRate: codingRate
        ))
    }

    /// Configures radio timing parameters for fine-tuning.
    ///
    /// - Parameters:
    ///   - rxDelay: Receive delay in microseconds.
    ///   - af: Auto-frequency correction parameter.
    /// - Throws: ``MeshCoreError/timeout`` or ``MeshCoreError/deviceError(code:)`` on failure.
    public func setTuning(rxDelay: UInt32, af: UInt32) async throws {
        try await sendSimpleCommand(PacketBuilder.setTuning(rxDelay: rxDelay, af: af))
    }

    /// Sets miscellaneous device parameters.
    ///
    /// This is a low-level command that sets all "other params" at once.
    /// Consider using granular setters like ``setManualAddContacts(_:)`` instead.
    ///
    /// - Parameters:
    ///   - manualAddContacts: Whether contacts require manual approval before adding.
    ///   - telemetryModeEnvironment: Environment telemetry reporting mode (0-3).
    ///   - telemetryModeLocation: Location telemetry reporting mode (0-3).
    ///   - telemetryModeBase: Base telemetry reporting mode (0-3).
    ///   - advertisementLocationPolicy: Location inclusion policy for advertisements.
    ///   - multiAcks: Number of acknowledgment retries.
    /// - Throws: ``MeshCoreError/timeout`` or ``MeshCoreError/deviceError(code:)`` on failure.
    public func setOtherParams(
        manualAddContacts: Bool,
        telemetryModeEnvironment: UInt8,
        telemetryModeLocation: UInt8,
        telemetryModeBase: UInt8,
        advertisementLocationPolicy: UInt8,
        multiAcks: UInt8? = nil
    ) async throws {
        try await sendSimpleCommand(PacketBuilder.setOtherParams(
            manualAddContacts: manualAddContacts,
            telemetryModeEnvironment: telemetryModeEnvironment,
            telemetryModeLocation: telemetryModeLocation,
            telemetryModeBase: telemetryModeBase,
            advertisementLocationPolicy: advertisementLocationPolicy,
            multiAcks: multiAcks
        ))
    }

    /// Sets the device PIN for administrative access.
    ///
    /// - Parameter pin: 4-digit PIN as a 32-bit unsigned integer.
    /// - Throws: ``MeshCoreError/timeout`` or ``MeshCoreError/deviceError(code:)`` on failure.
    public func setDevicePin(_ pin: UInt32) async throws {
        try await sendSimpleCommand(PacketBuilder.setDevicePin(pin))
    }

    // MARK: - Granular Device Configuration

    /// Sets the base telemetry mode (preserves other settings).
    ///
    /// Uses a read-modify-write pattern: reads current settings from `selfInfo`,
    /// modifies only the requested value, then writes all settings back.
    ///
    /// - Parameter mode: Telemetry mode value (0-3, higher bits are masked off).
    /// - Throws: ``MeshCoreError/sessionNotStarted`` if device info unavailable.
    public func setTelemetryModeBase(_ mode: UInt8) async throws {
        var config = try await currentOtherParams()
        config.telemetryModeBase = mode & 0b11
        try await applyOtherParams(config)
    }

    /// Sets the location telemetry mode (preserves other settings).
    ///
    /// - Parameter mode: Telemetry mode value (0-3).
    /// - Throws: ``MeshCoreError/sessionNotStarted`` if device info unavailable.
    public func setTelemetryModeLocation(_ mode: UInt8) async throws {
        var config = try await currentOtherParams()
        config.telemetryModeLocation = mode & 0b11
        try await applyOtherParams(config)
    }

    /// Sets the environment telemetry mode (preserves other settings).
    ///
    /// - Parameter mode: Telemetry mode value (0-3).
    /// - Throws: ``MeshCoreError/sessionNotStarted`` if device info unavailable.
    public func setTelemetryModeEnvironment(_ mode: UInt8) async throws {
        var config = try await currentOtherParams()
        config.telemetryModeEnvironment = mode & 0b11
        try await applyOtherParams(config)
    }

    /// Sets the manual add contacts mode (preserves other settings).
    ///
    /// When enabled, contacts discovered via advertisement must be manually approved
    /// before being added to the device's contact list.
    ///
    /// - Parameter enabled: Whether contacts must be manually approved.
    /// - Throws: ``MeshCoreError/sessionNotStarted`` if device info unavailable.
    public func setManualAddContacts(_ enabled: Bool) async throws {
        var config = try await currentOtherParams()
        config.manualAddContacts = enabled
        try await applyOtherParams(config)
    }

    /// Sets the multi-acks count (preserves other settings).
    ///
    /// - Parameter count: Number of acknowledgment retries.
    /// - Throws: ``MeshCoreError/sessionNotStarted`` if device info unavailable.
    public func setMultiAcks(_ count: UInt8) async throws {
        var config = try await currentOtherParams()
        config.multiAcks = count
        try await applyOtherParams(config)
    }

    /// Sets the advertisement location policy (preserves other settings).
    ///
    /// - Parameter policy: Location advertising policy value.
    /// - Throws: ``MeshCoreError/sessionNotStarted`` if device info unavailable.
    public func setAdvertisementLocationPolicy(_ policy: UInt8) async throws {
        var config = try await currentOtherParams()
        config.advertisementLocationPolicy = policy
        try await applyOtherParams(config)
    }

    /// Returns the current device configuration from selfInfo.
    ///
    /// - Returns: Current other params configuration.
    /// - Throws: ``MeshCoreError/sessionNotStarted`` if selfInfo unavailable after refresh.
    private func currentOtherParams() async throws -> OtherParamsConfig {
        if let info = selfInfo {
            return OtherParamsConfig(from: info)
        }

        // Refresh selfInfo if not available
        selfInfo = try await sendAppStart()
        guard let info = selfInfo else {
            throw MeshCoreError.sessionNotStarted
        }
        return OtherParamsConfig(from: info)
    }

    /// Applies other params configuration to device.
    private func applyOtherParams(_ config: OtherParamsConfig) async throws {
        try await setOtherParams(
            manualAddContacts: config.manualAddContacts,
            telemetryModeEnvironment: config.telemetryModeEnvironment,
            telemetryModeLocation: config.telemetryModeLocation,
            telemetryModeBase: config.telemetryModeBase,
            advertisementLocationPolicy: config.advertisementLocationPolicy,
            multiAcks: config.multiAcks
        )

        // Refresh selfInfo to keep cache consistent
        selfInfo = try await sendAppStart()
    }

    /// Reboots the device.
    ///
    /// Sends a reboot command to the device. The session will be disconnected.
    /// You must create a new session after the device restarts.
    ///
    /// - Throws: ``MeshTransportError`` if the command cannot be sent.
    public func reboot() async throws {
        try await transport.send(PacketBuilder.reboot())
    }

    /// Retrieves telemetry data from the device.
    ///
    /// - Returns: Device telemetry including battery, temperature, and sensor data.
    /// - Throws: ``MeshCoreError/timeout`` if the device doesn't respond.
    public func getSelfTelemetry() async throws -> TelemetryResponse {
        try await sendAndWait(PacketBuilder.getSelfTelemetry()) { event in
            if case .telemetryResponse(let response) = event { return response }
            return nil
        }
    }

    /// Retrieves all custom variables stored on the device.
    ///
    /// - Returns: Dictionary mapping variable names to values.
    /// - Throws: ``MeshCoreError/timeout`` if the device doesn't respond.
    public func getCustomVars() async throws -> [String: String] {
        try await sendAndWait(PacketBuilder.getCustomVars()) { event in
            if case .customVars(let vars) = event { return vars }
            return nil
        }
    }

    /// Sets a custom variable on the device.
    ///
    /// - Parameters:
    ///   - key: Variable name (max 32 bytes).
    ///   - value: Variable value (max 256 bytes).
    /// - Throws: ``MeshCoreError/timeout`` or ``MeshCoreError/deviceError(code:)`` on failure.
    public func setCustomVar(key: String, value: String) async throws {
        try await sendSimpleCommand(PacketBuilder.setCustomVar(key: key, value: value))
    }

    /// Exports the device's private key.
    ///
    /// This is a sensitive operation that exposes the device's cryptographic identity.
    /// The exported key can be imported into another device to clone its identity.
    ///
    /// - Returns: The 32-byte private key, or `nil` if export is disabled.
    /// - Throws: ``MeshCoreError/timeout`` if the device doesn't respond.
    public func exportPrivateKey() async throws -> Data {
        try await sendAndWait(PacketBuilder.exportPrivateKey()) { event in
            if case .privateKey(let key) = event { return key }
            if case .disabled = event { return nil }
            return nil
        }
    }

    /// Imports a private key into the device.
    ///
    /// This replaces the device's cryptographic identity. Use with caution.
    ///
    /// - Parameter key: The 32-byte private key to import.
    /// - Throws: ``MeshCoreError/timeout`` or ``MeshCoreError/deviceError(code:)`` on failure.
    public func importPrivateKey(_ key: Data) async throws {
        try await sendSimpleCommand(PacketBuilder.importPrivateKey(key))
    }

    // MARK: - Stats Commands

    /// Retrieves core device statistics.
    ///
    /// - Returns: Core statistics including uptime and system metrics.
    /// - Throws: ``MeshCoreError/timeout`` if the device doesn't respond.
    public func getStatsCore() async throws -> CoreStats {
        try await sendAndWait(PacketBuilder.getStatsCore()) { event in
            if case .statsCore(let stats) = event { return stats }
            return nil
        }
    }

    /// Retrieves radio statistics.
    ///
    /// - Returns: Radio statistics including RSSI, SNR, and transmission counts.
    /// - Throws: ``MeshCoreError/timeout`` if the device doesn't respond.
    public func getStatsRadio() async throws -> RadioStats {
        try await sendAndWait(PacketBuilder.getStatsRadio()) { event in
            if case .statsRadio(let stats) = event { return stats }
            return nil
        }
    }

    /// Retrieves packet statistics.
    ///
    /// - Returns: Packet statistics including sent, received, and dropped counts.
    /// - Throws: ``MeshCoreError/timeout`` if the device doesn't respond.
    public func getStatsPackets() async throws -> PacketStats {
        try await sendAndWait(PacketBuilder.getStatsPackets()) { event in
            if case .statsPackets(let stats) = event { return stats }
            return nil
        }
    }

    // MARK: - Contact Commands

    /// Resets the routing path for a contact.
    ///
    /// Clears the stored path, forcing the device to rediscover the route.
    /// This can help resolve routing issues or adapt to network changes.
    ///
    /// - Parameter publicKey: The full 32-byte public key of the contact.
    /// - Throws: ``MeshCoreError/timeout`` or ``MeshCoreError/deviceError(code:)`` on failure.
    public func resetPath(publicKey: Data) async throws {
        try await sendSimpleCommand(PacketBuilder.resetPath(publicKey: publicKey))
    }

    /// Removes a contact from the device's contact list.
    ///
    /// - Parameter publicKey: The full 32-byte public key of the contact to remove.
    /// - Throws: ``MeshCoreError/timeout`` or ``MeshCoreError/deviceError(code:)`` on failure.
    public func removeContact(publicKey: Data) async throws {
        try await sendSimpleCommand(PacketBuilder.removeContact(publicKey: publicKey))
    }

    /// Shares a contact with nearby devices via broadcast.
    ///
    /// Broadcasts the contact's information to other mesh nodes, allowing them
    /// to add it to their contact lists if desired.
    ///
    /// - Parameter publicKey: The full 32-byte public key of the contact to share.
    /// - Throws: ``MeshCoreError/timeout`` or ``MeshCoreError/deviceError(code:)`` on failure.
    public func shareContact(publicKey: Data) async throws {
        try await sendSimpleCommand(PacketBuilder.shareContact(publicKey: publicKey))
    }

    /// Exports a contact as a shareable URI string.
    ///
    /// - Parameter publicKey: The contact's public key, or `nil` to export self.
    /// - Returns: A URI string encoding the contact information.
    /// - Throws: ``MeshCoreError/timeout`` if the device doesn't respond.
    public func exportContact(publicKey: Data? = nil) async throws -> String {
        try await sendAndWait(PacketBuilder.exportContact(publicKey: publicKey)) { event in
            if case .contactURI(let uri) = event { return uri }
            return nil
        }
    }

    /// Imports a contact from encoded contact card data.
    ///
    /// - Parameter cardData: The contact card data (typically from a QR code or URI).
    /// - Throws: ``MeshCoreError/timeout`` or ``MeshCoreError/deviceError(code:)`` on failure.
    public func importContact(cardData: Data) async throws {
        var data = Data([CommandCode.importContact.rawValue])
        data.append(cardData)
        try await sendSimpleCommand(data)
    }

    /// Updates or creates a contact with full details.
    ///
    /// This is a low-level method that sets all contact fields. Consider using
    /// higher-level methods like ``addContact(_:)``, ``changeContactPath(_:path:)``,
    /// or ``changeContactFlags(_:flags:)`` instead.
    ///
    /// - Parameters:
    ///   - publicKey: The full 32-byte public key.
    ///   - type: Contact type identifier.
    ///   - flags: Contact flags for capabilities and permissions.
    ///   - outPathLength: Length of the outbound path, or -1 for flood.
    ///   - outPath: The routing path (up to 64 bytes).
    ///   - advertisedName: The contact's advertised name.
    ///   - lastAdvertisement: Timestamp of last received advertisement.
    ///   - latitude: GPS latitude in degrees.
    ///   - longitude: GPS longitude in degrees.
    /// - Throws: ``MeshCoreError/timeout`` or ``MeshCoreError/deviceError(code:)`` on failure.
    public func updateContact(
        publicKey: Data,
        type: UInt8,
        flags: UInt8,
        outPathLength: Int8,
        outPath: Data,
        advertisedName: String,
        lastAdvertisement: Date,
        latitude: Double,
        longitude: Double
    ) async throws {
        var data = Data([CommandCode.updateContact.rawValue])
        data.append(publicKey.prefix(32))
        data.append(type)
        data.append(flags)
        data.append(UInt8(bitPattern: outPathLength))

        var pathData = outPath.prefix(64)
        while pathData.count < 64 {
            pathData.append(0)
        }
        data.append(pathData)

        var nameData = (advertisedName.data(using: .utf8) ?? Data()).prefix(32)
        while nameData.count < 32 {
            nameData.append(0)
        }
        data.append(nameData)

        let lastAdvert = UInt32(lastAdvertisement.timeIntervalSince1970)
        data.append(contentsOf: withUnsafeBytes(of: lastAdvert.littleEndian) { Array($0) })

        let lat = Int32(latitude * 1_000_000)
        let lon = Int32(longitude * 1_000_000)
        data.append(contentsOf: withUnsafeBytes(of: lat.littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: lon.littleEndian) { Array($0) })

        try await sendSimpleCommand(data)
    }

    /// Adds a contact to the device's contact list.
    ///
    /// - Parameter contact: The contact to add.
    /// - Throws: ``MeshCoreError/timeout`` or ``MeshCoreError/deviceError(code:)`` on failure.
    public func addContact(_ contact: MeshContact) async throws {
        try await updateContact(
            publicKey: contact.publicKey,
            type: contact.type,
            flags: contact.flags,
            outPathLength: contact.outPathLength,
            outPath: contact.outPath,
            advertisedName: contact.advertisedName,
            lastAdvertisement: contact.lastAdvertisement,
            latitude: contact.latitude,
            longitude: contact.longitude
        )
    }

    /// Changes the routing path for a contact.
    ///
    /// Updates only the path while preserving all other contact information.
    ///
    /// - Parameters:
    ///   - contact: The contact to modify.
    ///   - path: The new routing path, or empty data to reset to flood.
    /// - Throws: ``MeshCoreError/timeout`` or ``MeshCoreError/deviceError(code:)`` on failure.
    public func changeContactPath(_ contact: MeshContact, path: Data) async throws {
        let pathLength: Int8 = path.isEmpty ? -1 : Int8(min(path.count, 64))
        try await updateContact(
            publicKey: contact.publicKey,
            type: contact.type,
            flags: contact.flags,
            outPathLength: pathLength,
            outPath: path,
            advertisedName: contact.advertisedName,
            lastAdvertisement: contact.lastAdvertisement,
            latitude: contact.latitude,
            longitude: contact.longitude
        )
    }

    /// Changes the flags for a contact.
    ///
    /// Updates only the flags while preserving all other contact information.
    ///
    /// - Parameters:
    ///   - contact: The contact to modify.
    ///   - flags: The new flags value.
    /// - Throws: ``MeshCoreError/timeout`` or ``MeshCoreError/deviceError(code:)`` on failure.
    public func changeContactFlags(_ contact: MeshContact, flags: UInt8) async throws {
        try await updateContact(
            publicKey: contact.publicKey,
            type: contact.type,
            flags: flags,
            outPathLength: contact.outPathLength,
            outPath: contact.outPath,
            advertisedName: contact.advertisedName,
            lastAdvertisement: contact.lastAdvertisement,
            latitude: contact.latitude,
            longitude: contact.longitude
        )
    }

    // MARK: - Messaging Commands

    /// Fetches the next pending message from the device.
    ///
    /// Returns one message at a time from the device's message queue. Call repeatedly
    /// until `.noMoreMessages` is returned to drain the queue.
    /// Use ``startAutoMessageFetching()`` to automate this process.
    ///
    /// - Returns: A ``MessageResult`` containing either a contact message, channel message,
    ///            or indication that no more messages are waiting.
    /// - Throws: ``MeshCoreError`` if the fetch fails.
    public func getMessage() async throws -> MessageResult {
        let data = PacketBuilder.getMessage()
        let events = await dispatcher.subscribe()
        try await transport.send(data)

        for await event in events {
            switch event {
            case .contactMessageReceived(let msg):
                return .contactMessage(msg)
            case .channelMessageReceived(let msg):
                return .channelMessage(msg)
            case .noMoreMessages:
                return .noMoreMessages
            case .error(let code):
                throw MeshCoreError.deviceError(code: code ?? 0)
            default:
                continue
            }
        }
        throw MeshCoreError.timeout
    }

    /// Sends a command message to a remote node.
    ///
    /// Commands are special messages that trigger actions on the remote device.
    ///
    /// - Parameters:
    ///   - destination: The destination public key (6+ bytes, uses first 6 as prefix).
    ///   - command: The command string to send.
    ///   - timestamp: Message timestamp. Defaults to current time.
    /// - Returns: Information about the sent message, including the expected ACK code.
    /// - Throws: ``MeshCoreError/timeout`` if the device doesn't respond.
    public func sendCommand(
        to destination: Data,
        command: String,
        timestamp: Date = Date()
    ) async throws -> MessageSentInfo {
        try await sendAndWait(PacketBuilder.sendCommand(to: destination, command: command, timestamp: timestamp)) { event in
            if case .messageSent(let info) = event { return info }
            return nil
        }
    }

    /// Sends a message to a channel.
    ///
    /// Channel messages are broadcast to all nodes with the same channel configuration.
    ///
    /// - Parameters:
    ///   - channel: Channel index (0-255).
    ///   - text: The message text to send.
    ///   - timestamp: Message timestamp. Defaults to current time.
    /// - Throws: ``MeshCoreError/timeout`` or ``MeshCoreError/deviceError(code:)`` on failure.
    public func sendChannelMessage(
        channel: UInt8,
        text: String,
        timestamp: Date = Date()
    ) async throws {
        try await sendSimpleCommand(PacketBuilder.sendChannelMessage(channel: channel, text: text, timestamp: timestamp))
    }

    /// Sends a login request to a remote node.
    ///
    /// Authenticates with a password-protected node to gain administrative access.
    ///
    /// - Parameters:
    ///   - destination: The node's public key (6+ bytes).
    ///   - password: The authentication password.
    /// - Returns: Information about the sent message, including the expected ACK code.
    /// - Throws: ``MeshCoreError/timeout`` if the device doesn't respond.
    public func sendLogin(to destination: Data, password: String) async throws -> MessageSentInfo {
        try await sendAndWait(PacketBuilder.sendLogin(to: destination, password: password)) { event in
            if case .messageSent(let info) = event { return info }
            return nil
        }
    }

    /// Sends a login request to a remote node.
    ///
    /// - Parameters:
    ///   - destination: The destination (contact or public key).
    ///   - password: The authentication password.
    /// - Returns: Information about the sent message.
    /// - Throws: ``MeshCoreError`` on failure.
    public func sendLogin(to destination: Destination, password: String) async throws -> MessageSentInfo {
        let publicKey = try destination.fullPublicKey()
        return try await sendLogin(to: publicKey, password: password)
    }

    /// Sends a logout request to a remote node.
    ///
    /// Terminates an authenticated session with a remote node.
    ///
    /// - Parameter destination: The node's public key (6+ bytes).
    /// - Throws: ``MeshCoreError/timeout`` or ``MeshCoreError/deviceError(code:)`` on failure.
    public func sendLogout(to destination: Data) async throws {
        try await sendSimpleCommand(PacketBuilder.sendLogout(to: destination))
    }

    /// Requests status information from a remote node.
    ///
    /// - Parameter destination: The node's public key (6+ bytes).
    /// - Returns: Information about the sent message, including the expected ACK code.
    /// - Throws: ``MeshCoreError/timeout`` if the device doesn't respond.
    public func sendStatusRequest(to destination: Data) async throws -> MessageSentInfo {
        try await sendAndWait(PacketBuilder.sendStatusRequest(to: destination)) { event in
            if case .messageSent(let info) = event { return info }
            return nil
        }
    }

    /// Requests telemetry data from a remote node.
    ///
    /// - Parameter destination: The node's public key (6+ bytes).
    /// - Returns: Information about the sent message, including the expected ACK code.
    /// - Throws: ``MeshCoreError/timeout`` if the device doesn't respond.
    public func sendTelemetryRequest(to destination: Data) async throws -> MessageSentInfo {
        try await sendAndWait(PacketBuilder.getSelfTelemetry(destination: destination)) { event in
            if case .messageSent(let info) = event { return info }
            return nil
        }
    }

    /// Initiates path discovery to a remote node.
    ///
    /// Triggers route discovery to find or refresh the path to a destination.
    ///
    /// - Parameter destination: The node's public key (6+ bytes).
    /// - Returns: Information about the sent message, including the expected ACK code.
    /// - Throws: ``MeshCoreError/timeout`` if the device doesn't respond.
    public func sendPathDiscovery(to destination: Data) async throws -> MessageSentInfo {
        try await sendAndWait(PacketBuilder.sendPathDiscovery(to: destination)) { event in
            if case .messageSent(let info) = event { return info }
            return nil
        }
    }

    /// Sends a trace packet through the mesh network.
    ///
    /// Trace packets record the path they traverse, useful for network debugging.
    ///
    /// - Parameters:
    ///   - tag: Optional trace identifier. Random value generated if nil.
    ///   - authCode: Optional authentication code. Random value generated if nil.
    ///   - flags: Trace flags controlling behavior.
    ///   - path: Optional initial path to follow.
    /// - Returns: Information about the sent message, including tag and auth code.
    /// - Throws: ``MeshCoreError/timeout`` if the device doesn't respond.
    public func sendTrace(
        tag: UInt32? = nil,
        authCode: UInt32? = nil,
        flags: UInt8 = 0,
        path: Data? = nil
    ) async throws -> MessageSentInfo {
        let actualTag = tag ?? UInt32.random(in: 1...UInt32.max)
        let actualAuth = authCode ?? UInt32.random(in: 1...UInt32.max)

        return try await sendAndWait(PacketBuilder.sendTrace(tag: actualTag, authCode: actualAuth, flags: flags, path: path)) { event in
            if case .messageSent(let info) = event { return info }
            return nil
        }
    }

    /// Sets the flood scope using a raw scope key.
    ///
    /// The flood scope limits broadcast flooding to nodes with matching scope.
    ///
    /// - Parameter scopeKey: The 32-byte scope key.
    /// - Throws: ``MeshCoreError/timeout`` or ``MeshCoreError/deviceError(code:)`` on failure.
    public func setFloodScope(scopeKey: Data) async throws {
        try await sendSimpleCommand(PacketBuilder.setFloodScope(scopeKey))
    }

    /// Sets the flood scope using a ``FloodScope`` enum.
    ///
    /// - Parameter scope: The flood scope to set.
    /// - Throws: ``MeshCoreError/timeout`` or ``MeshCoreError/deviceError(code:)`` on failure.
    public func setFloodScope(_ scope: FloodScope) async throws {
        try await setFloodScope(scopeKey: scope.scopeKey())
    }

    // MARK: - Channel Commands

    /// Retrieves configuration for a channel.
    ///
    /// - Parameter index: Channel index (0-255).
    /// - Returns: Channel information including name and secret.
    /// - Throws: ``MeshCoreError/timeout`` if the device doesn't respond.
    public func getChannel(index: UInt8) async throws -> ChannelInfo {
        try await sendAndWait(PacketBuilder.getChannel(index: index)) { event in
            if case .channelInfo(let info) = event { return info }
            return nil
        }
    }

    /// Configures a channel with name and secret.
    ///
    /// - Parameters:
    ///   - index: Channel index (0-255).
    ///   - name: Channel name.
    ///   - secret: The 32-byte channel secret key for encryption.
    /// - Throws: ``MeshCoreError/timeout`` or ``MeshCoreError/deviceError(code:)`` on failure.
    public func setChannel(index: UInt8, name: String, secret: Data) async throws {
        try await sendSimpleCommand(PacketBuilder.setChannel(index: index, name: name, secret: secret))
    }

    /// Configures a channel with automatic secret derivation.
    ///
    /// - Parameters:
    ///   - index: Channel index (0-255).
    ///   - name: Channel name.
    ///   - secret: Secret derivation strategy. Defaults to deriving from name.
    /// - Throws: ``MeshCoreError/timeout`` or ``MeshCoreError/deviceError(code:)`` on failure.
    public func setChannel(index: UInt8, name: String, secret: ChannelSecret = .deriveFromName) async throws {
        let secretData = secret.secretData(channelName: name)
        try await setChannel(index: index, name: name, secret: secretData)
    }

    // MARK: - Binary Protocol Commands

    /// Requests telemetry data from a remote node using binary protocol.
    ///
    /// This uses the binary protocol for more efficient data transfer than text commands.
    ///
    /// - Parameter publicKey: The full 32-byte public key of the remote node.
    /// - Returns: Telemetry response containing sensor data and device status.
    /// - Throws: ``MeshCoreError/timeout`` if no response within timeout period.
    ///           ``MeshCoreError/invalidResponse`` if unexpected response received.
    public func requestTelemetry(from publicKey: Data) async throws -> TelemetryResponse {
        // Serialize binary requests to prevent messageSent race conditions
        try await binaryRequestSerializer.withSerialization { [self] in
            try await performTelemetryRequest(from: publicKey)
        }
    }

    /// Internal implementation of telemetry request, called within serialization.
    private func performTelemetryRequest(from publicKey: Data) async throws -> TelemetryResponse {
        let data = PacketBuilder.binaryRequest(to: publicKey, type: .telemetry)
        let publicKeyPrefix = Data(publicKey.prefix(6))
        let effectiveTimeout = configuration.defaultTimeout

        // Subscribe BEFORE sending to avoid race condition where binaryResponse
        // arrives before we can register the pending request
        let events = await dispatcher.subscribe()

        // Send after subscribing
        try await transport.send(data)

        // Wait for messageSent (to get expectedAck) then binaryResponse (the actual response)
        return try await withThrowingTaskGroup(of: TelemetryResponse?.self) { group in
            group.addTask {
                var expectedAck: Data?

                for await event in events {
                    if Task.isCancelled { return nil }

                    switch event {
                    case .messageSent(let info):
                        // Capture the expectedAck from firmware's MSG_SENT response
                        expectedAck = info.expectedAck

                    case .binaryResponse(let tag, let responseData):
                        // Match by expectedAck (4-byte tag from firmware)
                        guard let expected = expectedAck, tag == expected else { continue }

                        let response = Parsers.TelemetryResponse.parseFromBinaryResponse(
                            responseData,
                            publicKeyPrefix: publicKeyPrefix
                        )
                        return response

                    case .telemetryResponse(let response):
                        // Handle already-routed response (if routing happens elsewhere)
                        return response

                    default:
                        continue
                    }
                }
                return nil
            }

            group.addTask { [clock = self.clock] in
                try await clock.sleep(for: .seconds(effectiveTimeout))
                return nil
            }

            if let result = try await group.next() ?? nil {
                group.cancelAll()
                return result
            }
            group.cancelAll()
            throw MeshCoreError.timeout
        }
    }

    /// Requests telemetry data from a destination.
    ///
    /// - Parameter destination: The destination (contact or public key).
    /// - Returns: Telemetry response from the remote node.
    /// - Throws: ``MeshCoreError`` on failure.
    public func requestTelemetry(from destination: Destination) async throws -> TelemetryResponse {
        let publicKey = try destination.fullPublicKey()
        return try await requestTelemetry(from: publicKey)
    }

    /// Requests Min-Max-Average (MMA) data for a time range.
    ///
    /// Retrieves aggregated sensor data statistics from a remote node.
    ///
    /// - Parameters:
    ///   - publicKey: The full 32-byte public key of the remote node.
    ///   - start: Start of the time range.
    ///   - end: End of the time range.
    /// - Returns: MMA response containing aggregated statistics.
    /// - Throws: ``MeshCoreError/timeout`` if no response within timeout period.
    ///           ``MeshCoreError/invalidResponse`` if unexpected response received.
    public func requestMMA(from publicKey: Data, start: Date, end: Date) async throws -> MMAResponse {
        var payload = Data()
        let startTimestamp = UInt32(start.timeIntervalSince1970)
        let endTimestamp = UInt32(end.timeIntervalSince1970)
        payload.append(contentsOf: withUnsafeBytes(of: startTimestamp.littleEndian) { Array($0) })
        payload.append(contentsOf: withUnsafeBytes(of: endTimestamp.littleEndian) { Array($0) })
        payload.append(contentsOf: [0, 0])

        let data = PacketBuilder.binaryRequest(to: publicKey, type: .mma, payload: payload)

        // Send and wait for MSG_SENT to get expected_ack
        let sentInfo: MessageSentInfo = try await sendAndWait(data) { event in
            if case .messageSent(let info) = event { return info }
            return nil
        }

        // Register with expected_ack as the tag for routing
        let result = await pendingRequests.register(
            tag: sentInfo.expectedAck,
            requestType: .mma,
            publicKeyPrefix: Data(publicKey.prefix(6)),
            timeout: configuration.defaultTimeout
        )

        guard let event = result else {
            throw MeshCoreError.timeout
        }

        if case .mmaResponse(let response) = event {
            return response
        }

        throw MeshCoreError.invalidResponse(expected: "mmaResponse", got: String(describing: event))
    }

    /// Requests the Access Control List (ACL) from a remote node.
    ///
    /// Retrieves the list of authorized public keys for administrative access.
    ///
    /// - Parameter publicKey: The full 32-byte public key of the remote node.
    /// - Returns: ACL response containing authorized public keys.
    /// - Throws: ``MeshCoreError/timeout`` if no response within timeout period.
    ///           ``MeshCoreError/invalidResponse`` if unexpected response received.
    public func requestACL(from publicKey: Data) async throws -> ACLResponse {
        let payload = Data([0, 0])
        let data = PacketBuilder.binaryRequest(to: publicKey, type: .acl, payload: payload)

        // Send and wait for MSG_SENT to get expected_ack
        let sentInfo: MessageSentInfo = try await sendAndWait(data) { event in
            if case .messageSent(let info) = event { return info }
            return nil
        }

        // Register with expected_ack as the tag for routing
        let result = await pendingRequests.register(
            tag: sentInfo.expectedAck,
            requestType: .acl,
            publicKeyPrefix: Data(publicKey.prefix(6)),
            timeout: configuration.defaultTimeout
        )

        guard let event = result else {
            throw MeshCoreError.timeout
        }

        if case .aclResponse(let response) = event {
            return response
        }

        throw MeshCoreError.invalidResponse(expected: "aclResponse", got: String(describing: event))
    }

    /// Requests the neighbor list from a remote node.
    ///
    /// Retrieves information about nodes that the remote device can directly communicate with.
    ///
    /// - Parameters:
    ///   - publicKey: The full 32-byte public key of the remote node.
    ///   - count: Maximum number of neighbors to return (default 255).
    ///   - offset: Starting offset for pagination (default 0).
    ///   - orderBy: Sort order (0 = by RSSI, default).
    ///   - pubkeyPrefixLength: Length of public key prefix to include (default 4).
    /// - Returns: Neighbors response containing list of adjacent nodes.
    /// - Throws: ``MeshCoreError/timeout`` if no response within timeout period.
    ///           ``MeshCoreError/invalidResponse`` if unexpected response received.
    public func requestNeighbours(
        from publicKey: Data,
        count: UInt8 = 255,
        offset: UInt16 = 0,
        orderBy: UInt8 = 0,
        pubkeyPrefixLength: UInt8 = 4
    ) async throws -> NeighboursResponse {
        var payload = Data()
        payload.append(0) // version
        payload.append(count)
        payload.append(contentsOf: withUnsafeBytes(of: offset.littleEndian) { Array($0) })
        payload.append(orderBy)
        payload.append(pubkeyPrefixLength)
        let randomTag = UInt32.random(in: 1...UInt32.max)
        payload.append(contentsOf: withUnsafeBytes(of: randomTag.littleEndian) { Array($0) })

        let data = PacketBuilder.binaryRequest(to: publicKey, type: .neighbours, payload: payload)

        // Send and wait for MSG_SENT to get expected_ack
        let sentInfo: MessageSentInfo = try await sendAndWait(data) { event in
            if case .messageSent(let info) = event { return info }
            return nil
        }

        // Register with expected_ack as the tag for routing, store prefixLength in context
        let result = await pendingRequests.register(
            tag: sentInfo.expectedAck,
            requestType: .neighbours,
            publicKeyPrefix: Data(publicKey.prefix(6)),
            timeout: configuration.defaultTimeout,
            context: ["prefixLength": Int(pubkeyPrefixLength)]
        )

        guard let event = result else {
            throw MeshCoreError.timeout
        }

        if case .neighboursResponse(let response) = event {
            return response
        }

        throw MeshCoreError.invalidResponse(expected: "neighboursResponse", got: String(describing: event))
    }

    /// Fetches all neighbors from a remote node with automatic pagination.
    ///
    /// This is a convenience method that automatically handles pagination to retrieve
    /// the complete neighbor list, making multiple requests if necessary.
    ///
    /// - Parameters:
    ///   - publicKey: The full 32-byte public key of the remote node.
    ///   - orderBy: Sort order (0 = by RSSI, default).
    ///   - pubkeyPrefixLength: Length of public key prefix to include (default 4).
    /// - Returns: Complete neighbors response with all neighbors.
    /// - Throws: ``MeshCoreError/timeout`` or ``MeshCoreError/invalidResponse`` on failure.
    public func fetchAllNeighbours(
        from publicKey: Data,
        orderBy: UInt8 = 0,
        pubkeyPrefixLength: UInt8 = 4
    ) async throws -> NeighboursResponse {
        var allNeighbours: [Neighbour] = []
        var offset: UInt16 = 0
        var totalCount = 0

        repeat {
            let response = try await requestNeighbours(
                from: publicKey,
                count: 255,
                offset: offset,
                orderBy: orderBy,
                pubkeyPrefixLength: pubkeyPrefixLength
            )

            totalCount = response.totalCount
            allNeighbours.append(contentsOf: response.neighbours)
            offset = UInt16(allNeighbours.count)

        } while allNeighbours.count < totalCount

        return NeighboursResponse(
            publicKeyPrefix: publicKey.prefix(6),
            tag: Data(),
            totalCount: totalCount,
            neighbours: allNeighbours
        )
    }

    // MARK: - Signing Commands

    /// Begins a signing operation.
    ///
    /// Initiates a multi-step signing process. After calling this, send data chunks
    /// with ``signData(_:)``, then finalize with ``signFinish(timeout:)``.
    ///
    /// - Returns: Maximum data size that can be signed in bytes.
    /// - Throws: ``MeshCoreError/timeout`` if the device doesn't respond.
    public func signStart() async throws -> Int {
        try await sendAndWait(PacketBuilder.signStart()) { event in
            if case .signStart(let maxLength) = event { return maxLength }
            return nil
        }
    }

    /// Sends a data chunk for signing.
    ///
    /// Must be called after ``signStart()`` and before ``signFinish(timeout:)``.
    ///
    /// - Parameter chunk: Data chunk to sign (typically up to 120 bytes).
    /// - Throws: ``MeshCoreError/timeout`` or ``MeshCoreError/deviceError(code:)`` on failure.
    public func signData(_ chunk: Data) async throws {
        try await sendSimpleCommand(PacketBuilder.signData(chunk))
    }

    /// Finalizes signing and retrieves the signature.
    ///
    /// Completes the signing operation started with ``signStart()`` after all
    /// data chunks have been sent with ``signData(_:)``.
    ///
    /// - Parameter timeout: Optional timeout override. Defaults to 3x default timeout.
    /// - Returns: The cryptographic signature (typically 64 bytes).
    /// - Throws: ``MeshCoreError/timeout`` if the device doesn't respond.
    public func signFinish(timeout: TimeInterval? = nil) async throws -> Data {
        let effectiveTimeout = timeout ?? (configuration.defaultTimeout * 3)
        return try await sendAndWait(PacketBuilder.signFinish(), matching: { event in
            if case .signature(let sig) = event { return sig }
            return nil
        }, timeout: effectiveTimeout)
    }

    /// Signs data using the device's private key.
    ///
    /// Handles the complete signing workflow: starts signing, sends data in chunks, and retrieves signature.
    ///
    /// - Parameters:
    ///   - data: The data to sign.
    ///   - chunkSize: Size of each chunk in bytes (default 120).
    ///   - timeout: Optional timeout for the finalization step.
    /// - Returns: The cryptographic signature.
    /// - Throws: ``MeshCoreError/dataTooLarge`` if data exceeds device limits.
    ///           ``MeshCoreError/timeout`` if any step times out.
    public func sign(_ data: Data, chunkSize: Int = 120, timeout: TimeInterval? = nil) async throws -> Data {
        let maxLength = try await signStart()

        guard data.count <= maxLength else {
            throw MeshCoreError.dataTooLarge(maxSize: maxLength, actualSize: data.count)
        }

        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            let chunk = data[offset..<end]
            try await signData(Data(chunk))
            offset = end
        }

        return try await signFinish(timeout: timeout)
    }

    // MARK: - Control Data Commands

    /// Sends control data to the mesh network.
    ///
    /// Control data packets are used for network-level operations and diagnostics.
    ///
    /// - Parameters:
    ///   - type: Control data type identifier.
    ///   - payload: The control data payload.
    /// - Throws: ``MeshCoreError/timeout`` or ``MeshCoreError/deviceError(code:)`` on failure.
    public func sendControlData(type: UInt8, payload: Data) async throws {
        try await sendSimpleCommand(PacketBuilder.sendControlData(type: type, payload: payload))
    }

    /// Sends a node discovery request to the mesh network.
    ///
    /// Broadcasts a request for nodes matching the filter criteria to respond.
    ///
    /// - Parameters:
    ///   - filter: Filter criteria for node types.
    ///   - prefixOnly: If `true`, only include public key prefixes in responses.
    ///   - tag: Optional request tag for correlation. Random value generated if nil.
    ///   - since: Optional timestamp to filter nodes seen since this time.
    /// - Returns: The tag used for this request (for correlating responses).
    /// - Throws: ``MeshCoreError/timeout`` or ``MeshCoreError/deviceError(code:)`` on failure.
    public func sendNodeDiscoverRequest(
        filter: UInt8,
        prefixOnly: Bool = true,
        tag: UInt32? = nil,
        since: Date? = nil
    ) async throws -> UInt32 {
        let actualTag = tag ?? UInt32.random(in: 1...UInt32.max)
        let sinceTimestamp = since.map { UInt32($0.timeIntervalSince1970) }
        let data = PacketBuilder.sendNodeDiscoverRequest(
            filter: filter,
            prefixOnly: prefixOnly,
            tag: actualTag,
            since: sinceTimestamp
        )
        try await sendSimpleCommand(data)
        return actualTag
    }

    /// Performs a factory reset on the device.
    ///
    /// This will erase all device configuration, contacts, and messages.
    /// The device will reboot and return to factory defaults.
    ///
    /// - Warning: This operation is irreversible.
    /// - Throws: ``MeshCoreError/timeout`` or ``MeshCoreError/deviceError(code:)`` on failure.
    public func factoryReset() async throws {
        try await sendSimpleCommand(PacketBuilder.factoryReset())
    }

    // MARK: - Private

    /// Sends a command and waits for an "OK" response from the device.
    private func sendSimpleCommand(_ data: Data) async throws {
        let _: Bool = try await sendAndWaitWithError(data) { event in
            if case .ok = event { return true }
            return nil
        }
    }

    /// The background loop for receiving data from the transport.
    private func receiveLoop() async {
        for await data in await transport.receivedData {
            await handleReceivedData(data)
        }
        // Stream ended - transport disconnected
        await dispatcher.dispatch(.connectionStateChanged(.disconnected))
        updateConnectionState(.disconnected)
        isRunning = false
    }

    /// Handles raw data received from the device.
    private func handleReceivedData(_ data: Data) async {
        var event = PacketParser.parse(data)

        if case .parseFailure(_, let reason) = event {
            logger.warning("Failed to parse packet: \(data.hexString) - \(reason)")
        } else {
            logger.debug("Received event: \(String(describing: event))")
        }

        // Route generic binary response to typed event based on pending request
        if case .binaryResponse(let tag, let responseData) = event {
            if let typedEvent = await routeGenericBinaryResponse(tag: tag, data: responseData) {
                event = typedEvent
                logger.debug("Routed binary response to typed event: \(String(describing: event))")
            }
        }

        trackContactChanges(event: event)
        await routeBinaryResponse(event: event)
        await dispatcher.dispatch(event)
    }

    /// Routes a generic binary response to a typed event based on pending request type.
    private func routeGenericBinaryResponse(tag: Data, data: Data) async -> MeshEvent? {
        guard let (requestType, publicKeyPrefix, context) = await pendingRequests.getBinaryRequestInfo(tag: tag) else {
            return nil
        }

        switch requestType {
        case .mma:
            let entries = MMAParser.parse(data)
            return .mmaResponse(MMAResponse(publicKeyPrefix: publicKeyPrefix, tag: tag, data: entries))

        case .acl:
            let entries = ACLParser.parse(data)
            return .aclResponse(ACLResponse(publicKeyPrefix: publicKeyPrefix, tag: tag, entries: entries))

        case .neighbours:
            let prefixLength = context["prefixLength"] ?? 4
            let response = NeighboursParser.parse(data, publicKeyPrefix: publicKeyPrefix, tag: tag, prefixLength: prefixLength)
            return .neighboursResponse(response)

        case .status:
            guard let response = Parsers.StatusResponse.parseFromBinaryResponse(
                data,
                publicKeyPrefix: publicKeyPrefix
            ) else {
                return nil
            }
            return .statusResponse(response)

        case .telemetry:
            let response = Parsers.TelemetryResponse.parseFromBinaryResponse(
                data,
                publicKeyPrefix: publicKeyPrefix
            )
            return .telemetryResponse(response)

        case .keepAlive:
            return nil
        }
    }

    /// Tracks contact-related changes from received events.
    private func trackContactChanges(event: MeshEvent) {
        // Track contact-related events in ContactManager
        contactManager.trackChanges(from: event)

        // Auto-refresh contacts if enabled and contacts became dirty
        if contactManager.isAutoUpdateEnabled && contactManager.needsRefresh {
            switch event {
            case .advertisement, .pathUpdate, .newContact:
                Task { [weak self] in
                    try? await self?.ensureContacts(force: true)
                }
            default:
                break
            }
        }

        // Track non-contact state
        switch event {
        case .currentTime(let time):
            cachedTime = time
        case .selfInfo(let info):
            selfInfo = info
        default:
            break
        }
    }

    /// Routes binary responses to complete pending requests.
    private func routeBinaryResponse(event: MeshEvent) async {
        switch event {
        case .statusResponse(let response):
            // Route by publicKeyPrefix + type for proper correlation
            await pendingRequests.completeBinaryRequest(
                publicKeyPrefix: response.publicKeyPrefix,
                type: .status,
                with: event
            )
        case .telemetryResponse(let response):
            await pendingRequests.completeBinaryRequest(
                publicKeyPrefix: response.publicKeyPrefix,
                type: .telemetry,
                with: event
            )
        case .mmaResponse(let response):
            await pendingRequests.completeBinaryRequest(
                publicKeyPrefix: response.publicKeyPrefix,
                type: .mma,
                with: event
            )
        case .aclResponse(let response):
            await pendingRequests.completeBinaryRequest(
                publicKeyPrefix: response.publicKeyPrefix,
                type: .acl,
                with: event
            )
        case .neighboursResponse(let response):
            await pendingRequests.completeBinaryRequest(
                publicKeyPrefix: response.publicKeyPrefix,
                type: .neighbours,
                with: event
            )
        case .acknowledgement(let code):
            await pendingRequests.complete(tag: code, with: event)
        default:
            break
        }
    }
}

// MARK: - Configuration Types

/// Configuration struct for device "other params" settings.
///
/// Used by granular configuration setters to implement read-modify-write pattern.
public struct OtherParamsConfig: Sendable {
    public var manualAddContacts: Bool
    public var telemetryModeBase: UInt8
    public var telemetryModeLocation: UInt8
    public var telemetryModeEnvironment: UInt8
    public var advertisementLocationPolicy: UInt8
    public var multiAcks: UInt8

    /// Creates a new configuration with default values.
    public init(
        manualAddContacts: Bool = false,
        telemetryModeBase: UInt8 = 0,
        telemetryModeLocation: UInt8 = 0,
        telemetryModeEnvironment: UInt8 = 0,
        advertisementLocationPolicy: UInt8 = 0,
        multiAcks: UInt8 = 0
    ) {
        self.manualAddContacts = manualAddContacts
        self.telemetryModeBase = telemetryModeBase
        self.telemetryModeLocation = telemetryModeLocation
        self.telemetryModeEnvironment = telemetryModeEnvironment
        self.advertisementLocationPolicy = advertisementLocationPolicy
        self.multiAcks = multiAcks
    }

    /// Creates a configuration from existing device information.
    init(from selfInfo: SelfInfo) {
        self.manualAddContacts = selfInfo.manualAddContacts
        self.telemetryModeBase = selfInfo.telemetryModeBase
        self.telemetryModeLocation = selfInfo.telemetryModeLocation
        self.telemetryModeEnvironment = selfInfo.telemetryModeEnvironment
        self.advertisementLocationPolicy = selfInfo.advertisementLocationPolicy
        self.multiAcks = selfInfo.multiAcks
    }
}
