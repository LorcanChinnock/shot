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
        installEditMenu()
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
        if host == "settings" {
            let name = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "section" }?.value
            SettingsWindowController.show(section: name.flatMap(SettingsSection.init(rawValue:)))
            return
        }
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
        // `shot://record?full=1` predates `shot://record-fullscreen`; keep it working.
        let legacyFull = action == .record && query.contains { $0.name == "full" && $0.value == "1" }
        coordinator.perform(legacyFull ? .recordFullscreen : action)
    }

    /// Never visible in an LSUIElement app, but routes ⌘X/⌘C/⌘V/⌘A/⌘Z to text fields.
    private func installEditMenu() {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        let main = NSMenu()
        main.addItem(NSMenuItem(title: "Shot", action: nil, keyEquivalent: ""))
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}
