import AppKit
import AVFoundation
import os
import Observation
import ShotCore
import SwiftUI

private let log = Logger.shot("quick-access")

struct QuickAccessCard: Identifiable {
    static let width = QuickAccessLayout.cardWidth

    let id = UUID()
    let fileURL: URL
    var thumbnail: NSImage
    let isVideo: Bool
    /// The capture with the style Use this style for new captures gave it, which Copy and dragging use in place of the
    /// plain file; `nil` while it's drawn, and for a capture with no style.
    var styledURL: URL?
    /// A recording's length in seconds, once it's read; `nil` before then and for a screenshot.
    var duration: Double?
    /// "Copied" over the card, for a moment after it's copied.
    var confirmation: ActionConfirmation?
    /// The card is being dragged out, so it shows faded where it was while the lifted copy follows the pointer.
    var isLifted = false
    /// The card was dropped in another app, so it shrinks away as it closes rather than sliding off.
    var wasDropped = false

    var height: CGFloat { QuickAccessLayout.cardHeight(for: thumbnail.size) }
}

@MainActor
@Observable
final class QuickAccessModel {
    var cards: [QuickAccessCard] = []
    /// Whether every card shows in full, as it does while the pointer is on the stack, rather than the older ones
    /// waiting behind the newest.
    var isFannedOut = false

    var layout: QuickAccessLayout { QuickAccessLayout(cardHeights: cards.map(\.height), fannedOut: isFannedOut) }
}

/// A card's action, for its right-click menu and VoiceOver's actions. With `children`, it's a submenu of them instead.
struct QuickAccessCardAction {
    let title: String
    var children: [QuickAccessCardAction] = []
    let perform: () -> Void
}

@MainActor
final class QuickAccessController {
    static let shared = QuickAccessController()
    static let maxCards = 5
    static let inset = QuickAccessLayout.screenInset

    var onAnnotate: ((URL) -> Void)?
    var onExportGIF: ((URL) -> Void)?

    private let model = QuickAccessModel()
    private var panel: FloatingPanelWindow?
    private var timers: [UUID: Task<Void, Never>] = [:]
    private var settleTask: Task<Void, Never>?
    /// Starts a drag when a card is pulled out of the panel.
    private lazy var drag = QuickAccessDrag(controller: self)
    /// The cards VoiceOver's focus is on, which hold every card as the pointer does.
    private var voiceOverFocus: Set<UUID> = []
    /// Watch the pointer while the stack is fanned out, to fold it again once the pointer leaves.
    private var pointerMonitors: [Any] = []

    /// How long a card's exit takes; the panel keeps its size until then so the card isn't clipped mid-slide.
    private static let exitDuration: Duration = .milliseconds(350)

    /// `copied` says the capture went to the clipboard too, which the card confirms once it has slid in.
    func add(fileURL: URL, thumbnail: CGImage, size: NSSize, copied: Bool) {
        add(QuickAccessCard(fileURL: fileURL, thumbnail: NSImage(cgImage: thumbnail, size: size), isVideo: false), copied: copied)
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

    func add(videoURL: URL, thumbnail: CGImage?, copied: Bool) {
        let image = thumbnail.map { NSImage(cgImage: $0, size: .zero) } ?? NSImage(systemSymbolName: "film", accessibilityDescription: nil) ?? NSImage()
        let card = QuickAccessCard(fileURL: videoURL, thumbnail: image, isVideo: true)
        add(card, copied: copied)
        // The length badge comes a moment after the card, so reading the file never holds the card up.
        Task { @MainActor [weak self] in
            guard let seconds = try? await AVURLAsset(url: videoURL).load(.duration).seconds, seconds.isFinite,
                  let self, let index = self.model.cards.firstIndex(where: { $0.id == card.id }) else {
                return
            }
            self.model.cards[index].duration = seconds
        }
    }

    private func add(_ card: QuickAccessCard, copied: Bool) {
        let opening = Perf.begin("Quick Access open")
        settleTask?.cancel()
        ensurePanel()
        // The panel only grows now, so the card that was in front isn't clipped as it moves behind the new one. It takes
        // its exact size once the cards have settled.
        layout(for: model.cards + [card], growOnly: true)
        panel?.orderFrontRegardless()
        // A panel that was just ordered in has to render empty first, or the card has nothing to animate from.
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            withAnimation(Motion.arrive) {
                self.model.cards.append(card)
            }
            Perf.endAtCommit("Quick Access open", opening, "card")
            while self.model.cards.count > Self.maxCards {
                self.remove(self.model.cards[0].id)
            }
            self.startTimer(for: card.id)
            self.settle()
            if copied {
                // Once the card has arrived, so its slide and the confirmation's pop play one after the other.
                try? await Task.sleep(for: .seconds(Moment.panelArrive.duration))
                self.confirm("Copied", on: card.id)
            }
        }
        announce(card)
    }

    /// Tells VoiceOver a card is there, since it may close before the VoiceOver cursor ever reaches the panel. Medium
    /// priority, so it doesn't cut off a toast saying the capture was copied or saved.
    private func announce(_ card: QuickAccessCard) {
        guard let panel else {
            return
        }
        let message = card.isVideo ? String(localized: "Recording ready in Quick Access") : String(localized: "Screenshot ready in Quick Access")
        NSAccessibility.post(element: panel, notification: .announcementRequested, userInfo: [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.medium.rawValue,
        ])
    }

    func remove(_ id: UUID) {
        timers.removeValue(forKey: id)?.cancel()
        voiceOverFocus.remove(id)
        if let styled = model.cards.first(where: { $0.id == id })?.styledURL {
            Self.removeStyled(styled)
        }
        withAnimation(Motion.leave) {
            model.cards.removeAll { $0.id == id }
        }
        if model.cards.isEmpty {
            fold()
        }
        settle()
    }

    /// Once the cards have finished moving, sizes the panel to them, or hides it when there are none, and works the
    /// system shadow out again, since it follows what's drawn.
    private func settle() {
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
                self.panel?.refreshShadow()
            }
        }
    }

    /// Entering a card fans the stack out. Leaving a card restarts its timer. Entering doesn't cancel it: when cards
    /// reflow under a still pointer the exit can be missed, so expiry checks the pointer instead.
    func setHovering(_ hovering: Bool, card id: UUID) {
        if hovering {
            fanOut()
        } else {
            startTimer(for: id)
        }
    }

    /// VoiceOver's focus on a card holds every card, as the pointer on the stack does. Leaving restarts that card's timer.
    func setVoiceOverFocus(_ focused: Bool, card id: UUID) {
        if focused {
            voiceOverFocus.insert(id)
        } else if voiceOverFocus.remove(id) != nil {
            startTimer(for: id)
        }
    }

    /// Shows every card in full, so an older one can be reached. The newest stays where it is, and the older ones move
    /// up above it.
    private func fanOut() {
        guard !model.isFannedOut, model.cards.count > 1 else {
            return
        }
        settleTask?.cancel()
        layout(for: model.cards, fannedOut: true, growOnly: true)
        withAnimation(Motion.arrive) {
            model.isFannedOut = true
        }
        watchPointer()
        settle()
    }

    /// Puts the older cards back behind the newest once the pointer has left the panel.
    private func foldIfPointerLeft() {
        guard model.isFannedOut, !isPointerOverStack else {
            return
        }
        fold()
        settle()
    }

    private func fold() {
        stopWatchingPointer()
        guard model.isFannedOut else {
            return
        }
        withAnimation(Motion.leave) {
            model.isFannedOut = false
        }
    }

    /// The pointer leaving can't be seen from the cards alone: it may leave through a gap between them, where the panel
    /// is see-through and gets no events. So while fanned out, every pointer move checks whether it's left the panel.
    /// A drag doesn't count, so dragging a card out doesn't fold the stack under it.
    private func watchPointer() {
        guard pointerMonitors.isEmpty else {
            return
        }
        let check: @Sendable (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated {
                self?.foldIfPointerLeft()
            }
        }
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: check) {
            pointerMonitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { event in
            check(event)
            return event
        }) {
            pointerMonitors.append(monitor)
        }
    }

    private func stopWatchingPointer() {
        pointerMonitors.forEach(NSEvent.removeMonitor)
        pointerMonitors.removeAll()
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
            // Every card waits while the pointer is on the stack, so none moves under it, and while VoiceOver is on a card.
            if self.isPointerOverStack || !self.voiceOverFocus.isEmpty {
                self.startTimer(for: id)
            } else {
                self.remove(id)
            }
        }
    }

    /// Whether the pointer is on the panel, cards and the gaps between them included.
    private var isPointerOverStack: Bool {
        guard let panel, panel.isVisible else {
            return false
        }
        return panel.frame.contains(NSEvent.mouseLocation)
    }

    private func ensurePanel() {
        if panel == nil {
            // The system shadow follows each card's shape and, unlike one drawn in SwiftUI, needs no margin that
            // would catch clicks.
            let panel = FloatingPanelWindow(contentRect: .zero)
            panel.level = .floating
            panel.becomesKeyOnlyIfNeeded = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            panel.contentView = NSView(hosting: QuickAccessView(model: model, controller: self))
            drag.watch(panel)
            self.panel = panel
        }
    }

    /// How far a card's outer edge sits in from the screen's side and bottom.
    static var cardEdgeInset: CGFloat { inset + QuickAccessLayout.padding }

    /// The top of the cards in screen coordinates while any are showing on `screen`, so a toast there can rest above
    /// them. Nil when the cards are on another display, where they'd say nothing about this one.
    func cardsTop(on screen: NSScreen) -> CGFloat? {
        guard let panel, panel.isVisible, !model.cards.isEmpty, panel.screen == screen else {
            return nil
        }
        return panel.frame.maxY - QuickAccessLayout.padding
    }

    private func layout() {
        layout(for: model.cards)
    }

    /// Sizes and places the panel for `cards`. With `growOnly`, it never gets smaller, so cards still moving aren't clipped.
    private func layout(for cards: [QuickAccessCard], fannedOut: Bool? = nil, growOnly: Bool = false) {
        guard let panel else {
            return
        }
        var size = QuickAccessLayout(cardHeights: cards.map(\.height), fannedOut: fannedOut ?? model.isFannedOut).size
        if growOnly, panel.isVisible {
            size.height = max(size.height, panel.frame.height)
        }
        let screen = NSScreen.underPointer ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let x = Preferences().quickAccessPosition == .left ? visible.minX + Self.inset : visible.maxX - Self.inset - size.width
        let origin = CGPoint(x: x, y: visible.minY + Self.inset)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    /// The card's actions in menu order, with `nil` for a divider: the hover buttons' actions, plus Copy Path and
    /// Show in Finder, which have no button.
    func actions(for card: QuickAccessCard) -> [QuickAccessCardAction?] {
        var actions: [QuickAccessCardAction?] = [
            QuickAccessCardAction(title: String(localized: "Copy")) { self.copy(card) },
            QuickAccessCardAction(title: String(localized: "Copy Path")) { self.copyPath(card) },
        ]
        actions.append(QuickAccessCardAction(title: String(localized: "Save As…")) { self.saveAs(card) })
        actions.append(nil)
        actions.append(QuickAccessCardAction(title: card.isVideo ? String(localized: "Edit Video") : String(localized: "Annotate")) { self.annotate(card) })
        if card.isVideo {
            actions.append(QuickAccessCardAction(title: String(localized: "Export GIF")) { self.exportGIF(card) })
        } else {
            actions.append(QuickAccessCardAction(title: String(localized: "Pin to Screen")) { self.pin(card) })
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
        confirm("Copied", on: card.id)
    }

    /// Copies the file's path as text.
    func copyPath(_ card: QuickAccessCard) {
        Clipboard.copy(string: card.fileURL.path)
        confirm("Copied path", on: card.id)
    }

    /// Shows `message` over the card for `ActionConfirmation.duration`, where the person is looking, rather than as a toast.
    private func confirm(_ message: LocalizedStringResource, on id: UUID) {
        guard let index = model.cards.firstIndex(where: { $0.id == id }) else {
            return
        }
        let confirmation = ActionConfirmation(message)
        model.cards[index].confirmation = confirmation
        confirmation.announce()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: ActionConfirmation.duration)
            guard let self, let index = self.model.cards.firstIndex(where: { $0.id == id }),
                  self.model.cards[index].confirmation?.id == confirmation.id else {
                return
            }
            self.model.cards[index].confirmation = nil
        }
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
            Toast.done("Saved \(destination.lastPathComponent)")
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
            Toast.done("Saved \(destination.lastPathComponent)")
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
        PinController.shared.pin(card.styledURL ?? card.fileURL, styled: card.styledURL != nil, from: screenFrame(of: card.id)) { [weak self] in
            self?.remove(card.id)
        }
    }

    /// Where the card is drawn on screen, or nil when it isn't showing.
    private func screenFrame(of id: UUID) -> CGRect? {
        guard let panel, let frame = windowFrame(of: id) else {
            return nil
        }
        return frame.offsetBy(dx: panel.frame.minX, dy: panel.frame.minY)
    }

    /// Where the card is drawn in the panel, in window coordinates, or nil when it isn't showing.
    func windowFrame(of id: UUID) -> CGRect? {
        guard let panel, panel.isVisible, let index = model.cards.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let layout = model.layout
        guard layout.placements.indices.contains(index) else {
            return nil
        }
        // The layout's frames are in the panel's bottom-left-origin coordinates, as the window's are.
        return layout.placements[index].frame
    }

    /// The card drawn at `point` in the panel's window coordinates, the frontmost where they overlap.
    func card(at point: CGPoint) -> UUID? {
        model.layout.card(at: point).flatMap { model.cards.indices.contains($0) ? model.cards[$0].id : nil }
    }

    func card(withID id: UUID) -> QuickAccessCard? {
        model.cards.first { $0.id == id }
    }

    // MARK: Dragging out

    func dragBegan(_ id: UUID) {
        guard let index = model.cards.firstIndex(where: { $0.id == id }) else {
            return
        }
        withAnimation(Motion.reduced ? nil : Motion.fade) {
            model.cards[index].isLifted = true
        }
    }

    /// A card dropped in another app has done its job, so it shrinks away. One let go nowhere comes back.
    func dragEnded(_ id: UUID, dropped: Bool) {
        guard let index = model.cards.firstIndex(where: { $0.id == id }) else {
            return
        }
        guard dropped else {
            withAnimation(Motion.reduced ? nil : Motion.arrive) {
                model.cards[index].isLifted = false
            }
            return
        }
        model.cards[index].wasDropped = true
        // On the next turn, so the card has drawn with its shrinking transition before it's removed.
        Task { @MainActor [weak self] in
            self?.remove(id)
        }
    }

    func showInFinder(_ card: QuickAccessCard) {
        NSWorkspace.shared.activateFileViewerSelecting([card.fileURL])
    }

    func exportGIF(_ card: QuickAccessCard) {
        onExportGIF?(card.fileURL)
    }
}
