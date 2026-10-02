import AppKit
import AVFoundation
import os
import ShotCore

private let log = Logger(subsystem: "dev.lorcan.Shot", category: "capture")

@MainActor
final class CaptureCoordinator {
    let state: AppState
    private var busy = false
    private let recorder = Recorder()

    init(state: AppState) {
        self.state = state
        recorder.onFinish = { [weak self] url in
            self?.recordingFinished(url)
        }
        recorder.onError = { [weak self] error in
            self?.state.isRecording = false
            self?.report(error)
        }
        QuickAccessController.shared.onExportGIF = { [weak self] url in
            self?.exportGIF(url)
        }
    }

    /// `fullDisplay` skips the region overlay and records the display under the pointer.
    func perform(_ action: ShotAction, fullDisplay: Bool = false) {
        log.notice("Action received: \(action.rawValue, privacy: .public)")
        if action == .record, recorder.isRecording {
            state.isRecording = false
            Task {
                await recorder.stop()
            }
            return
        }
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
                case .record:
                    try await startRecording(fullDisplay: fullDisplay)
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

    private func startRecording(fullDisplay: Bool) async throws {
        let screens = NSScreen.screens
        let screen: NSScreen
        let region: CGRect
        if fullDisplay {
            guard let pointerScreen = NSScreen.underPointer else {
                throw CaptureError.displayNotFound
            }
            screen = pointerScreen
            region = pointerScreen.frame
        } else {
            let displays = screens.map { OverlayDisplay(frame: $0.frame, scale: $0.backingScaleFactor, image: nil) }
            let windows = SelectionOverlayController.onScreenWindows()
            guard let selection = await SelectionOverlayController.select(displays: displays, windowMode: false, windows: windows, isLive: true) else {
                return
            }
            switch selection {
            case let .area(index, rect):
                screen = screens[index]
                region = rect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
            case let .window(info):
                let primaryHeight = screens.first?.frame.height ?? 0
                let frame = Geometry.flip(info.frame, primaryHeight: primaryHeight)
                screen = screens.first { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) } ?? screens[0]
                region = frame.intersection(screen.frame)
            case let .fullDisplay(index):
                screen = screens[index]
                region = screen.frame
            }
        }
        try await recorder.start(screen: screen, region: region)
        state.isRecording = true
    }

    private func recordingFinished(_ url: URL) {
        state.isRecording = false
        Task {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 480, height: 480)
            let thumbnail = try? await generator.image(at: .zero).image
            QuickAccessController.shared.add(videoURL: url, thumbnail: thumbnail)
        }
    }

    func exportGIF(_ videoURL: URL) {
        let gifURL = FileNaming.uniqueURL(in: videoURL.deletingLastPathComponent(), date: Date(), pathExtension: "gif", prefix: Preferences().filePrefix)
        Toast.show("Exporting GIF…", duration: nil)
        Task {
            do {
                let result = try await GIFExporter.export(videoURL: videoURL, to: gifURL) { fraction in
                    Task { @MainActor in
                        Toast.show("Exporting GIF… \(Int(fraction * 100))%", duration: nil)
                    }
                }
                let note = result.truncated ? " (first \(Int(GIFExporter.maxDuration)) s only)" : ""
                Toast.show("Saved \(gifURL.lastPathComponent)\(note)", duration: .seconds(3))
            } catch {
                Toast.show("GIF export failed: \(error.localizedDescription)", duration: .seconds(3))
            }
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

    /// Runs the enabled after-capture actions: save, copy, then Quick Access or the editor.
    func finish(image original: CGImage, scale originalScale: CGFloat) async throws {
        let prefs = Preferences()
        if prefs.playSound {
            Sound.capture()
        }
        let downscale = prefs.downscaleRetina && originalScale > 1
        let format = prefs.imageFormat
        let source = SendableImage(original)
        let encoded = await Task.detached { () -> (file: Data?, png: Data?, image: SendableImage) in
            let image = downscale ? PNG.downscaled(source.image, scale: originalScale) : source.image
            let scale = downscale ? 1 : originalScale
            let file = PNG.data(from: image, scale: scale, format: format)
            let png = format == .png ? file : PNG.data(from: image, scale: scale)
            return (file, png, SendableImage(image))
        }.value
        guard let fileData = encoded.file, let png = encoded.png else {
            throw CaptureError.encodingFailed
        }
        let image = encoded.image.image
        let scale = downscale ? 1 : originalScale
        var savedURL: URL?
        if prefs.saveAfterCapture || prefs.quickAccessAfterCapture || prefs.openEditorAfterCapture {
            let folder = prefs.saveAfterCapture ? prefs.saveFolder : FileManager.default.temporaryDirectory.appendingPathComponent("Shot")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = FileNaming.uniqueURL(in: folder, date: Date(), pathExtension: format.fileExtension, prefix: prefs.filePrefix)
            try fileData.write(to: url)
            savedURL = url
            log.notice("Saved \(url.path, privacy: .public)")
        }
        if prefs.copyAfterCapture {
            Clipboard.copy(png: png, image: image)
        }
        if let savedURL, prefs.openEditorAfterCapture {
            EditorWindowController.open(savedURL)
        } else if let savedURL, prefs.quickAccessAfterCapture {
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

@MainActor
enum Sound {
    private static let shutter = NSSound(contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif", byReference: true)

    static func capture() {
        shutter?.stop()
        shutter?.play()
    }
}
