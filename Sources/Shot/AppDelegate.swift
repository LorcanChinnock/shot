import AppKit
import os
import ShotCore

private let log = Logger(subsystem: "dev.lorcan.Shot", category: "app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    lazy var coordinator = CaptureCoordinator(state: state)
    private var defaultsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        HotkeyCenter.shared.onPress = { [weak self] action in
            self?.coordinator.perform(action)
        }
        HotkeyCenter.shared.reloadFromPreferences()
        QuickAccessController.shared.onAnnotate = { [weak self] url in
            self?.coordinator.annotate(url)
        }
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                HotkeyCenter.shared.reloadFromPreferences()
            }
        }
        Permissions.showOnboardingIfNeeded()
        log.notice("Shot launched")
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handle(url)
        }
    }

    private func handle(_ url: URL) {
        guard url.scheme == "shot", let host = url.host() else {
            return
        }
        log.notice("URL received: \(url.absoluteString, privacy: .public)")
        if host == "annotate" {
            let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "path" }?.value
            guard let path else {
                Toast.show("Missing path for annotate")
                return
            }
            coordinator.annotate(URL(fileURLWithPath: (path as NSString).expandingTildeInPath))
            return
        }
        guard let action = ShotAction(rawValue: host) else {
            Toast.show("Unknown action: \(host)")
            return
        }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        coordinator.perform(action, fullDisplay: query.contains { $0.name == "full" && $0.value == "1" })
    }
}
