import Foundation
import SwiftData
@testable import PocketMeshServices

extension ConnectionManager {
    static func createForTesting(
        defaults: UserDefaults? = nil
    ) throws -> (ConnectionManager, MockBLEStateMachine) {
        let container = try PersistenceStore.createContainer(inMemory: true)
        let mock = MockBLEStateMachine()
        let manager: ConnectionManager
        if let defaults {
            manager = ConnectionManager(modelContainer: container, defaults: defaults, stateMachine: mock)
        } else {
            manager = ConnectionManager(modelContainer: container, stateMachine: mock)
        }
        return (manager, mock)
    }
}
