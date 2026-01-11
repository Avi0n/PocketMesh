import CoreLocation
import Testing

@testable import PocketMesh
@testable import PocketMeshServices

// MARK: - Mock Elevation Service

actor MockElevationService: ElevationServiceProtocol {
    var elevationToReturn: Double = 100
    var shouldFail = false
    var fetchCount = 0
    var profileToReturn: [ElevationSample]?

    func fetchElevation(at coordinate: CLLocationCoordinate2D) async throws -> Double {
        fetchCount += 1
        if shouldFail {
            throw ElevationServiceError.noData
        }
        return elevationToReturn
    }

    func fetchElevations(along path: [CLLocationCoordinate2D]) async throws -> [ElevationSample] {
        fetchCount += 1
        if shouldFail {
            throw ElevationServiceError.noData
        }

        if let profile = profileToReturn {
            return profile
        }

        // Generate default samples with flat terrain
        var samples: [ElevationSample] = []
        let startCoord = path.first ?? CLLocationCoordinate2D(latitude: 0, longitude: 0)

        for (index, coord) in path.enumerated() {
            let distance = index == 0 ? 0 : RFCalculator.distance(from: startCoord, to: coord)
            samples.append(ElevationSample(
                coordinate: coord,
                elevation: elevationToReturn,
                distanceFromAMeters: distance
            ))
        }

        return samples
    }

    func reset() {
        elevationToReturn = 100
        shouldFail = false
        fetchCount = 0
        profileToReturn = nil
    }

    func setFailure(_ fail: Bool) {
        shouldFail = fail
    }
}

// MARK: - Mock Persistence Store

actor MockPersistenceStore: PersistenceStoreProtocol {
    var contacts: [UUID: ContactDTO] = [:]

    func fetchContacts(deviceID: UUID) async throws -> [ContactDTO] {
        Array(contacts.values.filter { $0.deviceID == deviceID && !$0.isDiscovered })
    }

    func addContact(_ contact: ContactDTO) {
        contacts[contact.id] = contact
    }

    func reset() {
        contacts = [:]
    }

    // MARK: - Unused Protocol Requirements (stubs)

    func saveMessage(_ dto: MessageDTO) async throws {}
    func fetchMessage(id: UUID) async throws -> MessageDTO? { nil }
    func fetchMessage(ackCode: UInt32) async throws -> MessageDTO? { nil }
    func fetchMessages(contactID: UUID, limit: Int, offset: Int) async throws -> [MessageDTO] { [] }
    func fetchMessages(deviceID: UUID, channelIndex: UInt8, limit: Int, offset: Int) async throws -> [MessageDTO] { [] }
    func deleteMessagesForContact(contactID: UUID) async throws {}
    func updateMessageStatus(id: UUID, status: MessageStatus) async throws {}
    func updateMessageAck(id: UUID, ackCode: UInt32, status: MessageStatus, roundTripTime: UInt32?) async throws {}
    func updateMessageByAckCode(_ ackCode: UInt32, status: MessageStatus, roundTripTime: UInt32?) async throws {}
    func updateMessageRetryStatus(id: UUID, status: MessageStatus, retryAttempt: Int, maxRetryAttempts: Int) async throws {}
    func updateMessageHeardRepeats(id: UUID, heardRepeats: Int) async throws {}
    func updateMessageLinkPreview(id: UUID, url: String?, title: String?, imageData: Data?, iconData: Data?, fetched: Bool) async throws {}
    func fetchConversations(deviceID: UUID) async throws -> [ContactDTO] { [] }
    func fetchContact(id: UUID) async throws -> ContactDTO? { nil }
    func fetchContact(deviceID: UUID, publicKey: Data) async throws -> ContactDTO? { nil }
    func fetchContact(deviceID: UUID, publicKeyPrefix: Data) async throws -> ContactDTO? { nil }
    @discardableResult func saveContact(deviceID: UUID, from frame: ContactFrame) async throws -> UUID { UUID() }
    func saveContact(_ dto: ContactDTO) async throws {}
    func deleteContact(id: UUID) async throws {}
    func updateContactLastMessage(contactID: UUID, date: Date?) async throws {}
    func incrementUnreadCount(contactID: UUID) async throws {}
    func clearUnreadCount(contactID: UUID) async throws {}
    func fetchDiscoveredContacts(deviceID: UUID) async throws -> [ContactDTO] { [] }
    func confirmContact(id: UUID) async throws {}
    func fetchChannels(deviceID: UUID) async throws -> [ChannelDTO] { [] }
    func fetchChannel(deviceID: UUID, index: UInt8) async throws -> ChannelDTO? { nil }
    func fetchChannel(id: UUID) async throws -> ChannelDTO? { nil }
    @discardableResult func saveChannel(deviceID: UUID, from info: ChannelInfo) async throws -> UUID { UUID() }
    func saveChannel(_ dto: ChannelDTO) async throws {}
    func deleteChannel(id: UUID) async throws {}
    func updateChannelLastMessage(channelID: UUID, date: Date) async throws {}
    func incrementChannelUnreadCount(channelID: UUID) async throws {}
    func clearChannelUnreadCount(channelID: UUID) async throws {}
    func fetchSavedTracePaths(deviceID: UUID) async throws -> [SavedTracePathDTO] { [] }
    func fetchSavedTracePath(id: UUID) async throws -> SavedTracePathDTO? { nil }
    func createSavedTracePath(deviceID: UUID, name: String, pathBytes: Data, initialRun: TracePathRunDTO?) async throws -> SavedTracePathDTO {
        SavedTracePathDTO(id: UUID(), deviceID: deviceID, name: name, pathBytes: pathBytes, createdDate: Date(), runs: [])
    }
    func updateSavedTracePathName(id: UUID, name: String) async throws {}
    func deleteSavedTracePath(id: UUID) async throws {}
    func appendTracePathRun(pathID: UUID, run: TracePathRunDTO) async throws {}

    // MARK: - Heard Repeats (stubs)

    func findSentChannelMessage(deviceID: UUID, channelIndex: UInt8, timestamp: UInt32, text: String, withinSeconds: Int) async throws -> MessageDTO? { nil }
    func saveMessageRepeat(_ dto: MessageRepeatDTO) async throws {}
    func fetchMessageRepeats(messageID: UUID) async throws -> [MessageRepeatDTO] { [] }
    func messageRepeatExists(rxLogEntryID: UUID) async throws -> Bool { false }
    func incrementMessageHeardRepeats(id: UUID) async throws -> Int { 0 }

    // MARK: - Debug Log (stubs)

    func saveDebugLogEntries(_ dtos: [DebugLogEntryDTO]) async throws {}
    func fetchDebugLogEntries(since date: Date, limit: Int) async throws -> [DebugLogEntryDTO] { [] }
    func countDebugLogEntries() async throws -> Int { 0 }
    func pruneDebugLogEntries(keepCount: Int) async throws {}
    func clearDebugLogEntries() async throws {}
}

// MARK: - Test Helpers

private let sanFrancisco = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
private let oakland = CLLocationCoordinate2D(latitude: 37.8044, longitude: -122.2712)
private let berkeley = CLLocationCoordinate2D(latitude: 37.8716, longitude: -122.2727)

private func createTestContact(
    name: String = "Test Contact",
    latitude: Double = 37.7749,
    longitude: Double = -122.4194,
    type: ContactType = .chat,
    deviceID: UUID = UUID()
) -> ContactDTO {
    ContactDTO(
        id: UUID(),
        deviceID: deviceID,
        publicKey: Data([0xAB] + Array(repeating: UInt8(0x00), count: 31)),
        name: name,
        typeRawValue: type.rawValue,
        flags: 0,
        outPathLength: 0,
        outPath: Data(),
        lastAdvertTimestamp: 0,
        latitude: latitude,
        longitude: longitude,
        lastModified: 0,
        nickname: nil,
        isBlocked: false,
        isFavorite: false,
        isDiscovered: false,
        lastMessageDate: nil,
        unreadCount: 0
    )
}

// MARK: - Initial State Tests

@Suite("LineOfSightViewModel Initial State")
@MainActor
struct InitialStateTests {

    @Test("Initial state has nil points")
    func initialPointsAreNil() {
        let viewModel = LineOfSightViewModel(elevationService: MockElevationService())

        #expect(viewModel.pointA == nil)
        #expect(viewModel.pointB == nil)
    }

    @Test("Initial status is idle")
    func initialStatusIsIdle() {
        let viewModel = LineOfSightViewModel(elevationService: MockElevationService())

        #expect(viewModel.analysisStatus == .idle)
    }

    @Test("canAnalyze is false initially")
    func canAnalyzeFalseInitially() {
        let viewModel = LineOfSightViewModel(elevationService: MockElevationService())

        #expect(viewModel.canAnalyze == false)
    }

    @Test("Initial elevation profile is empty")
    func initialProfileEmpty() {
        let viewModel = LineOfSightViewModel(elevationService: MockElevationService())

        #expect(viewModel.elevationProfile.isEmpty)
    }

    @Test("Default frequency is 906 MHz")
    func defaultFrequency() {
        let viewModel = LineOfSightViewModel(elevationService: MockElevationService())

        #expect(viewModel.frequencyMHz == 906.0)
    }

    @Test("Default refraction K is 1.0")
    func defaultRefractionK() {
        let viewModel = LineOfSightViewModel(elevationService: MockElevationService())

        #expect(viewModel.refractionK == 1.0)
    }
}

// MARK: - Preselected Contact Initialization Tests

@Suite("Preselected Contact Initialization")
@MainActor
struct PreselectedContactTests {

    @Test("Preselected contact sets point A")
    func preselectedContactSetsPointA() async throws {
        let contact = createTestContact(name: "Preselected", latitude: 37.8, longitude: -122.4)
        let viewModel = LineOfSightViewModel(preselectedContact: contact)

        // Wait for elevation fetch to complete
        try await Task.sleep(for: .milliseconds(100))

        #expect(viewModel.pointA != nil)
        #expect(viewModel.pointA?.contact?.name == "Preselected")
        #expect(viewModel.pointA?.coordinate.latitude == 37.8)
    }

    @Test("Preselected contact with no location does not set point A")
    func preselectedContactNoLocation() {
        let contact = createTestContact(name: "No Location", latitude: 0, longitude: 0)
        let viewModel = LineOfSightViewModel(preselectedContact: contact)

        #expect(viewModel.pointA == nil)
    }

    @Test("Nil preselected contact leaves point A nil")
    func nilPreselectedContact() {
        let viewModel = LineOfSightViewModel(preselectedContact: nil)

        #expect(viewModel.pointA == nil)
    }
}

// MARK: - Point Selection Tests

@Suite("Point Selection")
@MainActor
struct PointSelectionTests {

    @Test("selectPoint sets point A when empty")
    func selectPointSetsA() async throws {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        viewModel.selectPoint(at: sanFrancisco)

        #expect(viewModel.pointA != nil)
        #expect(viewModel.pointA?.coordinate.latitude == sanFrancisco.latitude)
        #expect(viewModel.pointB == nil)
    }

    @Test("selectPoint sets point B when A exists")
    func selectPointSetsB() async throws {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        viewModel.selectPoint(at: sanFrancisco)
        viewModel.selectPoint(at: oakland)

        #expect(viewModel.pointA != nil)
        #expect(viewModel.pointB != nil)
        #expect(viewModel.pointB?.coordinate.latitude == oakland.latitude)
    }

    @Test("selectPoint replaces B when both exist")
    func selectPointReplacesB() async throws {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        viewModel.selectPoint(at: sanFrancisco)
        viewModel.selectPoint(at: oakland)
        viewModel.selectPoint(at: berkeley)

        #expect(viewModel.pointA?.coordinate.latitude == sanFrancisco.latitude)
        #expect(viewModel.pointB?.coordinate.latitude == berkeley.latitude)
    }

    @Test("setPointA sets coordinate and contact")
    func setPointAWithContact() async throws {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)
        let contact = createTestContact(name: "Point A Contact")

        viewModel.setPointA(coordinate: sanFrancisco, contact: contact)

        #expect(viewModel.pointA != nil)
        #expect(viewModel.pointA?.contact?.name == "Point A Contact")
        #expect(viewModel.pointA?.displayName == "Point A Contact")
    }

    @Test("setPointB sets coordinate and contact")
    func setPointBWithContact() async throws {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)
        let contact = createTestContact(name: "Point B Contact")

        viewModel.setPointA(coordinate: sanFrancisco)
        viewModel.setPointB(coordinate: oakland, contact: contact)

        #expect(viewModel.pointB != nil)
        #expect(viewModel.pointB?.contact?.name == "Point B Contact")
    }

    @Test("Point without contact shows Dropped pin")
    func droppedPinDisplayName() {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        viewModel.setPointA(coordinate: sanFrancisco)

        #expect(viewModel.pointA?.displayName == "Dropped pin")
    }
}

// MARK: - Same Location Prevention Tests

@Suite("Same Location Prevention")
@MainActor
struct SameLocationTests {

    @Test("Cannot set B to same location as A")
    func cannotSetBToSameAsA() {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        viewModel.setPointA(coordinate: sanFrancisco)
        viewModel.setPointB(coordinate: sanFrancisco)

        #expect(viewModel.pointA != nil)
        #expect(viewModel.pointB == nil)
    }

    @Test("Can set B to different location after same location rejected")
    func canSetBAfterRejection() {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        viewModel.setPointA(coordinate: sanFrancisco)
        viewModel.setPointB(coordinate: sanFrancisco)  // Rejected
        viewModel.setPointB(coordinate: oakland)  // Should work

        #expect(viewModel.pointB != nil)
        #expect(viewModel.pointB?.coordinate.latitude == oakland.latitude)
    }
}

// MARK: - Elevation Fetching Tests

@Suite("Elevation Fetching")
@MainActor
struct ElevationFetchingTests {

    @Test("Point starts with nil elevation")
    func pointStartsWithNilElevation() {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        viewModel.setPointA(coordinate: sanFrancisco)

        // Before async fetch completes
        #expect(viewModel.pointA?.isLoadingElevation == true)
    }

    @Test("Elevation is fetched asynchronously")
    func elevationFetchedAsync() async throws {
        let mockService = MockElevationService()
        await mockService.reset()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        viewModel.setPointA(coordinate: sanFrancisco)

        // Wait for elevation fetch
        try await Task.sleep(for: .milliseconds(100))

        #expect(viewModel.pointA?.groundElevation == 100)
        #expect(viewModel.pointA?.isLoadingElevation == false)
    }

    @Test("canAnalyze is true when both elevations loaded")
    func canAnalyzeWithBothElevations() async throws {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        viewModel.setPointA(coordinate: sanFrancisco)
        viewModel.setPointB(coordinate: oakland)

        // Wait for elevation fetches
        try await Task.sleep(for: .milliseconds(200))

        #expect(viewModel.canAnalyze == true)
    }

    @Test("totalHeight includes additionalHeight")
    func totalHeightCalculation() async throws {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        viewModel.setPointA(coordinate: sanFrancisco)
        try await Task.sleep(for: .milliseconds(100))

        viewModel.updateAdditionalHeight(for: .pointA, meters: 10)

        #expect(viewModel.pointA?.groundElevation == 100)
        #expect(viewModel.pointA?.additionalHeight == 10)
        #expect(viewModel.pointA?.totalHeight == 110)
    }
}

// MARK: - Height Adjustment Tests

@Suite("Height Adjustment")
@MainActor
struct HeightAdjustmentTests {

    @Test("Height adjustment clamps to zero")
    func heightClampsToZero() async throws {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        viewModel.setPointA(coordinate: sanFrancisco)
        try await Task.sleep(for: .milliseconds(100))

        viewModel.updateAdditionalHeight(for: .pointA, meters: -10)

        #expect(viewModel.pointA?.additionalHeight == 0)
    }

    @Test("Height adjustment accepts positive values")
    func heightAcceptsPositive() async throws {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        viewModel.setPointA(coordinate: sanFrancisco)
        try await Task.sleep(for: .milliseconds(100))

        viewModel.updateAdditionalHeight(for: .pointA, meters: 15)

        #expect(viewModel.pointA?.additionalHeight == 15)
    }

    @Test("Height adjustment for point B works")
    func heightAdjustmentPointB() async throws {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        viewModel.setPointA(coordinate: sanFrancisco)
        viewModel.setPointB(coordinate: oakland)
        try await Task.sleep(for: .milliseconds(200))

        viewModel.updateAdditionalHeight(for: .pointB, meters: 20)

        #expect(viewModel.pointB?.additionalHeight == 20)
    }

    @Test("Height adjustment on nil point does nothing")
    func heightAdjustmentNilPoint() {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        // Should not crash
        viewModel.updateAdditionalHeight(for: .pointA, meters: 10)
        viewModel.updateAdditionalHeight(for: .pointB, meters: 10)

        #expect(viewModel.pointA == nil)
        #expect(viewModel.pointB == nil)
    }

    @Test("Height change invalidates analysis")
    func heightChangeInvalidatesAnalysis() async throws {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        viewModel.setPointA(coordinate: sanFrancisco)
        viewModel.setPointB(coordinate: oakland)
        try await Task.sleep(for: .milliseconds(200))

        viewModel.analyze()
        try await Task.sleep(for: .milliseconds(200))

        // Should have a result
        if case .result = viewModel.analysisStatus {
            // Now change height
            viewModel.updateAdditionalHeight(for: .pointA, meters: 5)

            // Should be back to idle
            #expect(viewModel.analysisStatus == .idle)
        } else {
            Issue.record("Expected analysis result before height change")
        }
    }
}

// MARK: - Clear Tests

@Suite("Clear Methods")
@MainActor
struct ClearTests {

    @Test("clear removes all state")
    func clearRemovesAllState() async throws {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        viewModel.setPointA(coordinate: sanFrancisco)
        viewModel.setPointB(coordinate: oakland)
        try await Task.sleep(for: .milliseconds(200))

        viewModel.clear()

        #expect(viewModel.pointA == nil)
        #expect(viewModel.pointB == nil)
        #expect(viewModel.analysisStatus == .idle)
        #expect(viewModel.elevationProfile.isEmpty)
    }

    @Test("clearPointA removes only point A")
    func clearPointARemovesOnlyA() async throws {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        viewModel.setPointA(coordinate: sanFrancisco)
        viewModel.setPointB(coordinate: oakland)
        try await Task.sleep(for: .milliseconds(200))

        viewModel.clearPointA()

        #expect(viewModel.pointA == nil)
        #expect(viewModel.pointB != nil)
    }

    @Test("clearPointB removes only point B")
    func clearPointBRemovesOnlyB() async throws {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        viewModel.setPointA(coordinate: sanFrancisco)
        viewModel.setPointB(coordinate: oakland)
        try await Task.sleep(for: .milliseconds(200))

        viewModel.clearPointB()

        #expect(viewModel.pointA != nil)
        #expect(viewModel.pointB == nil)
    }

    @Test("clearPointA invalidates analysis")
    func clearPointAInvalidatesAnalysis() async throws {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        viewModel.setPointA(coordinate: sanFrancisco)
        viewModel.setPointB(coordinate: oakland)
        try await Task.sleep(for: .milliseconds(200))

        viewModel.analyze()
        try await Task.sleep(for: .milliseconds(200))

        viewModel.clearPointA()

        #expect(viewModel.analysisStatus == .idle)
    }
}

// MARK: - Task Cancellation Tests

@Suite("Task Cancellation")
@MainActor
struct TaskCancellationTests {

    @Test("Setting new point A cancels pending elevation fetch")
    func newPointACancelsPendingFetch() async throws {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        // Set first point
        viewModel.setPointA(coordinate: sanFrancisco)

        // Immediately set second point (should cancel first fetch)
        viewModel.setPointA(coordinate: oakland)

        // Wait for fetch to complete
        try await Task.sleep(for: .milliseconds(100))

        // Should have the second coordinate
        #expect(viewModel.pointA?.coordinate.latitude == oakland.latitude)
    }

    @Test("Setting new point B cancels pending elevation fetch")
    func newPointBCancelsPendingFetch() async throws {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        viewModel.setPointA(coordinate: sanFrancisco)
        viewModel.setPointB(coordinate: oakland)

        // Immediately set new point B (should cancel first fetch)
        viewModel.setPointB(coordinate: berkeley)

        // Wait for fetch to complete
        try await Task.sleep(for: .milliseconds(100))

        // Should have the second coordinate
        #expect(viewModel.pointB?.coordinate.latitude == berkeley.latitude)
    }

    @Test("Clear cancels all pending tasks")
    func clearCancelsAllTasks() async throws {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        viewModel.setPointA(coordinate: sanFrancisco)
        viewModel.setPointB(coordinate: oakland)

        // Clear immediately (before fetches complete)
        viewModel.clear()

        // Verify cleared state
        #expect(viewModel.pointA == nil)
        #expect(viewModel.pointB == nil)
    }
}

// MARK: - Analysis Tests

@Suite("Analysis")
@MainActor
struct AnalysisTests {

    @Test("analyze sets loading status")
    func analyzeStartsLoading() async throws {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        viewModel.setPointA(coordinate: sanFrancisco)
        viewModel.setPointB(coordinate: oakland)
        try await Task.sleep(for: .milliseconds(200))

        // Start analysis but don't wait for it
        viewModel.analyze()

        // Should be loading (or already completed for mock)
        let isLoadingOrResult = viewModel.analysisStatus == .loading
            || (viewModel.analysisStatus != .idle && viewModel.analysisStatus != .error(""))

        #expect(isLoadingOrResult)
    }

    @Test("analyze produces result on success")
    func analyzeProducesResult() async throws {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        viewModel.setPointA(coordinate: sanFrancisco)
        viewModel.setPointB(coordinate: oakland)
        try await Task.sleep(for: .milliseconds(200))

        viewModel.analyze()
        try await Task.sleep(for: .milliseconds(300))

        if case .result(let result) = viewModel.analysisStatus {
            #expect(result.distanceMeters > 0)
        } else {
            Issue.record("Expected result status, got: \(viewModel.analysisStatus)")
        }
    }

    @Test("analyze populates elevation profile")
    func analyzePopulatesProfile() async throws {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        viewModel.setPointA(coordinate: sanFrancisco)
        viewModel.setPointB(coordinate: oakland)
        try await Task.sleep(for: .milliseconds(200))

        viewModel.analyze()
        try await Task.sleep(for: .milliseconds(300))

        #expect(!viewModel.elevationProfile.isEmpty)
    }

    @Test("analyze without elevations does nothing")
    func analyzeWithoutElevations() {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        // Points not set
        viewModel.analyze()

        #expect(viewModel.analysisStatus == .idle)
    }

    @Test("analyze error sets error status")
    func analyzeErrorSetsErrorStatus() async throws {
        let mockService = MockElevationService()
        await mockService.reset()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        viewModel.setPointA(coordinate: sanFrancisco)
        viewModel.setPointB(coordinate: oakland)
        try await Task.sleep(for: .milliseconds(200))

        // Now make the service fail for the analysis fetch
        await mockService.setFailure(true)

        viewModel.analyze()
        try await Task.sleep(for: .milliseconds(300))

        if case .error = viewModel.analysisStatus {
            // Expected
        } else {
            Issue.record("Expected error status")
        }
    }

    @Test("New analysis cancels previous")
    func newAnalysisCancelsPrevious() async throws {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        viewModel.setPointA(coordinate: sanFrancisco)
        viewModel.setPointB(coordinate: oakland)
        try await Task.sleep(for: .milliseconds(200))

        // Start analysis
        viewModel.analyze()

        // Start another immediately
        viewModel.analyze()

        // Should complete without issues
        try await Task.sleep(for: .milliseconds(300))

        if case .result = viewModel.analysisStatus {
            // Expected
        } else if case .loading = viewModel.analysisStatus {
            // Still loading is also acceptable
        } else {
            Issue.record("Unexpected status: \(viewModel.analysisStatus)")
        }
    }
}

// MARK: - Selected Point Tests

@Suite("SelectedPoint")
@MainActor
struct SelectedPointTests {

    @Test("totalHeight is nil when groundElevation is nil")
    func totalHeightNilWhenNoGround() {
        let point = SelectedPoint(
            coordinate: sanFrancisco,
            contact: nil,
            groundElevation: nil,
            additionalHeight: 10
        )

        #expect(point.totalHeight == nil)
    }

    @Test("totalHeight includes both ground and additional")
    func totalHeightCombined() {
        let point = SelectedPoint(
            coordinate: sanFrancisco,
            contact: nil,
            groundElevation: 100,
            additionalHeight: 10
        )

        #expect(point.totalHeight == 110)
    }

    @Test("isLoadingElevation is true when groundElevation is nil")
    func isLoadingWhenNilElevation() {
        let point = SelectedPoint(
            coordinate: sanFrancisco,
            contact: nil,
            groundElevation: nil,
            additionalHeight: 0
        )

        #expect(point.isLoadingElevation == true)
    }

    @Test("isLoadingElevation is false when groundElevation is set")
    func notLoadingWhenElevationSet() {
        let point = SelectedPoint(
            coordinate: sanFrancisco,
            contact: nil,
            groundElevation: 100,
            additionalHeight: 0
        )

        #expect(point.isLoadingElevation == false)
    }
}

// MARK: - AnalysisStatus Equatable Tests

@Suite("AnalysisStatus Equatable")
struct AnalysisStatusEquatableTests {

    @Test("idle equals idle")
    func idleEqualsIdle() {
        #expect(AnalysisStatus.idle == AnalysisStatus.idle)
    }

    @Test("loading equals loading")
    func loadingEqualsLoading() {
        #expect(AnalysisStatus.loading == AnalysisStatus.loading)
    }

    @Test("error with same message equals")
    func errorWithSameMessage() {
        #expect(AnalysisStatus.error("test") == AnalysisStatus.error("test"))
    }

    @Test("error with different message not equal")
    func errorWithDifferentMessage() {
        #expect(AnalysisStatus.error("test1") != AnalysisStatus.error("test2"))
    }

    @Test("idle does not equal loading")
    func idleNotEqualLoading() {
        #expect(AnalysisStatus.idle != AnalysisStatus.loading)
    }
}

// MARK: - Load Repeaters Tests

@Suite("Load Repeaters")
@MainActor
struct LoadRepeatersTests {

    @Test("loadRepeaters filters to only repeaters with location")
    func loadRepeatersFiltersCorrectly() async throws {
        let mockService = MockElevationService()
        let mockDataStore = MockPersistenceStore()
        let deviceID = UUID()

        // Add a repeater with location
        let repeaterWithLocation = createTestContact(
            name: "Repeater 1",
            latitude: 37.7749,
            longitude: -122.4194,
            type: .repeater,
            deviceID: deviceID
        )
        await mockDataStore.addContact(repeaterWithLocation)

        // Add a repeater without location
        let repeaterNoLocation = createTestContact(
            name: "Repeater 2",
            latitude: 0,
            longitude: 0,
            type: .repeater,
            deviceID: deviceID
        )
        await mockDataStore.addContact(repeaterNoLocation)

        // Add a chat contact with location (should be excluded)
        let chatWithLocation = createTestContact(
            name: "Chat User",
            latitude: 37.8044,
            longitude: -122.2712,
            type: .chat,
            deviceID: deviceID
        )
        await mockDataStore.addContact(chatWithLocation)

        // Add a room contact with location (should be excluded)
        let roomWithLocation = createTestContact(
            name: "Room Server",
            latitude: 37.8716,
            longitude: -122.2727,
            type: .room,
            deviceID: deviceID
        )
        await mockDataStore.addContact(roomWithLocation)

        let viewModel = LineOfSightViewModel(elevationService: mockService)
        viewModel.configure(dataStore: mockDataStore, deviceID: deviceID)

        await viewModel.loadRepeaters()

        #expect(viewModel.repeatersWithLocation.count == 1)
        #expect(viewModel.repeatersWithLocation.first?.name == "Repeater 1")
    }

    @Test("loadRepeaters returns empty when no repeaters have location")
    func loadRepeatersEmptyWhenNoLocation() async throws {
        let mockService = MockElevationService()
        let mockDataStore = MockPersistenceStore()
        let deviceID = UUID()

        // Add repeaters without location
        let repeater1 = createTestContact(
            name: "Repeater 1",
            latitude: 0,
            longitude: 0,
            type: .repeater,
            deviceID: deviceID
        )
        await mockDataStore.addContact(repeater1)

        let repeater2 = createTestContact(
            name: "Repeater 2",
            latitude: 0,
            longitude: 0,
            type: .repeater,
            deviceID: deviceID
        )
        await mockDataStore.addContact(repeater2)

        let viewModel = LineOfSightViewModel(elevationService: mockService)
        viewModel.configure(dataStore: mockDataStore, deviceID: deviceID)

        await viewModel.loadRepeaters()

        #expect(viewModel.repeatersWithLocation.isEmpty)
    }

    @Test("loadRepeaters does nothing without configuration")
    func loadRepeatersWithoutConfig() async throws {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        // Don't configure the viewModel - should do nothing
        await viewModel.loadRepeaters()

        #expect(viewModel.repeatersWithLocation.isEmpty)
    }

    @Test("loadRepeaters only loads repeaters for configured device")
    func loadRepeatersForSpecificDevice() async throws {
        let mockService = MockElevationService()
        let mockDataStore = MockPersistenceStore()
        let deviceID1 = UUID()
        let deviceID2 = UUID()

        // Add repeater for device 1
        let repeaterDevice1 = createTestContact(
            name: "Repeater Device 1",
            latitude: 37.7749,
            longitude: -122.4194,
            type: .repeater,
            deviceID: deviceID1
        )
        await mockDataStore.addContact(repeaterDevice1)

        // Add repeater for device 2
        let repeaterDevice2 = createTestContact(
            name: "Repeater Device 2",
            latitude: 37.8044,
            longitude: -122.2712,
            type: .repeater,
            deviceID: deviceID2
        )
        await mockDataStore.addContact(repeaterDevice2)

        let viewModel = LineOfSightViewModel(elevationService: mockService)
        viewModel.configure(dataStore: mockDataStore, deviceID: deviceID1)

        await viewModel.loadRepeaters()

        #expect(viewModel.repeatersWithLocation.count == 1)
        #expect(viewModel.repeatersWithLocation.first?.name == "Repeater Device 1")
    }

    @Test("Initial repeatersWithLocation is empty")
    func initialRepeatersEmpty() {
        let viewModel = LineOfSightViewModel(elevationService: MockElevationService())

        #expect(viewModel.repeatersWithLocation.isEmpty)
    }
}

// MARK: - Elevation Interpolation Tests

@Suite("Elevation Interpolation")
@MainActor
struct ElevationInterpolationTests {

    @Test("elevationAt returns nil when profile is empty")
    func elevationAtEmptyProfile() {
        let viewModel = LineOfSightViewModel(elevationService: MockElevationService())
        #expect(viewModel.elevationAt(pathFraction: 0.5) == nil)
    }

    @Test("elevationAt interpolates between samples")
    func elevationAtInterpolation() {
        let mockService = MockElevationService()
        let profile = [
            ElevationSample(coordinate: sanFrancisco, elevation: 100, distanceFromAMeters: 0),
            ElevationSample(coordinate: oakland, elevation: 200, distanceFromAMeters: 1000)
        ]

        let viewModel = LineOfSightViewModel(elevationService: mockService)
        viewModel.setElevationProfileForTesting(profile)

        // Midpoint should interpolate to 150
        let midElevation = viewModel.elevationAt(pathFraction: 0.5)
        #expect(midElevation != nil)
        #expect(abs(midElevation! - 150) < 0.01)

        // At start
        let startElevation = viewModel.elevationAt(pathFraction: 0.0)
        #expect(startElevation != nil)
        #expect(abs(startElevation! - 100) < 0.01)

        // At end
        let endElevation = viewModel.elevationAt(pathFraction: 1.0)
        #expect(endElevation != nil)
        #expect(abs(endElevation! - 200) < 0.01)
    }

    @Test("coordinateAt interpolates between samples")
    func coordinateAtInterpolation() {
        let mockService = MockElevationService()
        let profile = [
            ElevationSample(coordinate: sanFrancisco, elevation: 100, distanceFromAMeters: 0),
            ElevationSample(coordinate: oakland, elevation: 200, distanceFromAMeters: 1000)
        ]

        let viewModel = LineOfSightViewModel(elevationService: mockService)
        viewModel.setElevationProfileForTesting(profile)

        let midCoord = viewModel.coordinateAt(pathFraction: 0.5)
        #expect(midCoord != nil)

        // Should be roughly between SF and Oakland
        let expectedLat = (sanFrancisco.latitude + oakland.latitude) / 2
        let expectedLon = (sanFrancisco.longitude + oakland.longitude) / 2
        #expect(abs(midCoord!.latitude - expectedLat) < 0.001)
        #expect(abs(midCoord!.longitude - expectedLon) < 0.001)
    }

    @Test("elevationAt returns nil when profile has single sample")
    func elevationAtSingleSample() {
        let viewModel = LineOfSightViewModel(elevationService: MockElevationService())
        viewModel.setElevationProfileForTesting([
            ElevationSample(coordinate: sanFrancisco, elevation: 100, distanceFromAMeters: 0)
        ])

        #expect(viewModel.elevationAt(pathFraction: 0.5) == nil)
    }

    @Test("elevationAt clamps pathFraction outside valid range")
    func elevationAtClampsOutOfRange() {
        let viewModel = LineOfSightViewModel(elevationService: MockElevationService())
        viewModel.setElevationProfileForTesting([
            ElevationSample(coordinate: sanFrancisco, elevation: 100, distanceFromAMeters: 0),
            ElevationSample(coordinate: oakland, elevation: 200, distanceFromAMeters: 1000)
        ])

        // Negative should clamp to start (100)
        let belowStart = viewModel.elevationAt(pathFraction: -0.5)
        #expect(belowStart != nil)
        #expect(abs(belowStart! - 100) < 0.01)

        // Above 1.0 should clamp to end (200)
        let aboveEnd = viewModel.elevationAt(pathFraction: 1.5)
        #expect(aboveEnd != nil)
        #expect(abs(aboveEnd! - 200) < 0.01)
    }
}

// MARK: - Contact Toggle Selection Tests

@Suite("Contact Toggle Selection")
@MainActor
struct ContactToggleTests {

    @Test("toggleContact sets point A for first contact")
    func toggleFirstContactSetsA() async throws {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)
        let contact = createTestContact(name: "Repeater", latitude: 37.8, longitude: -122.4, type: .repeater)

        viewModel.toggleContact(contact)

        #expect(viewModel.pointA != nil)
        #expect(viewModel.pointA?.contact?.id == contact.id)
    }

    @Test("toggleContact sets point B for second contact")
    func toggleSecondContactSetsB() async throws {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)
        let contact1 = createTestContact(name: "Repeater 1", latitude: 37.8, longitude: -122.4, type: .repeater)
        let contact2 = createTestContact(name: "Repeater 2", latitude: 37.7, longitude: -122.3, type: .repeater)

        viewModel.toggleContact(contact1)
        viewModel.toggleContact(contact2)

        #expect(viewModel.pointA?.contact?.id == contact1.id)
        #expect(viewModel.pointB?.contact?.id == contact2.id)
    }

    @Test("toggleContact clears point A when tapped again")
    func toggleSameContactClearsA() async throws {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)
        let contact = createTestContact(name: "Repeater", latitude: 37.8, longitude: -122.4, type: .repeater)

        viewModel.toggleContact(contact)
        viewModel.toggleContact(contact)

        #expect(viewModel.pointA == nil)
    }

    @Test("toggleContact clears point B when tapped again")
    func toggleSameContactClearsB() async throws {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)
        let contact1 = createTestContact(name: "Repeater 1", latitude: 37.8, longitude: -122.4, type: .repeater)
        let contact2 = createTestContact(name: "Repeater 2", latitude: 37.7, longitude: -122.3, type: .repeater)

        viewModel.toggleContact(contact1)
        viewModel.toggleContact(contact2)
        viewModel.toggleContact(contact2)

        #expect(viewModel.pointA != nil)
        #expect(viewModel.pointB == nil)
    }

    @Test("isContactSelected returns correct state")
    func isContactSelectedReturnsCorrectState() async throws {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)
        let contact = createTestContact(name: "Repeater", latitude: 37.8, longitude: -122.4, type: .repeater)

        #expect(viewModel.isContactSelected(contact) == nil)

        viewModel.toggleContact(contact)
        #expect(viewModel.isContactSelected(contact) == .pointA)
    }

    @Test("isContactSelected returns pointB when contact is point B")
    func isContactSelectedReturnsPointB() async throws {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)
        let contact1 = createTestContact(name: "Repeater 1", latitude: 37.8, longitude: -122.4, type: .repeater)
        let contact2 = createTestContact(name: "Repeater 2", latitude: 37.7, longitude: -122.3, type: .repeater)

        viewModel.toggleContact(contact1)
        viewModel.toggleContact(contact2)

        #expect(viewModel.isContactSelected(contact1) == .pointA)
        #expect(viewModel.isContactSelected(contact2) == .pointB)
    }

    @Test("isContactSelected returns nil for unselected contact")
    func isContactSelectedReturnsNilForUnselected() async throws {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)
        let contact1 = createTestContact(name: "Repeater 1", latitude: 37.8, longitude: -122.4, type: .repeater)
        let contact2 = createTestContact(name: "Repeater 2", latitude: 37.7, longitude: -122.3, type: .repeater)

        viewModel.toggleContact(contact1)

        #expect(viewModel.isContactSelected(contact2) == nil)
    }
}

// MARK: - Repeater Point Tests

private let testRepeaterCoordinate = CLLocationCoordinate2D(latitude: 37.8, longitude: -122.35)

@Suite("Repeater Point Model")
struct RepeaterPointTests {

    @Test("RepeaterPoint clamps pathFraction to valid range")
    func pathFractionClamping() {
        var point = RepeaterPoint(coordinate: testRepeaterCoordinate, pathFraction: 0.02)
        #expect(point.pathFraction >= 0.05)

        point = RepeaterPoint(coordinate: testRepeaterCoordinate, pathFraction: 0.98)
        #expect(point.pathFraction <= 0.95)

        point = RepeaterPoint(coordinate: testRepeaterCoordinate, pathFraction: 0.5)
        #expect(point.pathFraction == 0.5)
    }

    @Test("RepeaterPoint has default height of 10m")
    func defaultHeight() {
        let point = RepeaterPoint(coordinate: testRepeaterCoordinate, pathFraction: 0.5)
        #expect(point.additionalHeight == 10)
    }
}

// MARK: - Repeater ViewModel Properties Tests

@Suite("Repeater ViewModel Properties")
@MainActor
struct RepeaterViewModelTests {

    @Test("Initial repeaterPoint is nil")
    func initialRepeaterNil() {
        let viewModel = LineOfSightViewModel(elevationService: MockElevationService())
        #expect(viewModel.repeaterPoint == nil)
    }
}

// MARK: - Repeater Lifecycle Tests

@Suite("Repeater Lifecycle")
@MainActor
struct RepeaterLifecycleTests {

    @Test("addRepeater places at worst obstruction point")
    func addRepeaterAtWorstObstruction() {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        // Create profile spanning 10km
        let profile = (0...100).map { i in
            ElevationSample(
                coordinate: CLLocationCoordinate2D(
                    latitude: 37.7749 + Double(i) * 0.001,
                    longitude: -122.4194
                ),
                elevation: 100,
                distanceFromAMeters: Double(i) * 100
            )
        }
        viewModel.setElevationProfileForTesting(profile)

        // Set obstructed result with worst point at 30% of path
        let obstructedResult = PathAnalysisResult(
            distanceMeters: 10000,
            freeSpacePathLoss: 110,
            peakDiffractionLoss: 15,
            totalPathLoss: 125,
            clearanceStatus: .partialObstruction,
            worstClearancePercent: 45,
            obstructionPoints: [
                ObstructionPoint(distanceFromAMeters: 3000, obstructionHeightMeters: 20, fresnelClearancePercent: 45),
                ObstructionPoint(distanceFromAMeters: 7000, obstructionHeightMeters: 10, fresnelClearancePercent: 55)
            ],
            frequencyMHz: 906,
            refractionK: 1.0
        )
        viewModel.setAnalysisStatusForTesting(obstructedResult)

        viewModel.addRepeater()

        #expect(viewModel.repeaterPoint != nil)
        // Worst obstruction is at 3000m out of 10000m = 0.3
        #expect(abs(viewModel.repeaterPoint!.pathFraction - 0.3) < 0.01)
    }

    @Test("clearRepeater removes repeater")
    func clearRepeaterReverts() {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        viewModel.repeaterPoint = RepeaterPoint(coordinate: testRepeaterCoordinate, pathFraction: 0.5)
        #expect(viewModel.repeaterPoint != nil)

        viewModel.clearRepeater()

        #expect(viewModel.repeaterPoint == nil)
    }

    @Test("updateRepeaterPosition updates pathFraction")
    func updateRepeaterPosition() {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        viewModel.repeaterPoint = RepeaterPoint(coordinate: testRepeaterCoordinate, pathFraction: 0.5)
        viewModel.updateRepeaterPosition(pathFraction: 0.7)

        #expect(viewModel.repeaterPoint?.pathFraction == 0.7)
    }

    @Test("updateRepeaterPosition clamps to valid range")
    func updateRepeaterPositionClamping() {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        viewModel.repeaterPoint = RepeaterPoint(coordinate: testRepeaterCoordinate, pathFraction: 0.5)

        viewModel.updateRepeaterPosition(pathFraction: 0.01)
        #expect(viewModel.repeaterPoint!.pathFraction >= 0.05)

        viewModel.updateRepeaterPosition(pathFraction: 0.99)
        #expect(viewModel.repeaterPoint!.pathFraction <= 0.95)
    }

    @Test("updateRepeaterHeight updates additionalHeight")
    func updateRepeaterHeight() {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        viewModel.repeaterPoint = RepeaterPoint(coordinate: testRepeaterCoordinate, additionalHeight: 10, pathFraction: 0.5)
        viewModel.updateRepeaterHeight(meters: 25)

        #expect(viewModel.repeaterPoint?.additionalHeight == 25)
    }

    @Test("updateRepeaterHeight clamps negative to zero")
    func updateRepeaterHeightClamping() {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        viewModel.repeaterPoint = RepeaterPoint(coordinate: testRepeaterCoordinate, additionalHeight: 10, pathFraction: 0.5)
        viewModel.updateRepeaterHeight(meters: -5)

        #expect(viewModel.repeaterPoint?.additionalHeight == 0)
    }

    @Test("clearPointA removes repeater")
    func clearPointARemovesRepeater() {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        viewModel.setPointA(coordinate: sanFrancisco)
        viewModel.repeaterPoint = RepeaterPoint(coordinate: testRepeaterCoordinate, pathFraction: 0.5)

        viewModel.clearPointA()

        #expect(viewModel.repeaterPoint == nil)
    }

    @Test("clearPointB removes repeater")
    func clearPointBRemovesRepeater() {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        viewModel.setPointA(coordinate: sanFrancisco)
        viewModel.setPointB(coordinate: oakland)
        viewModel.repeaterPoint = RepeaterPoint(coordinate: testRepeaterCoordinate, pathFraction: 0.5)

        viewModel.clearPointB()

        #expect(viewModel.repeaterPoint == nil)
    }
}

// MARK: - Relay Analysis Tests

@Suite("Relay Analysis")
@MainActor
struct RelayAnalysisTests {

    @Test("analyzeWithRepeater produces relay result")
    func analyzeWithRepeaterProducesRelayResult() async throws {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        // Set points first (this clears profile via invalidateAnalysis)
        viewModel.setPointA(coordinate: sanFrancisco)
        viewModel.setPointB(coordinate: oakland)
        try await Task.sleep(for: .milliseconds(200))

        // Create and set profile AFTER points are set
        let profile = (0...100).map { i in
            ElevationSample(
                coordinate: CLLocationCoordinate2D(
                    latitude: 37.7749 + Double(i) * 0.001,
                    longitude: -122.4194
                ),
                elevation: 100,
                distanceFromAMeters: Double(i) * 100
            )
        }
        viewModel.setElevationProfileForTesting(profile)

        // Add repeater at midpoint
        viewModel.repeaterPoint = RepeaterPoint(coordinate: testRepeaterCoordinate, additionalHeight: 10, pathFraction: 0.5)

        viewModel.analyzeWithRepeater()

        if case .relayResult(let result) = viewModel.analysisStatus {
            #expect(result.segmentAR.startLabel == "A")
            #expect(result.segmentAR.endLabel == "R")
            #expect(result.segmentRB.startLabel == "R")
            #expect(result.segmentRB.endLabel == "B")
        } else {
            Issue.record("Expected relayResult status, got: \(viewModel.analysisStatus)")
        }
    }

    @Test("analyzeWithRepeater updates when repeater position changes")
    func analyzeWithRepeaterUpdatesOnPositionChange() async throws {
        let mockService = MockElevationService()
        let viewModel = LineOfSightViewModel(elevationService: mockService)

        // Set points first (this clears profile via invalidateAnalysis)
        viewModel.setPointA(coordinate: sanFrancisco)
        viewModel.setPointB(coordinate: oakland)
        try await Task.sleep(for: .milliseconds(200))

        // Create and set profile AFTER points are set
        let profile = (0...100).map { i in
            ElevationSample(
                coordinate: CLLocationCoordinate2D(
                    latitude: 37.7749 + Double(i) * 0.001,
                    longitude: -122.4194
                ),
                elevation: 100,
                distanceFromAMeters: Double(i) * 100
            )
        }
        viewModel.setElevationProfileForTesting(profile)

        viewModel.repeaterPoint = RepeaterPoint(coordinate: testRepeaterCoordinate, additionalHeight: 10, pathFraction: 0.5)
        viewModel.analyzeWithRepeater()

        // Get initial segment distances
        guard case .relayResult(let initialResult) = viewModel.analysisStatus else {
            Issue.record("Expected initial relayResult")
            return
        }
        let initialARDistance = initialResult.segmentAR.distanceMeters

        // Move repeater to 30%
        viewModel.updateRepeaterPosition(pathFraction: 0.3)
        viewModel.analyzeWithRepeater()

        guard case .relayResult(let updatedResult) = viewModel.analysisStatus else {
            Issue.record("Expected updated relayResult")
            return
        }

        // A→R segment should be shorter now
        #expect(updatedResult.segmentAR.distanceMeters < initialARDistance)
    }
}

// MARK: - AnalysisStatus Relay Extension Tests

@Suite("AnalysisStatus Relay Extension")
struct AnalysisStatusRelayTests {

    @Test("relayResult case stores RelayPathAnalysisResult")
    func relayResultCase() {
        let segmentAR = SegmentAnalysisResult(
            startLabel: "A", endLabel: "R",
            clearanceStatus: .clear,
            distanceMeters: 5000,
            worstClearancePercent: 85
        )
        let segmentRB = SegmentAnalysisResult(
            startLabel: "R", endLabel: "B",
            clearanceStatus: .clear,
            distanceMeters: 3000,
            worstClearancePercent: 90
        )
        let relayResult = RelayPathAnalysisResult(segmentAR: segmentAR, segmentRB: segmentRB)

        let status = AnalysisStatus.relayResult(relayResult)

        if case .relayResult(let result) = status {
            #expect(result.totalDistanceMeters == 8000)
        } else {
            Issue.record("Expected relayResult case")
        }
    }

    @Test("relayResult equals relayResult with same data")
    func relayResultEquatable() {
        let segmentAR = SegmentAnalysisResult(
            startLabel: "A", endLabel: "R",
            clearanceStatus: .clear,
            distanceMeters: 5000,
            worstClearancePercent: 85
        )
        let segmentRB = SegmentAnalysisResult(
            startLabel: "R", endLabel: "B",
            clearanceStatus: .clear,
            distanceMeters: 3000,
            worstClearancePercent: 90
        )
        let relayResult = RelayPathAnalysisResult(segmentAR: segmentAR, segmentRB: segmentRB)

        let status1 = AnalysisStatus.relayResult(relayResult)
        let status2 = AnalysisStatus.relayResult(relayResult)

        #expect(status1 == status2)
    }
}
