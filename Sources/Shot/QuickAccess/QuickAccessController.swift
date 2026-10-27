import AppKit
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
    private var panel: NSPanel?
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
        guard duration > 0 else {
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
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            panel.contentView = NSView(hosting: QuickAccessView(model: model, controller: self))
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

    /// The card's actions in menu order, with `nil` for a divider: the hover buttons' actions, plus Copy Path, Copy Text,
    /// Pin, which have no button.
    func actions(for card: QuickAccessCard) -> [QuickAccessCardAction?] {
        var actions: [QuickAccessCardAction?] = [
            QuickAccessCardAction(title: String(localized: "Copy")) { self.copy(card) },
            QuickAccessCardAction(title: String(localized: "Copy Path")) { self.copyPath(card) },
        ]
        if !card.isVideo {
            actions.append(QuickAccessCardAction(title: String(localized: "Copy Text")) {
                Task { await Clipboard.copyText(inImageAt: card.styledURL ?? card.fileURL) }
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
