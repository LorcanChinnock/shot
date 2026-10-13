import Foundation
import ShotCore

extension ProjectStore {
    /// This app's store, so ShotDev's projects stay apart from the release's.
    static let app = ProjectStore(bundleID: Bundle.main.bundleIdentifier ?? "dev.lorcan.Shot.dev")
}
