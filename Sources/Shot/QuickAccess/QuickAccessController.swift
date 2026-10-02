import AppKit
import Observation
import ShotCore
import SwiftUI

struct QuickAccessCard: Identifiable {
    static let width: CGFloat = 240
    static let minHeight: CGFloat = 135
    static let maxHeight: CGFloat = 180

    let id = UUID()
    let fileURL: URL
    let thumbnail: NSImage
    let isVideo: Bool

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

@MainActor
final class QuickAccessController {
    static let shared = QuickAccessController()
    static let maxCards = 5
    static let inset: CGFloat = 20
    static let spacing: CGFloat = 14
    /// Leaves room for the cards' hard shadows.
    static let padding: CGFloat = 10

    var onAnnotate: ((URL) -> Void)?
    var onExportGIF: ((URL) -> Void)?

    private let model = QuickAccessModel()
    private var panel: NSPanel?
    private var timers: [UUID: Task<Void, Never>] = [:]

    func add(fileURL: URL, thumbnail: CGImage, scale: CGFloat) {
        let size = NSSize(width: CGFloat(thumbnail.width) / scale, height: CGFloat(thumbnail.height) / scale)
        add(QuickAccessCard(fileURL: fileURL, thumbnail: NSImage(cgImage: thumbnail, size: size), isVideo: false))
    }

    func add(videoURL: URL, thumbnail: CGImage?) {
        let image = thumbnail.map { NSImage(cgImage: $0, size: .zero) } ?? NSImage(systemSymbolName: "film", accessibilityDescription: nil) ?? NSImage()
        add(QuickAccessCard(fileURL: videoURL, thumbnail: image, isVideo: true))
    }

    private func add(_ card: QuickAccessCard) {
        withAnimation(.easeOut(duration: 0.2)) {
            model.cards.append(card)
        }
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
        }
        layout()
        panel?.orderFrontRegardless()
    }

    private func layout() {
        guard let panel else {
            return
        }
        let cardsHeight = model.cards.reduce(0) { $0 + $1.height } + Self.spacing * CGFloat(max(0, model.cards.count - 1))
        let size = CGSize(width: QuickAccessCard.width + Self.padding * 2, height: cardsHeight + Self.padding * 2)
        let screen = NSScreen.underPointer ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let x = Preferences().quickAccessPosition == .left ? visible.minX + Self.inset : visible.maxX - Self.inset - size.width
        let origin = CGPoint(x: x, y: visible.minY + Self.inset)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
    }

    // MARK: Card actions

    func copy(_ card: QuickAccessCard) {
        if card.isVideo {
            Clipboard.copy(fileURL: card.fileURL)
        } else if let image = PNG.image(at: card.fileURL), let png = pngData(for: card.fileURL, image: image) {
            Clipboard.copy(png: png, image: image)
        } else {
            Toast.show("Could not read \(card.fileURL.lastPathComponent)")
            return
        }
        Toast.show("Copied")
    }

    /// The file's own bytes when it is a PNG; JPEG and other captures are re-encoded.
    private func pngData(for url: URL, image: CGImage) -> Data? {
        if ImageFormat(fileExtension: url.pathExtension) == .png {
            return try? Data(contentsOf: url)
        }
        return PNG.data(from: image, scale: PNG.scale(ofFileAt: url))
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
