import AppKit
import Observation
import ShotCore
import SwiftUI

struct QuickAccessCard: Identifiable {
    let id = UUID()
    let fileURL: URL
    let thumbnail: NSImage
    let isVideo: Bool
}

@MainActor
@Observable
final class QuickAccessModel {
    var cards: [QuickAccessCard] = []
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
    private var hostingView: NSHostingView<QuickAccessView>?
    private var timers: [UUID: Task<Void, Never>] = [:]

    func add(fileURL: URL, thumbnail: CGImage, scale: CGFloat) {
        let size = NSSize(width: CGFloat(thumbnail.width) / scale, height: CGFloat(thumbnail.height) / scale)
        add(QuickAccessCard(fileURL: fileURL, thumbnail: NSImage(cgImage: thumbnail, size: size), isVideo: false))
    }

    func add(videoURL: URL, thumbnail: CGImage?) {
        let image = thumbnail.map { NSImage(cgImage: $0, size: .zero) } ?? NSImage(systemSymbolName: "film", accessibilityDescription: nil)!
        add(QuickAccessCard(fileURL: videoURL, thumbnail: image, isVideo: true))
    }

    private func add(_ card: QuickAccessCard) {
        model.cards.append(card)
        while model.cards.count > Self.maxCards {
            remove(model.cards[0].id)
        }
        startTimer(for: card.id)
        show()
    }

    func remove(_ id: UUID) {
        timers.removeValue(forKey: id)?.cancel()
        model.cards.removeAll { $0.id == id }
        if model.cards.isEmpty {
            panel?.orderOut(nil)
        } else {
            layout()
        }
    }

    func setHovering(_ hovering: Bool, card id: UUID) {
        if hovering {
            timers.removeValue(forKey: id)?.cancel()
        } else {
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
            if !Task.isCancelled {
                self?.remove(id)
            }
        }
    }

    private func show() {
        if panel == nil {
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.becomesKeyOnlyIfNeeded = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
            let hostingView = NSHostingView(rootView: QuickAccessView(model: model, controller: self))
            panel.contentView = hostingView
            self.panel = panel
            self.hostingView = hostingView
        }
        layout()
        panel?.orderFrontRegardless()
    }

    private func layout() {
        guard let panel, let hostingView else {
            return
        }
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        let screen = NSScreen.underPointer ?? NSScreen.screens[0]
        let origin = CGPoint(x: screen.visibleFrame.minX + Self.inset, y: screen.visibleFrame.minY + Self.inset)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    // MARK: Card actions

    func copy(_ card: QuickAccessCard) {
        if card.isVideo {
            Clipboard.copy(fileURL: card.fileURL)
        } else if let data = try? Data(contentsOf: card.fileURL), let image = PNG.image(at: card.fileURL) {
            Clipboard.copy(png: data, image: image)
        }
        Toast.show("Copied")
    }

    func saveAs(_ card: QuickAccessCard) {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = card.fileURL.lastPathComponent
        savePanel.directoryURL = Preferences().saveFolder
        NSApp.activate()
        guard savePanel.runModal() == .OK, let destination = savePanel.url else {
            return
        }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: card.fileURL, to: destination)
            Toast.show("Saved \(destination.lastPathComponent)")
        } catch {
            Toast.show("Save failed: \(error.localizedDescription)")
        }
    }

    func annotate(_ card: QuickAccessCard) {
        remove(card.id)
        onAnnotate?(card.fileURL)
    }

    func showInFinder(_ card: QuickAccessCard) {
        NSWorkspace.shared.activateFileViewerSelecting([card.fileURL])
    }

    func exportGIF(_ card: QuickAccessCard) {
        onExportGIF?(card.fileURL)
    }
}
