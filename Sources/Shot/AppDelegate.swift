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
        _ = Preferences()
        HotkeyCenter.shared.onPress = { [weak self] action in
            self?.coordinator.perform(action)
        }
        registerHotkeys()
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.registerHotkeysIfChanged()
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
        coordinator.perform(action)
    }

    private var registeredBindings: [ShotAction: KeyCombo] = [:]
    var hotkeysSuspended = false

    func registerHotkeys() {
        let prefs = Preferences()
        var bindings: [ShotAction: KeyCombo] = [:]
        for action in ShotAction.allCases {
            bindings[action] = prefs.hotkey(for: action)
        }
        registeredBindings = bindings
        HotkeyCenter.shared.register(bindings)
    }

    private func registerHotkeysIfChanged() {
        guard !hotkeysSuspended else {
            return
        }
        let prefs = Preferences()
        let current = ShotAction.allCases.reduce(into: [ShotAction: KeyCombo]()) { $0[$1] = prefs.hotkey(for: $1) }
        if current != registeredBindings {
            registerHotkeys()
        }
    }
}
