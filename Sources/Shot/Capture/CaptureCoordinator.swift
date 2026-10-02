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
                case .captureArea:
                    try await captureWithOverlay(windowMode: false, text: false)
                case .captureWindow:
                    try await captureWithOverlay(windowMode: true, text: false)
                case .captureText:
                    try await captureWithOverlay(windowMode: false, text: true)
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
        EditorWindowController.open(url)
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

    private func captureWithOverlay(windowMode: Bool, text: Bool) async throws {
        let start = ContinuousClock.now
        let windows = SelectionOverlayController.onScreenWindows()
        let frozen = try await DisplayCapturer.captureAll()
        log.notice("Freeze capture of \(frozen.count) displays took \(ContinuousClock.now - start, privacy: .public)")
        let displays = frozen.map { OverlayDisplay(frame: $0.frame, scale: $0.scale, image: $0.image) }
        guard let selection = await SelectionOverlayController.select(displays: displays, windowMode: windowMode, windows: windows) else {
            return
        }
        let image: CGImage
        let scale: CGFloat
        switch selection {
        case let .area(index, rect):
            let display = frozen[index]
            let pixels = Geometry.pixelRect(forViewRect: rect, viewHeight: display.frame.height, scale: display.scale)
            guard let cropped = display.image.cropping(to: pixels) else {
                throw CaptureError.encodingFailed
            }
            image = cropped
            scale = display.scale
        case let .window(info):
            let result = try await WindowCapturer.capture(windowID: info.windowID, includeShadow: !text && Preferences().windowShadow)
            image = result.image
            scale = result.scale
        case let .fullDisplay(index):
            image = frozen[index].image
            scale = frozen[index].scale
        }
        if text {
            try await recognizeText(in: image)
        } else {
            try await finish(image: image, scale: scale)
        }
    }

    private func recognizeText(in image: CGImage) async throws {
        let sendableImage = SendableImage(image)
        let text = try await Task.detached { try OCR.recognizeText(in: sendableImage.image) }.value
        guard !text.isEmpty else {
            Toast.show("No text found")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Toast.show("Copied \(text.count) characters")
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
