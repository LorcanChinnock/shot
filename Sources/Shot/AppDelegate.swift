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
        // First, before anything below saves a setting and makes a new user look like an earlier one.
        WelcomeWindow.loadProgress()
        Preferences.registerDefaults()
        applyAppearance()
        SystemShortcuts.giveBackTextCaptureKeyIfNeeded()
        SystemShortcuts.giveBackFullScreenKeyIfNeeded()
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
        QuickAccessController.shared.onExportGIF = { [weak self] url in
            self?.coordinator.exportGIF(url)
        }
        GalleryController.shared.onEdit = { [weak self] url in
            self?.coordinator.annotate(url)
        }
        GalleryController.shared.onExportGIF = { [weak self] url in
            self?.coordinator.exportGIF(url)
        }
        LegacyAgentCleanup.run(bundleID: Bundle.main.bundleIdentifier ?? "dev.lorcan.Shot.dev")
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                HotkeyCenter.shared.reloadFromPreferences()
                self?.applyAppearance()
            }
        }
        installEditMenu()
        _ = Updater.shared
        Task.detached(priority: .utility) {
            // A loupe left by a run that quit or died mid-pick would otherwise swallow every click.
            ColorSampler.endLoupe()
            await Recorder.recoverLeftoverSegments()
            let swept = TemporaryCaptures.sweep()
            if swept > 0 {
                log.notice("Swept \(swept) old captures taken with saving off")
            }
            let pruned = ProjectStore.app.prune()
            if pruned > 0 {
                log.notice("Pruned \(pruned) projects whose files are gone")
            }
        }
        WelcomeWindow.showIfNeeded()
        // Someone new hasn't been told about the takeover yet; the welcome window's setup step takes the keys.
        if Permissions.hasScreenCapture, WelcomeWindow.progress == .done {
            SystemShortcuts.takeKeys()
        }
        log.notice("Shot launched")
    }

    /// A recording in progress is stopped and saved first, so quitting, or logging out, doesn't lose it.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Editors are asked too when the session ends or Sparkle relaunches to update: Cancel stops either, and nothing
        // is lost silently. A recording is saved first so it isn't lost while the sheets wait.
        let recording = coordinator.isRecording
        guard recording || EditorWindowController.hasUnsavedChanges || VideoEditorWindowController.hasUnsavedChanges else {
            return .terminateNow
        }
        Task {
            if recording {
                log.notice("Quitting while recording; saving the recording first")
                await coordinator.finishRecording(within: .seconds(10))
            }
            var proceed = await EditorWindowController.confirmQuit()
            if proceed {
                proceed = await VideoEditorWindowController.confirmQuit()
            }
            if !proceed {
                log.notice("Quit cancelled from an editor's unsaved changes")
            }
            NSApp.reply(toApplicationShouldTerminate: proceed)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        TextIndexer.shared.stop()
        if ColorSampler.isShowing {
            ColorSampler.endLoupe()
        }
        SystemShortcuts.giveBackKeys()
    }

    /// Opening Shot again from Finder or Spotlight shows Settings, the way back when the menu bar icon is hidden
    /// behind the notch or pushed off a crowded bar.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        log.notice("Reopened; showing Settings")
        MainWindowController.showSettings()
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handle(url)
        }
    }

    private func handle(_ url: URL) {
        guard let scheme = url.scheme, ShotURL.schemes.contains(scheme) else {
            return
        }
        log.notice("URL received: \(url.absoluteString)")
        let route: ShotURL
        do {
            route = try ShotURL(url)
        } catch ShotURL.ParseError.notShot {
            return
        } catch {
            Toast.error(error.localizedDescription)
            return
        }
        switch route {
        case .pause:
            coordinator.togglePause()
        case .gallery:
            GalleryController.shared.show()
        case let .settings(name):
            let section = name.flatMap(SettingsSection.init(rawValue:))
            if let name, section == nil {
                Toast.error("Unknown settings section: \(name)")
                return
            }
            MainWindowController.showSettings(section: section)
        case .welcome:
            WelcomeWindow.showAgain()
        case let .captureTimer(seconds):
            coordinator.captureAfterCountdown(seconds: seconds)
        case let .edit(route):
            coordinator.edit(route)
        case let .action(action, target):
            coordinator.perform(action, target: target)
        }
    }

    /// Shown while a glass window puts Shot in the Dock; otherwise only routes ⌘W to the key window,
    /// ⌘X/⌘C/⌘V/⌘A/⌘Z to text fields and ⌥⌘C/⌥⌘V to the image editor.
    /// Settings › General › Appearance, for every window and panel that doesn't set its own.
    private func applyAppearance() {
        let appearance: NSAppearance? = switch Preferences().appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        if NSApp.appearance != appearance {
            NSApp.appearance = appearance
        }
    }

    private func installEditMenu() {
        let app = NSMenu(title: "Shot")
        app.addItem(withTitle: String(localized: "Settings…"), action: #selector(showSettings), keyEquivalent: ",").target = self
        app.addItem(.separator())
        app.addItem(withTitle: String(localized: "Quit Shot"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem(title: "Shot", action: nil, keyEquivalent: "")
        appItem.submenu = app

        let file = NSMenu(title: String(localized: "File"))
        file.addItem(withTitle: String(localized: "Close Window"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let fileItem = NSMenuItem(title: String(localized: "File"), action: nil, keyEquivalent: "")
        fileItem.submenu = file

        let edit = NSMenu(title: String(localized: "Edit"))
        edit.addItem(withTitle: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: String(localized: "Redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        // The editors'; elsewhere nothing answers them, so they're greyed out. Apply Style to All Images is the image
        // editor's, and Trim Idle Time the video editor's.
        edit.addItem(.separator())
        edit.addItem(withTitle: String(localized: "Copy Style"), action: Selector(("copyStyle:")), keyEquivalent: "c").keyEquivalentModifierMask = [.command, .option]
        edit.addItem(withTitle: String(localized: "Paste Style"), action: Selector(("pasteStyle:")), keyEquivalent: "v").keyEquivalentModifierMask = [.command, .option]
        edit.addItem(withTitle: String(localized: "Apply Style to All Images"), action: Selector(("applyStyleToAllImages:")), keyEquivalent: "")
        edit.addItem(withTitle: String(localized: "Trim Idle Time"), action: Selector(("trimIdleTime:")), keyEquivalent: "")
        edit.addItem(withTitle: String(localized: "Flatten"), action: Selector(("flatten:")), keyEquivalent: "")
        edit.addItem(withTitle: String(localized: "Revert to Original"), action: Selector(("revertToOriginal:")), keyEquivalent: "")
        let editItem = NSMenuItem(title: String(localized: "Edit"), action: nil, keyEquivalent: "")
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
