import AppKit
import Observation
import ShotCore

/// Shot's icon in the menu bar and the native menu it opens. The menu is an `NSMenu`, so macOS draws its rows, highlight and
/// shadow, and keyboard navigation, type-to-select and VoiceOver work as in any other menu. Only the Recent row is a custom
/// view (`RecentRowView`), since a menu has no row of pictures, and the keyboard reaches its captures through a native
/// submenu. The menu is rebuilt each time it opens, which costs a
/// handful of items, so it always shows the current shortcuts, recording state and update.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let state: AppState
    private let coordinator: CaptureCoordinator
    private let recent = RecentCapturesStore()
    private let recentRow = RecentRowView()
    /// Made once and added back on each rebuild: a menu item that's let go takes its view out of whichever item holds it now.
    private lazy var recentItems: [NSMenuItem] = {
        let thumbnails = NSMenuItem(title: String(localized: "Recent captures"), action: nil, keyEquivalent: "")
        thumbnails.view = recentRow
        return [.separator(), .sectionHeader(title: String(localized: "Recent")), thumbnails]
    }()

    init(state: AppState, coordinator: CaptureCoordinator) {
        self.state = state
        self.coordinator = coordinator
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        recentRow.onOpen = { [weak self] item in self?.open(item) }
        recent.onChange = { [weak self] in self?.showRecent() }
        updateIcon()
        // Read ahead, off the main thread, so the first open already has its pictures.
        recent.refresh()
    }

    // MARK: Icon

    private func updateIcon() {
        withObservationTracking {
            let image: NSImage
            if state.isRecording, let seconds = state.recordingSeconds {
                image = BrandMark.timerImage(seconds: seconds, paused: state.isPaused, pulse: state.menuBar.pulse)
                statusItem.length = NSStatusItem.variableLength
            } else {
                image = BrandMark.menuBarImage(
                    iconState, updateAvailable: Updater.shared.pendingVersion != nil,
                    flip: state.menuBar.flip, pulse: state.menuBar.pulse
                )
                statusItem.length = NSStatusItem.squareLength
            }
            statusItem.button?.image = image
            statusItem.button?.setAccessibilityLabel(image.accessibilityDescription)
        } onChange: { [weak self] in
            Task { @MainActor in self?.updateIcon() }
        }
    }

    private var iconState: BrandMark.State {
        if state.isPaused {
            return .paused
        }
        if state.isRecording {
            return .recording
        }
        if let seconds = state.countdown {
            return .countdown(seconds)
        }
        return .idle
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if state.isRecording {
            menu.addItem(row(String(localized: "Stop Recording"), symbol: "stop.circle", tint: .record, combo: hotkey(.record)) { [weak self] in
                self?.coordinator.perform(.record)
            })
            let pause = state.isPaused ? String(localized: "Resume Recording") : String(localized: "Pause Recording")
            menu.addItem(row(pause, symbol: state.isPaused ? "play.circle" : "pause.circle") { [weak self] in
                self?.coordinator.togglePause()
            })
            menu.addItem(.separator())
        }
        menu.addItem(action(.screenshot, symbol: "viewfinder"))
        if !state.isRecording {
            menu.addItem(action(.record, symbol: "record.circle", tint: .record))
            menu.addItem(action(.pickColor, symbol: "eyedropper"))
        }
        menu.addItem(row(String(localized: "Gallery"), symbol: "square.grid.2x2") {
            GalleryController.shared.show()
        })

        recentItems.forEach(menu.addItem)
        showRecent()

        menu.addItem(.separator())
        let settings = row(String(localized: "Settings…"), symbol: nil) { MainWindowController.showSettings() }
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(updateRow())
        let quit = row(String(localized: "Quit Shot"), symbol: nil) { NSApp.terminate(nil) }
        quit.keyEquivalent = "q"
        menu.addItem(quit)
    }

    func menuWillOpen(_ menu: NSMenu) {
        recent.refresh()
    }

    func menuDidClose(_ menu: NSMenu) {
        recentRow.menuClosed()
    }

    /// A menu keeps the arrow keys and Return to itself, so a custom view in it can't take them. When the keyboard lands on
    /// the Recent row, the row draws as highlighted and gets a submenu listing the same captures, which Right opens like any
    /// other. The pointer never gets the submenu, so it can't pop out over the menu while someone aims at a thumbnail.
    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        guard let rowItem = recentItems.last else {
            return
        }
        let byKeyboard = item === rowItem && NSApp.currentEvent?.type == .keyDown
        recentRow.isHighlighted = byKeyboard
        if item === rowItem {
            rowItem.submenu = byKeyboard ? recentList() : nil
        }
    }

    private func recentList() -> NSMenu {
        let list = NSMenu(title: String(localized: "Recent captures"))
        for entry in recent.entries {
            let item = MenuActionItem(title: entry.item.recentLabel) { [weak self] in self?.open(entry.item) }
            item.image = Self.listThumbnail(entry.thumbnail?.image)
            item.toolTip = entry.item.name
            list.addItem(item)
        }
        return list
    }

    /// A 30 × 20 copy of a thumbnail for the keyboard's list, cropped and rounded as in the row.
    private static func listThumbnail(_ image: NSImage?) -> NSImage {
        NSImage(size: NSSize(width: 30, height: 20), flipped: false) { rect in
            RecentThumbnailView.drawPicture(image, in: rect, radius: Brutal.Radius.tiny)
            return true
        }
    }

    /// Shows or hides the Recent section, and gives the row its captures, without rebuilding the menu, so it can fill in
    /// while the menu is open.
    private func showRecent() {
        recentRow.entries = recent.entries
        recentItems.forEach { $0.isHidden = recent.entries.isEmpty }
    }

    /// Opens a capture in its editor. It runs while the click or Return is still being handled, as every other menu action
    /// does, since macOS lets an app come to the front only in answer to the person's own input.
    private func open(_ item: GalleryItem) {
        menu.cancelTracking()
        coordinator.annotate(item.url)
    }

    private func updateRow() -> NSMenuItem {
        let updater = Updater.shared
        if let version = updater.pendingVersion {
            return row(String(localized: "Update to Shot \(version)…"), symbol: nil) { updater.checkForUpdates() }
        }
        let item = row(String(localized: "Check for Updates…"), symbol: nil) { updater.checkForUpdates() }
        item.isEnabled = updater.canCheckForUpdates
        return item
    }

    private func hotkey(_ action: ShotAction) -> KeyCombo? {
        Preferences().hotkey(for: action)
    }

    private func action(_ action: ShotAction, symbol: String, tint: Tint? = nil) -> NSMenuItem {
        row(action.title, symbol: symbol, tint: tint, combo: hotkey(action)) { [weak self] in
            self?.coordinator.perform(action)
        }
    }

    enum Tint {
        case record
    }

    private func row(_ title: String, symbol: String?, tint: Tint? = nil, combo: KeyCombo? = nil, perform: @escaping () -> Void) -> NSMenuItem {
        let item = MenuActionItem(title: title, perform: perform)
        if let symbol {
            item.image = Self.icon(symbol, tint: tint)
        }
        if let (key, modifiers) = combo?.menuKeyEquivalent {
            item.keyEquivalent = key
            item.keyEquivalentModifierMask = modifiers
        }
        return item
    }

    /// The board's 15 pt line icons. Untinted icons stay templates, so the menu draws them in its text colour and inverts
    /// them on the highlight, the way every native menu does. Record keeps its red.
    private static func icon(_ symbol: String, tint: Tint?) -> NSImage? {
        var configuration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        if tint == .record {
            configuration = configuration.applying(.init(paletteColors: [NSColor(Brutal.record)]))
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
        image?.isTemplate = tint == nil
        return image
    }
}

/// A menu item that runs a closure, so the menu needs no selectors.
private final class MenuActionItem: NSMenuItem {
    private let perform: () -> Void

    init(title: String, perform: @escaping () -> Void) {
        self.perform = perform
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func run() {
        perform()
    }
}

extension KeyCombo {
    /// Keys whose menu key equivalent isn't the character they type.
    private static let specialKeys: [UInt32: Int] = [
        49: 0x20, 36: 0x0D, 48: 0x09, 53: 0x1B, 51: 0x08, 117: NSDeleteFunctionKey,
        123: NSLeftArrowFunctionKey, 124: NSRightArrowFunctionKey, 125: NSDownArrowFunctionKey, 126: NSUpArrowFunctionKey,
        115: NSHomeFunctionKey, 119: NSEndFunctionKey, 116: NSPageUpFunctionKey, 121: NSPageDownFunctionKey,
    ]

    /// The key and modifiers an `NSMenuItem` shows for this shortcut, or nil for a key a menu can't show.
    var menuKeyEquivalent: (String, NSEvent.ModifierFlags)? {
        let key: String
        if let special = Self.specialKeys[keyCode], let scalar = UnicodeScalar(special) {
            key = String(Character(scalar))
        } else if keyLabel.count == 1 {
            key = keyLabel.lowercased()
        } else {
            return nil
        }
        let flags = eventFlags
        var modifiers: NSEvent.ModifierFlags = []
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        return (key, modifiers)
    }
}
