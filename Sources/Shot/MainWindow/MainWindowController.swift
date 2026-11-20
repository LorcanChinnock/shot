import AppKit
import ShotCore
import SwiftUI

/// What the one Shot window shows: the library, or the settings pages.
@MainActor
@Observable
final class MainWindowNavigation {
    enum Page {
        case library, settings
    }

    static let shared = MainWindowNavigation()
    var page: Page = .library
    /// Set by "Show all in library", which shows every matching capture in the grid. A new search clears it.
    var showAllCaptures = false
    /// Whether a setting matches the search, which the library learns from `SettingsMatchProbe`.
    var settingsMatch = false
    /// The window's width, for whether the sidebar fits.
    var width = MainWindowLayout.minWidth
    /// Set when the sidebar button shows the sidebar in a window too narrow for it. Widening the window clears it.
    var revealsSidebar = false

    func sidebarFits(width sidebarWidth: Double) -> Bool {
        MainWindowLayout.sidebarFits(windowWidth: width, sidebarWidth: sidebarWidth)
    }

    func showsSidebar(wanted: Bool, width sidebarWidth: Double) -> Bool {
        MainWindowLayout.showsSidebar(windowWidth: width, sidebarWidth: sidebarWidth, wanted: wanted, revealed: revealsSidebar)
    }

    /// The search, which the library's field and the settings pages' field share: `MainWindowView` keeps the gallery's
    /// query and the settings query the same.
    var query: String {
        page == .library ? GalleryController.shared.model.query : SettingsNavigation.shared.query
    }

    /// What fills the window beside the sidebar for the search.
    var content: MainWindowSearch.Content {
        MainWindowSearch.content(query: query, page: page == .library ? .library : .settings, settingsMatch: settingsMatch, showAllCaptures: showAllCaptures)
    }

    /// Shows the library, ending any search.
    func openLibrary() {
        clearSearch()
        page = .library
    }

    /// Shows the settings pages, at `section` when one is given, ending any search.
    func openSettings(_ section: SettingsSection? = nil) {
        clearSearch()
        if let section {
            SettingsNavigation.shared.open(section)
        }
        page = .settings
    }

    /// "Show all in library": every capture that matches the search, in the grid, keeping the search.
    func showAllInLibrary() {
        showAllCaptures = true
        page = .library
    }

    /// Previews a capture from the search results in the library, with the rest of the matches behind it.
    func preview(_ item: GalleryItem) {
        showAllInLibrary()
        GalleryController.shared.model.preview(item)
    }

    func clearSearch() {
        SettingsNavigation.shared.query = ""
        GalleryController.shared.model.query = ""
        showAllCaptures = false
        settingsMatch = false
    }
}

/// Hands each key to the half of the window that's showing: the gallery's ⌘ shortcuts and plain keys on the library, ↑ and ↓
/// between sections on the settings pages.
private final class MainWindow: NSWindow {
    var onCommand: ((String, Bool) -> Bool)?
    var onKey: ((NSEvent) -> Bool)?
    var onTextKey: ((NSEvent) -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), let key = event.charactersIgnoringModifiers?.lowercased(), onCommand?(key, flags.contains(.shift)) == true {
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Esc leaves the gallery's search field before the field sees it, so the next arrow moves through the grid.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, firstResponder is NSText, onTextKey?(event) == true {
            return
        }
        super.sendEvent(event)
    }

    /// The end of the responder chain, so a button, slider or sidebar row that Tab focused keeps Space and the arrow keys.
    override func keyDown(with event: NSEvent) {
        if onKey?(event) == true {
            return
        }
        super.keyDown(with: event)
    }
}

/// The one Shot window, holding the library and Settings, while `PreferenceKey.oneWindow` is on (#1460). It replaces
/// `GalleryWindowController` and `SettingsWindowController`, and opens where it was last closed, at the same size.
@MainActor
enum MainWindowController {
    private(set) static var window: NSWindow?
    private static var contentReleased = false
    static let size = GalleryWindowController.size
    /// The toolbar and two columns of thumbnails, with the sidebar hidden.
    static let minSize = NSSize(width: MainWindowLayout.minWidth, height: SettingsWindowController.minSize.height)
    /// The user defaults name AppKit saves the window's frame under.
    private static let frameName = "Shot"

    /// The window's ID for screen capture, so captures can include it while Shot's overlays stay out.
    static var windowID: CGWindowID? { window.map { CGWindowID($0.windowNumber) } }

    static func showLibrary() {
        MainWindowNavigation.shared.openLibrary()
        show()
        // Keeps the search field from taking focus, so the arrow keys move through the grid.
        window?.makeFirstResponder(nil)
    }

    static func showSettings(section: SettingsSection? = nil) {
        MainWindowNavigation.shared.openSettings(section)
        show()
    }

    private static func show() {
        Perf.measureWindowOpen("main")
        if window == nil {
            makeWindow()
        }
        guard let window else {
            return
        }
        if contentReleased {
            GlassWindow.setContent(of: window) { MainWindowView() }
            contentReleased = false
        }
        GlassWindow.present(window)
        window.invalidateShadow()
    }

    private static func makeWindow() {
        let visible = (NSScreen.underPointer ?? NSScreen.screens[0]).visibleFrame
        let window = MainWindow()
        GlassWindow.make(window, size: NSSize(width: min(size.width, visible.width), height: min(size.height, visible.height)), title: String(localized: "Shot"), resizable: true) {
            MainWindowView()
        }
        window.minSize = minSize
        // `make` centres the window; a frame saved from an earlier session puts it back where it was.
        window.setFrameUsingName(frameName)
        window.setFrameAutosaveName(frameName)
        let navigation = MainWindowNavigation.shared
        let gallery = GalleryController.shared
        // While search results cover the grid, the grid's keys would act on captures out of sight, so only ⌘F and ⌘W reach it.
        let showingResults = { navigation.page == .library && navigation.content == .results }
        window.onCommand = { key, shift in
            guard navigation.page == .library, !showingResults() || ["f", "w"].contains(key) else {
                return false
            }
            return gallery.handleCommand(key, shift: shift, in: window)
        }
        window.onTextKey = { event in
            guard navigation.page == .library else {
                return false
            }
            // Esc in the search field ends a search showing results, back to the library as it was.
            if showingResults(), event.keyCode == 53 {
                navigation.clearSearch()
                window.makeFirstResponder(nil)
                return true
            }
            return gallery.handleKey(event, in: window)
        }
        window.onKey = { event in
            switch navigation.page {
            case .library:
                return !showingResults() && gallery.handleKey(event, in: window)
            case .settings:
                guard event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else {
                    return false
                }
                return SettingsWindowController.moveBetweenSections(keyCode: event.keyCode, in: window)
            }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated {
                gallery.model.reload()
            }
        }
        // The window is kept when closed, so its views never disappear on their own: turn off any camera or microphone test,
        // stop watching the folder, and once closed drop the views. `show` builds them again.
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated {
                DevicePreview.stopAll()
                gallery.model.stop()
                DispatchQueue.main.async {
                    guard !window.isVisible else {
                        return
                    }
                    window.contentView = NSView()
                    contentReleased = true
                }
            }
        }
        self.window = window
    }
}

/// The library or the settings pages, filling the window. The gallery keeps watching the save folder while the window is
/// open, whichever is shown, so going back to the library is instant.
private struct MainWindowView: View {
    @Bindable private var navigation = MainWindowNavigation.shared
    private let settings = SettingsNavigation.shared

    var body: some View {
        let model = GalleryController.shared.model
        Group {
            switch navigation.page {
            case .library:
                GalleryRootView(model: model)
            case .settings:
                SettingsView()
            }
        }
        .environment(\.inMainWindow, true)
        .onGeometryChange(for: Double.self) { $0.size.width } action: { width in
            navigation.width = width
            // Back to the sidebar button's own choice once the widest sidebar either page can have fits. Clearing it
            // sooner would hide a sidebar someone showed before there's room for it.
            if navigation.revealsSidebar, MainWindowLayout.sidebarFits(windowWidth: width, sidebarWidth: max(SettingsView.sidebarWidths.upperBound, GalleryModel.sidebarWidths.upperBound)) {
                navigation.revealsSidebar = false
            }
        }
        // One search: typing on either page searches both captures and settings.
        .onChange(of: model.query) {
            if settings.query != model.query {
                settings.query = model.query
            }
            // A new search starts from the results again, rather than the grid "Show all in library" left.
            navigation.showAllCaptures = false
        }
        .onChange(of: settings.query) {
            if model.query != settings.query {
                model.query = settings.query
            }
        }
        .onAppear { model.start() }
        .onDisappear { model.stop() }
        .frame(minWidth: MainWindowController.minSize.width, maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EnvironmentValues {
    /// True inside the one Shot window, where the library and Settings sidebars link to each other rather than to a window.
    @Entry var inMainWindow = false
}
