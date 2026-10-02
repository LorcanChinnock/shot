import Foundation
import os

extension Logger {
    /// Logs under the app's bundle identifier, so forks with their own identifier keep their logs apart.
    static func shot(_ category: String) -> Logger {
        Logger(subsystem: Bundle.main.bundleIdentifier ?? "Shot", category: category)
    }
}
