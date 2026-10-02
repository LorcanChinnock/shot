import AppKit
import os
import ShotCore

private let log = Logger(subsystem: "dev.lorcan.Shot", category: "capture")

@MainActor
final class CaptureCoordinator {
    let state: AppState
    private var busy = false

    init(state: AppState) {
        self.state = state
    }

    func perform(_ action: ShotAction) {
        log.notice("Action received: \(action.rawValue, privacy: .public)")
        guard !busy else {
            return
        }
        Task {
            busy = true
            defer { busy = false }
            do {
                switch action {
                case .captureFullscreen:
                    try await captureFullscreen()
                default:
                    Toast.show("\(action.title) is not available yet")
                }
            } catch {
                report(error)
            }
        }
    }

    func annotate(_ url: URL) {
        log.notice("Annotate requested: \(url.path, privacy: .public)")
    }

    private func captureFullscreen() async throws {
        guard let screen = NSScreen.underPointer else {
            throw CaptureError.displayNotFound
        }
        let start = ContinuousClock.now
        guard let frozen = try await DisplayCapturer.captureAll(screens: [screen]).first else {
            throw CaptureError.displayNotFound
        }
        log.notice("Fullscreen capture took \(ContinuousClock.now - start, privacy: .public)")
        try await finish(image: frozen.image, scale: frozen.scale)
    }

    /// Runs the enabled after-capture actions: save, copy, Quick Access.
    func finish(image: CGImage, scale: CGFloat) async throws {
        let prefs = Preferences()
        let sendableImage = SendableImage(image)
        let encoded = await Task.detached { PNG.data(from: sendableImage.image, scale: scale) }.value
        guard let png = encoded else {
            throw CaptureError.encodingFailed
        }
        var savedURL: URL?
        if prefs.saveAfterCapture || prefs.quickAccessAfterCapture {
            let folder = prefs.saveAfterCapture ? prefs.saveFolder : FileManager.default.temporaryDirectory.appendingPathComponent("Shot")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = FileNaming.uniqueURL(in: folder, date: Date(), pathExtension: "png")
            try png.write(to: url)
            savedURL = url
            log.notice("Saved \(url.path, privacy: .public)")
        }
        if prefs.copyAfterCapture {
            Clipboard.copy(png: png, image: image)
        }
        if let savedURL, prefs.quickAccessAfterCapture {
            QuickAccessController.shared.add(fileURL: savedURL, thumbnail: image, scale: scale)
        } else {
            Toast.show(prefs.copyAfterCapture ? "Copied to clipboard" : "Saved")
        }
    }

    func report(_ error: Error) {
        log.error("Action failed: \(error.localizedDescription, privacy: .public)")
        if !Permissions.hasScreenCapture {
            Permissions.showOnboarding()
        }
        Toast.show(error.localizedDescription)
    }
}

struct SendableImage: @unchecked Sendable {
    let image: CGImage

    init(_ image: CGImage) {
        self.image = image
    }
}

@MainActor
enum Clipboard {
    static func copy(png: Data, image: CGImage) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let tiff = NSImage(cgImage: image, size: .zero).tiffRepresentation {
            item.setData(tiff, forType: .tiff)
        }
        pasteboard.writeObjects([item])
    }

    static func copy(fileURL: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
    }
}
