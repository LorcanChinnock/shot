import AppKit
import Observation
import os
import Sparkle

private let log = Logger.shot("update")

/// Wraps Sparkle. Nothing goes over the network until the user agrees: Sparkle asks once whether to
/// check automatically (Info.plist leaves SUEnableAutomaticChecks unset), and "Check for Updates…" is always manual.
/// Local builds have no SUFeedURL, so the updater never starts and Sparkle can't replace them with a release.
/// Homebrew or a drag-and-drop can replace the app while it runs, so before offering an update it checks the
/// copy on disk and offers a relaunch instead.
@MainActor
@Observable
final class Updater: NSObject {
    static let shared = Updater()

    /// Set while a scheduled check has found an update the user hasn't looked at yet. A menu bar app's
    /// update alert can open behind other windows, so the menu offers it too.
    private(set) var pendingVersion: String?
    private(set) var canCheckForUpdates = false

    @ObservationIgnored private var controller: SPUStandardUpdaterController!
    @ObservationIgnored private var canCheckObservation: NSKeyValueObservation?

    private override init() {
        super.init()
        let isEnabled = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil
        controller = SPUStandardUpdaterController(startingUpdater: isEnabled, updaterDelegate: self, userDriverDelegate: self)
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

extension Updater: SPUUpdaterDelegate {
    nonisolated func updater(_ updater: SPUUpdater, shouldProceedWithUpdate updateItem: SUAppcastItem, updateCheck: SPUUpdateCheck) throws {
        let running = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let infoURL = Bundle.main.bundleURL.appending(path: "Contents/Info.plist")
        guard let installed = NSDictionary(contentsOf: infoURL)?["CFBundleShortVersionString"] as? String, installed != running else {
            return
        }
        log.notice("Shot \(installed) is installed but \(running ?? "?") is running; offering a relaunch")
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                Self.offerRelaunch(installed: installed)
            }
        }
        throw NSError(domain: SUSparkleErrorDomain, code: Int(SUError.installationCanceledError.rawValue))
    }

    private static func offerRelaunch(installed: String) {
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Shot \(installed) is installed"
        alert.informativeText = "Shot was updated while it was running. Relaunch to finish."
        alert.addButton(withTitle: "Relaunch")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            Permissions.relaunch()
        }
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
