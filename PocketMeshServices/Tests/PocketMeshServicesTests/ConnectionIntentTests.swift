import Foundation
import Testing
@testable import PocketMeshServices

@Suite("ConnectionIntent Tests")
struct ConnectionIntentTests {

    // MARK: - Convenience Properties

    @Test("wantsConnection returns true for .wantsConnection")
    func wantsConnectionTrue() {
        #expect(ConnectionIntent.wantsConnection().wantsConnection == true)
    }

    @Test("wantsConnection returns true for .wantsConnection(forceFullSync: true)")
    func wantsConnectionTrueWithForceSync() {
        #expect(ConnectionIntent.wantsConnection(forceFullSync: true).wantsConnection == true)
    }

    @Test("wantsConnection returns false for .none")
    func wantsConnectionFalseForNone() {
        #expect(ConnectionIntent.none.wantsConnection == false)
    }

    @Test("wantsConnection returns false for .userDisconnected")
    func wantsConnectionFalseForUserDisconnected() {
        #expect(ConnectionIntent.userDisconnected.wantsConnection == false)
    }

    @Test("isUserDisconnected returns true only for .userDisconnected")
    func isUserDisconnectedProperty() {
        #expect(ConnectionIntent.userDisconnected.isUserDisconnected == true)
        #expect(ConnectionIntent.none.isUserDisconnected == false)
        #expect(ConnectionIntent.wantsConnection().isUserDisconnected == false)
    }

    // MARK: - Equatable

    @Test("wantsConnection default is equatable")
    func wantsConnectionEquatable() {
        #expect(ConnectionIntent.wantsConnection() == ConnectionIntent.wantsConnection(forceFullSync: false))
    }

    @Test("wantsConnection with different forceFullSync are not equal")
    func wantsConnectionNotEqualWithDifferentSync() {
        #expect(ConnectionIntent.wantsConnection(forceFullSync: true) != ConnectionIntent.wantsConnection(forceFullSync: false))
    }

    // MARK: - Migration Equivalence

    @Test("wantsConnection replaces shouldBeConnected = true")
    func migrationShouldBeConnected() {
        let intent = ConnectionIntent.wantsConnection()
        #expect(intent.wantsConnection == true)
        #expect(intent.isUserDisconnected == false)
    }

    @Test("userDisconnected replaces setUserDisconnected + shouldBeConnected = false")
    func migrationUserDisconnected() {
        let intent = ConnectionIntent.userDisconnected
        #expect(intent.wantsConnection == false)
        #expect(intent.isUserDisconnected == true)
    }

    @Test("forceFullSync is carried in wantsConnection")
    func migrationForceFullSync() {
        let intent = ConnectionIntent.wantsConnection(forceFullSync: true)
        if case .wantsConnection(let force) = intent {
            #expect(force == true)
        } else {
            Issue.record("Expected .wantsConnection")
        }
    }

    @Test("forceFullSync can be consumed and reset")
    func forceFullSyncConsumePattern() {
        var intent = ConnectionIntent.wantsConnection(forceFullSync: true)

        // Consume
        if case .wantsConnection(let force) = intent {
            #expect(force == true)
            intent = .wantsConnection()
        }

        // Verify reset
        if case .wantsConnection(let force) = intent {
            #expect(force == false)
        } else {
            Issue.record("Expected .wantsConnection after reset")
        }
    }
}

// MARK: - Persistence Tests (serialized to avoid UserDefaults race conditions)

@Suite("ConnectionIntent Persistence Tests", .serialized)
struct ConnectionIntentPersistenceTests {

    private static let key = "com.pocketmesh.userExplicitlyDisconnected"

    @Test("userDisconnected persists and restores")
    func userDisconnectedPersistsAndRestores() {
        UserDefaults.standard.removeObject(forKey: Self.key)

        ConnectionIntent.userDisconnected.persist()
        let restored = ConnectionIntent.restored()
        #expect(restored == .userDisconnected)

        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    @Test("none clears persisted userDisconnected")
    func noneClearsPersistence() {
        UserDefaults.standard.removeObject(forKey: Self.key)

        ConnectionIntent.userDisconnected.persist()
        #expect(ConnectionIntent.restored() == .userDisconnected)

        ConnectionIntent.none.persist()
        #expect(ConnectionIntent.restored() == .none)

        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    @Test("wantsConnection clears persisted userDisconnected")
    func wantsConnectionClearsPersistence() {
        UserDefaults.standard.removeObject(forKey: Self.key)

        ConnectionIntent.userDisconnected.persist()
        #expect(ConnectionIntent.restored() == .userDisconnected)

        ConnectionIntent.wantsConnection().persist()
        #expect(ConnectionIntent.restored() == .none)

        UserDefaults.standard.removeObject(forKey: Self.key)
    }

    @Test("restored returns .none when nothing persisted")
    func restoredReturnsNoneByDefault() {
        UserDefaults.standard.removeObject(forKey: Self.key)
        #expect(ConnectionIntent.restored() == .none)
    }
}
