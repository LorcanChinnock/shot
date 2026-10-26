import AppKit
import Carbon.HIToolbox
import os
import Observation
import ShotCore
import SwiftUI

private let log = Logger.shot("quick-access")

struct QuickAccessCard: Identifiable {
    static let width = QuickAccessLayout.cardWidth
    static let minHeight: CGFloat = 135
    static let maxHeight: CGFloat = 180

    let id = UUID()
    let fileURL: URL
    var thumbnail: NSImage
    let isVideo: Bool
    /// The capture with the style Use this style for new captures gave it, which Copy and dragging use in place of the
    /// plain file; `nil` while it's drawn, and for a capture with no style.
    var styledURL: URL?

    var height: CGFloat {
        let size = thumbnail.size
        guard size.width > 0 else {
            return Self.maxHeight
        }
        return min(Self.maxHeight, max(Self.minHeight, (Self.width * size.height / size.width).rounded()))
    }
}

@MainActor
@Observable
final class QuickAccessModel {
    var cards: [QuickAccessCard] = []
    /// The card the keyboard acts on, while Focus Quick Access has handed the cards the keyboard.
    var selected: UUID?
}

/// A card's action, for its right-click menu and the menu Space opens. With `children`, it's a submenu of them instead.
struct QuickAccessCardAction {
    let title: String
    var children: [QuickAccessCardAction] = []
    let perform: () -> Void
}

@MainActor
final class QuickAccessController {
    static let shared = QuickAccessController()
    static let maxCards = 5
    static let inset: CGFloat = 20

    var onAnnotate: ((URL) -> Void)?
    var onExportGIF: ((URL) -> Void)?

    private let model = QuickAccessModel()
    private var panel: QuickAccessPanel?
    private var timers: [UUID: Task<Void, Never>] = [:]
    private var settleTask: Task<Void, Never>?

    /// How long a card's exit takes; the panel keeps its size until then so the card isn't clipped mid-slide.
    private static let exitDuration: Duration = .milliseconds(350)

    func add(fileURL: URL, thumbnail: CGImage, size: NSSize) {
        add(QuickAccessCard(fileURL: fileURL, thumbnail: NSImage(cgImage: thumbnail, size: size), isVideo: false))
    }

    /// Gives the card for the capture at `fileURL` the look Use this style for new captures gives it: `png` for its Copy and
    /// drag, and `thumbnail`, `size` points big, to show. The PNG is written to a temporary file, named as the capture is,
    /// for dragging.
    func setStyled(_ png: Data, thumbnail: CGImage, size: NSSize, of fileURL: URL) async {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Styled captures/\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(fileURL.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("png")
        let written = await Task.detached {
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try png.write(to: url, options: .atomic)
                return true
            } catch {
                log.error("Could not write the styled capture: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }.value
        guard written else {
            return
        }
        guard let index = model.cards.firstIndex(where: { $0.fileURL == fileURL && !$0.isVideo }) else {
            Self.removeStyled(url)
            return
        }
        model.cards[index].thumbnail = NSImage(cgImage: thumbnail, size: size)
        model.cards[index].styledURL = url
        layout()
    }

    /// Deletes a styled capture's temporary file and its folder.
    private static func removeStyled(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    func add(videoURL: URL, thumbnail: CGImage?) {
        let image = thumbnail.map { NSImage(cgImage: $0, size: .zero) } ?? NSImage(systemSymbolName: "film", accessibilityDescription: nil) ?? NSImage()
        add(QuickAccessCard(fileURL: videoURL, thumbnail: image, isVideo: true))
    }

    private func add(_ card: QuickAccessCard) {
        settleTask?.cancel()
        ensurePanel()
        layout(for: model.cards + [card])
        panel?.orderFrontRegardless()
        // A panel that was just ordered in has to render empty first, or the card has nothing to animate from.
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            withAnimation(QuickAccessMotion.enter) {
                self.model.cards.append(card)
            }
            while self.model.cards.count > Self.maxCards {
                self.remove(self.model.cards[0].id)
            }
            self.startTimer(for: card.id)
        }
    }

    func remove(_ id: UUID) {
        timers.removeValue(forKey: id)?.cancel()
        if model.selected == id {
            let index = model.cards.firstIndex { $0.id == id } ?? 0
            let rest = model.cards.filter { $0.id != id }
            if rest.isEmpty {
                endKeyboard()
            } else {
                select(rest[min(index, rest.count - 1)].id)
            }
        }
        if let styled = model.cards.first(where: { $0.id == id })?.styledURL {
            Self.removeStyled(styled)
        }
        withAnimation(QuickAccessMotion.exit) {
            model.cards.removeAll { $0.id == id }
        }
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: Self.exitDuration)
            guard !Task.isCancelled, let self else {
                return
            }
            if self.model.cards.isEmpty {
                self.panel?.orderOut(nil)
            } else {
                self.layout()
            }
        }
    }

    /// Leaving a card restarts its timer. Entering doesn't cancel it: when cards reflow under a
    /// still pointer the exit can be missed, so expiry checks the pointer instead.
    func setHovering(_ hovering: Bool, card id: UUID) {
        if !hovering {
            startTimer(for: id)
        }
    }

    private func startTimer(for id: UUID) {
        timers[id]?.cancel()
        let duration = Preferences().quickAccessDuration
        // Cards wait while the keyboard is on them; `endKeyboard` starts their timers again.
        guard duration > 0, model.selected == nil else {
            return
        }
        timers[id] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self else {
                return
            }
            if self.isPointerOver(id) {
                self.startTimer(for: id)
            } else {
                self.remove(id)
            }
        }
    }

    private func isPointerOver(_ id: UUID) -> Bool {
        guard let panel, panel.isVisible else {
            return false
        }
        guard let index = model.cards.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let frame = QuickAccessLayout(cardHeights: model.cards.map(\.height)).cardFrames[index]
        return frame.offsetBy(dx: panel.frame.minX, dy: panel.frame.minY).contains(NSEvent.mouseLocation)
    }

    private func ensurePanel() {
        if panel == nil {
            let panel = QuickAccessPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            panel.contentView = NSView(hosting: QuickAccessView(model: model, controller: self))
            panel.onKey = { [weak self] in self?.handleKey($0) ?? false }
            panel.onResignKey = { [weak self] in self?.endKeyboard() }
            self.panel = panel
        }
    }

    private func layout() {
        layout(for: model.cards)
    }

    private func layout(for cards: [QuickAccessCard]) {
        guard let panel else {
            return
        }
        let size = QuickAccessLayout(cardHeights: cards.map(\.height)).size
        let screen = NSScreen.underPointer ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let x = Preferences().quickAccessPosition == .left ? visible.minX + Self.inset : visible.maxX - Self.inset - size.width
        let origin = CGPoint(x: x, y: visible.minY + Self.inset)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    // MARK: Keyboard

    /// Hands the keyboard to the newest card, with its buttons showing, until Esc, a click elsewhere, or an action that
    /// leaves the card. The panel never activates Shot, so the app in front stays in front.
    func focusNewest() {
        guard let panel, let newest = model.cards.last else {
            Toast.show("No Quick Access cards to focus")
            return
        }
        for timer in timers.values {
            timer.cancel()
        }
        timers.removeAll()
        panel.acceptsKeys = true
        select(newest.id)
        panel.makeKeyAndOrderFront(nil)
        log.notice("Keyboard on Quick Access, \(self.model.cards.count) cards")
    }

    private func select(_ id: UUID) {
        model.selected = id
        guard let panel, let card = model.cards.first(where: { $0.id == id }) else {
            return
        }
        let name = card.fileURL.lastPathComponent
        let message = card.isVideo
            ? String(localized: "Recording \(name). Return copies it, Space shows its actions, Esc goes back.")
            : String(localized: "Screenshot \(name). Return copies it, Space shows its actions, Esc goes back.")
        NSAccessibility.post(element: panel, notification: .announcementRequested, userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    /// Gives the keyboard back to the app in front and starts the cards' timers again.
    private func endKeyboard() {
        guard model.selected != nil, let panel else {
            return
        }
        model.selected = nil
        panel.acceptsKeys = false
        if panel.isKeyWindow {
            // A panel can't hand key status back to another app, but ordering it out does, and it comes straight back.
            panel.orderOut(nil)
            panel.orderFrontRegardless()
        }
        for card in model.cards {
            startTimer(for: card.id)
        }
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard let index = model.cards.firstIndex(where: { $0.id == model.selected }) else {
            return false
        }
        let card = model.cards[index]
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        switch (Int(event.keyCode), modifiers) {
        case (kVK_Escape, []):
            endKeyboard()
        case (kVK_UpArrow, []):
            select(model.cards[max(index - 1, 0)].id)
        case (kVK_DownArrow, []):
            select(model.cards[min(index + 1, model.cards.count - 1)].id)
        case (kVK_Return, []), (kVK_ANSI_KeypadEnter, []), (kVK_ANSI_C, .command):
            copy(card)
            // Straight back to the app in front, ready to paste.
            endKeyboard()
        case (kVK_ANSI_S, .command):
            saveAs(card)
        case (kVK_ANSI_E, .command):
            annotate(card)
        case (kVK_Delete, []), (kVK_ForwardDelete, []):
            remove(card.id)
        case (kVK_Space, []):
            showMenu(for: card, at: index)
        default:
            return false
        }
        return true
    }

    private func showMenu(for card: QuickAccessCard, at index: Int) {
        guard let view = panel?.contentView else {
            return
        }
        let menu = NSMenu()
        for action in actions(for: card) {
            if let action {
                let item = ClosureMenuItem(title: action.title, perform: action.perform)
                if !action.children.isEmpty {
                    item.submenu = NSMenu()
                    for child in action.children {
                        item.submenu?.addItem(ClosureMenuItem(title: child.title, perform: child.perform))
                    }
                }
                menu.addItem(item)
            } else {
                menu.addItem(.separator())
            }
        }
        // Card frames count up from the bottom; a hosting view counts down.
        let frame = QuickAccessLayout(cardHeights: model.cards.map(\.height)).cardFrames[index]
        let top = view.isFlipped ? view.bounds.height - frame.maxY : frame.maxY
        menu.popUp(positioning: menu.items.first, at: NSPoint(x: frame.minX + 12, y: view.isFlipped ? top + 12 : top - 12), in: view)
    }

    /// The card's actions in menu order, with `nil` for a divider: the hover buttons' actions, plus Copy Path, Copy Text,
    /// Copy Alt Text and Pin, which have no button.
    func actions(for card: QuickAccessCard) -> [QuickAccessCardAction?] {
        var actions: [QuickAccessCardAction?] = [
            QuickAccessCardAction(title: String(localized: "Copy")) { self.copy(card) },
            QuickAccessCardAction(title: String(localized: "Copy Path")) { self.copyPath(card) },
        ]
        if !card.isVideo {
            actions.append(QuickAccessCardAction(title: String(localized: "Copy Text")) {
                Task { await Clipboard.copyText(inImageAt: card.styledURL ?? card.fileURL) }
            })
            if AltTextAction.isAvailable {
                actions.append(QuickAccessCardAction(title: String(localized: "Copy Alt Text")) {
                    Task { await AltTextAction.copy(imageAt: card.styledURL ?? card.fileURL) }
                })
            }
        }
        if BugReportAction.isAvailable {
            actions.append(QuickAccessCardAction(title: String(localized: "Copy Bug Report")) {
                Task { await BugReportAction.copy(fileAt: card.styledURL ?? card.fileURL) }
            })
        }
        actions.append(QuickAccessCardAction(title: String(localized: "Save As…")) { self.saveAs(card) })
        actions.append(nil)
        actions.append(QuickAccessCardAction(title: card.isVideo ? String(localized: "Edit Video") : String(localized: "Annotate")) { self.annotate(card) })
        if card.isVideo {
            actions.append(QuickAccessCardAction(title: String(localized: "Export GIF")) { self.exportGIF(card) })
        } else {
            actions.append(QuickAccessCardAction(title: String(localized: "Pin")) { self.pin(card) })
        }
        actions.append(QuickAccessCardAction(title: String(localized: "Show in Finder")) { self.showInFinder(card) })
        return actions
    }

    // MARK: Card actions

    func copy(_ card: QuickAccessCard) {
        if card.isVideo {
            Clipboard.copy(fileURL: card.fileURL)
        } else if !Clipboard.copy(imageAt: card.styledURL ?? card.fileURL) {
            Toast.error("Couldn't read \(card.fileURL.lastPathComponent)")
            return
        }
        Toast.show("Copied")
    }

    /// Copies the file's path as text.
    func copyPath(_ card: QuickAccessCard) {
        Clipboard.copy(string: card.fileURL.path)
        Toast.show("Copied path")
    }

    func saveAs(_ card: QuickAccessCard) {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = card.fileURL.lastPathComponent
        savePanel.directoryURL = Preferences().saveFolder
        NSApp.activate()
        guard savePanel.runModal() == .OK, let destination = savePanel.url else {
            return
        }
        // Saving over the capture's own file has nothing to copy.
        let source = card.fileURL
        if destination.resolvingSymlinksInPath().standardizedFileURL == source.resolvingSymlinksInPath().standardizedFileURL {
            Toast.show("Saved \(destination.lastPathComponent)")
            return
        }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                // Copy beside the destination first, so a failed copy leaves the old file in place.
                let temporary = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString)-\(destination.lastPathComponent)")
                defer { try? FileManager.default.removeItem(at: temporary) }
                try FileManager.default.copyItem(at: source, to: temporary)
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try FileManager.default.copyItem(at: source, to: destination)
            }
            Toast.show("Saved \(destination.lastPathComponent)")
        } catch {
            Toast.error("Couldn't save: \(error.localizedDescription)")
        }
    }

    func annotate(_ card: QuickAccessCard) {
        remove(card.id)
        onAnnotate?(card.fileURL)
    }

    /// Floats the capture, styled as Copy has it, above other windows; the card goes, as the pin replaces it. It goes once
    /// the pin has read the image, since removing the card deletes the styled file.
    func pin(_ card: QuickAccessCard) {
        PinController.shared.pin(card.styledURL ?? card.fileURL, styled: card.styledURL != nil) { [weak self] in
            self?.remove(card.id)
        }
    }

    func showInFinder(_ card: QuickAccessCard) {
        NSWorkspace.shared.activateFileViewerSelecting([card.fileURL])
    }

    func exportGIF(_ card: QuickAccessCard) {
        onExportGIF?(card.fileURL)
    }
}

/// Becomes key only while Focus Quick Access hands it the keyboard, so clicking a card never takes focus from the app in
/// front.
private final class QuickAccessPanel: NSPanel {
    var acceptsKeys = false
    var onKey: ((NSEvent) -> Bool)?
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool { acceptsKeys }

    // Ahead of the hosted views, which would otherwise take the arrows and Space.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, onKey?(event) == true {
            return
        }
        super.sendEvent(event)
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

private final class ClosureMenuItem: NSMenuItem {
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
