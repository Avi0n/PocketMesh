import UIKit
import PocketMeshServices

/// UIKit-based implementation of AppStateProvider.
///
/// Checks UIApplication.shared.applicationState to determine if app is in foreground.
/// MainActor-isolated with async getter to allow cross-actor access.
@MainActor
public final class AppStateProviderImpl: AppStateProvider {

    public init() {}

    nonisolated public var isInForeground: Bool {
        get async {
            await MainActor.run {
                UIApplication.shared.applicationState == .active
            }
        }
    }
}
