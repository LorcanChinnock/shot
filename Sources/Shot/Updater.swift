import AppKit
import Observation
import os
import Sparkle

private let log = Logger.shot("update")

/// Wraps Sparkle. Nothing goes over the network until the user agrees: Sparkle asks once whether to
/// check automatically (Info.plist leaves SUEnableAutomaticChecks unset), and "Check for Updates…" is always manual.
/// Dev builds have no SUFeedURL, so the updater never starts and Sparkle can't replace them with a release.
@MainActor
@Observable
final class Updater: NSObject {
    static let shared = Updater()

    /// Set while a scheduled check has found an update the user hasn't looked at yet. A menu bar app's
    /// update alert can open behind other windows, so the menu offers it too.
    private(set) var pendingVersion: String?
    private(set) var canCheckForUpdates = false
    let isEnabled = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil

    @ObservationIgnored private var controller: SPUStandardUpdaterController!
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: isEnabled, updaterDelegate: nil, userDriverDelegate: self)
        canCheckObservation = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else {
                    return
                }
                self.canCheckForUpdates = self.controller.updater.canCheckForUpdates
            }
        }
    }

    var automaticallyChecks: Bool {
        get {
            access(keyPath: \.automaticallyChecks)
            return controller.updater.automaticallyChecksForUpdates
        }
        set {
            withMutation(keyPath: \.automaticallyChecks) {
                controller.updater.automaticallyChecksForUpdates = newValue
            }
            log.notice("Automatic update checks \(newValue ? "on" : "off")")
        }
    }

    func checkForUpdates() {
        NSApp.activate()
        controller.checkForUpdates(nil)
    }
}

extension Updater: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        let version = update.displayVersionString
        let userInitiated = state.userInitiated
        MainActor.assumeIsolated {
            log.notice("Update \(version) available")
            if !userInitiated {
                pendingVersion = version
            }
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated {
            pendingVersion = nil
        }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated {
            pendingVersion = nil
        }
    }
}
