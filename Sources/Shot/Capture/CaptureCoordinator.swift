import AppKit
import os
import ShotCore

private let log = Logger(subsystem: "dev.lorcan.Shot", category: "capture")

@MainActor
final class CaptureCoordinator {
    let state: AppState

    init(state: AppState) {
        self.state = state
    }

    func perform(_ action: ShotAction) {
        log.notice("Action received: \(action.rawValue, privacy: .public)")
    }

    func annotate(_ url: URL) {
        log.notice("Annotate requested: \(url.path, privacy: .public)")
    }
}
