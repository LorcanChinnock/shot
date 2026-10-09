import AppKit
import os
import ShotCore

private let log = Logger.shot("app")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState()
    lazy var coordinator = CaptureCoordinator(state: state)
    private var defaultsObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        SystemShortcuts.giveBackTextCaptureKeyIfNeeded()
        HotkeyCenter.shared.onPress = { [weak self] action in
            self?.coordinator.perform(action)
        }
        HotkeyCenter.shared.reloadFromPreferences()
        if let launch = Perf.millisecondsSinceLaunch() {
            Perf.signposter.emitEvent("Ready", "launch ms=\(launch)")
        }
        QuickAccessController.shared.onAnnotate = { [weak self] url in
            self?.coordinator.annotate(url)
        }
        GalleryController.shared.onEdit = { [weak self] url in
            self?.coordinator.annotate(url)
        }
        GalleryController.shared.onExportGIF = { [weak self] url in
            self?.coordinator.exportGIF(url)
        }
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                HotkeyCenter.shared.reloadFromPreferences()
            }
        }
        installEditMenu()
        _ = Updater.shared
        Task.detached(priority: .utility) {
            Recorder.sweepLeftoverSegments()
        }
        Permissions.showOnboardingIfNeeded()
        if Permissions.hasScreenCapture {
            SystemShortcuts.takeKeys()
        }
        log.notice("Shot launched")
    }

    /// A recording in progress is stopped and saved first, so quitting, or logging out, doesn't lose it.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard coordinator.isRecording else {
            return .terminateNow
        }
        log.notice("Quitting while recording; saving the recording first")
        Task {
            await coordinator.finishRecording(within: .seconds(10))
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        SystemShortcuts.giveBackKeys()
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
        log.notice("URL received: \(url.absoluteString)")
        if host == "pause" {
            coordinator.togglePause()
            return
        }
        if host == "gallery" {
            GalleryController.shared.show()
            return
        }
        if host == "settings" {
            let name = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "section" }?.value
            MainWindowController.showSettings(section: name.flatMap(SettingsSection.init(rawValue:)))
            return
        }
        if EditorRoute.hosts.contains(host) {
            let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "path" }?.value
            guard let route = EditorRoute(host: host, path: path) else {
                Toast.error("Missing path for \(host)")
                return
            }
            coordinator.edit(route)
            return
        }
        guard let action = ShotAction(rawValue: host) else {
            Toast.error("Unknown action: \(host)")
            return
        }
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        // `shot://record?full=1` predates `shot://record-fullscreen`; keep it working.
        let legacyFull = action == .record && query.contains { $0.name == "full" && $0.value == "1" }
        coordinator.perform(legacyFull ? .recordFullscreen : action)
    }

    /// Shown while a glass window puts Shot in the Dock; otherwise only routes ⌘W to the key window,
    /// ⌘X/⌘C/⌘V/⌘A/⌘Z to text fields and ⌥⌘C/⌥⌘V to the image editor.
    private func installEditMenu() {
        let app = NSMenu(title: "Shot")
        app.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",").target = self
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Shot", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem(title: "Shot", action: nil, keyEquivalent: "")
        appItem.submenu = app

        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        fileItem.submenu = file

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        // The editors'; elsewhere nothing answers them, so they're greyed out. Apply Style to All Images is the image editor's.
        edit.addItem(.separator())
        edit.addItem(withTitle: "Copy Style", action: Selector(("copyStyle:")), keyEquivalent: "c").keyEquivalentModifierMask = [.command, .option]
        edit.addItem(withTitle: "Paste Style", action: Selector(("pasteStyle:")), keyEquivalent: "v").keyEquivalentModifierMask = [.command, .option]
        edit.addItem(withTitle: "Apply Style to All Images", action: Selector(("applyStyleToAllImages:")), keyEquivalent: "")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        let main = NSMenu()
        main.addItem(appItem)
        main.addItem(fileItem)
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    @objc private func showSettings() {
        MainWindowController.showSettings()
    }
}
