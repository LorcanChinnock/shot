import AppKit
import AVFoundation
import os
import ShotCore
import UniformTypeIdentifiers

private let log = Logger.shot("capture")

@MainActor
final class CaptureCoordinator {
    let state: AppState
    private var busy = false
    private let recorder = Recorder()
    private var setup: RecordingSetupController?
    /// The region being recorded, as an AppKit global rect.
    private var recordingRegion = CGRect.zero

    init(state: AppState) {
        self.state = state
        recorder.onFinish = { [weak self] url in
            self?.recordingFinished(url)
        }
        recorder.onPhaseChange = { [weak self] phase in
            self?.state.isRecording = phase == .recording || phase == .paused
            self?.state.isPaused = phase == .paused
        }
        recorder.onStopRequested = { [weak self] discard in
            self?.stopRecording(discard: discard)
        }
        recorder.onError = { [weak self] error in
            self?.state.isRecording = false
            self?.report(error)
        }
        QuickAccessController.shared.onExportGIF = { [weak self] url in
            self?.exportGIF(url)
        }
    }

    func perform(_ action: ShotAction) {
        log.notice("Action received: \(action.rawValue, privacy: .public)")
        if action.isRecording, recorder.isRecording {
            stopRecording(discard: false)
            return
        }
        if action.isRecording, let setup {
            setup.confirm()
            return
        }
        guard !busy else {
            return
        }
        busy = true
        Task {
            defer { busy = false }
            do {
                switch action {
                case .captureFullscreen:
                    try await captureFullscreen()
                case .captureArea:
                    try await captureWithOverlay(windowMode: false)
                case .captureWindow:
                    try await captureWithOverlay(windowMode: true)
                case .record:
                    try await startRecording(mode: .area)
                case .recordFullscreen:
                    try await startRecording(mode: .screen)
                case .recordWindow:
                    try await startRecording(mode: .window)
                }
            } catch {
                report(error)
            }
        }
    }

    /// Opens a capture in the editor that suits it.
    func annotate(_ url: URL) {
        edit(EditorRoute(fileURL: url))
    }

    func edit(_ route: EditorRoute) {
        switch route {
        case let .image(url):
            log.notice("Annotate requested: \(url.path)")
            EditorWindowController.open(url)
        case let .video(url):
            log.notice("Video edit requested: \(url.path)")
            VideoEditorWindowController.open(url)
        }
    }

    private func captureFullscreen() async throws {
        guard let screen = NSScreen.underPointer else {
            throw CaptureError.displayNotFound
        }
        let start = ContinuousClock.now
        guard let frozen = try await DisplayCapturer.captureAll(screens: [screen]).first else {
            throw CaptureError.displayNotFound
        }
        log.debug("Fullscreen capture took \(ContinuousClock.now - start, privacy: .public)")
        let visible = screen.fullCaptureFrame.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        let pixels = Geometry.pixelRect(forViewRect: visible, viewHeight: frozen.frame.height, scale: frozen.scale)
        guard let image = frozen.image.cropping(to: pixels) else {
            throw CaptureError.encodingFailed
        }
        try await finish(image: image, scale: frozen.scale, from: screen.fullCaptureFrame)
    }

    private func captureWithOverlay(windowMode: Bool) async throws {
        let start = ContinuousClock.now
        let windows = SelectionOverlayController.onScreenWindows()
        let frozen = try await DisplayCapturer.captureAll()
        log.debug("Freeze capture of \(frozen.count) displays took \(ContinuousClock.now - start, privacy: .public)")
        let displays = frozen.map { OverlayDisplay(frame: $0.frame, scale: $0.scale, image: $0.image) }
        guard let selection = await SelectionOverlayController.select(displays: displays, windowMode: windowMode, windows: windows) else {
            return
        }
        let image: CGImage
        let scale: CGFloat
        let frame: CGRect
        switch selection {
        case let .area(index, rect):
            let display = frozen[index]
            let pixels = Geometry.pixelRect(forViewRect: rect, viewHeight: display.frame.height, scale: display.scale)
            guard let cropped = display.image.cropping(to: pixels) else {
                throw CaptureError.encodingFailed
            }
            image = cropped
            scale = display.scale
            frame = rect.offsetBy(dx: display.frame.minX, dy: display.frame.minY)
        case let .window(info):
            let result = try await WindowCapturer.capture(windowID: info.windowID, includeShadow: Preferences().windowShadow)
            image = result.image
            scale = result.scale
            frame = Geometry.flip(info.frame, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
        case let .fullDisplay(index):
            image = frozen[index].image
            scale = frozen[index].scale
            frame = frozen[index].frame
        }
        try await finish(image: image, scale: scale, from: frame)
    }

    func togglePause() {
        Task {
            await recorder.togglePause()
        }
    }

    func stopRecording(discard: Bool) {
        Task {
            await recorder.stop(discard: discard)
        }
    }

    /// Frames the recording, then waits for Record and the countdown before starting.
    private func startRecording(mode: RecordingMode) async throws {
        guard let (screen, region, windowID) = await RecordingSetupController.pickRegion(mode: mode) else {
            return
        }
        let controller = RecordingSetupController(mode: mode, screen: screen, region: region, windowID: windowID)
        setup = controller
        let result = await controller.run()
        setup = nil
        guard case let .start(screen, region, windowID) = result else {
            return
        }
        recordingRegion = region
        try await recorder.start(screen: screen, region: region, windowID: windowID)
    }

    private func recordingFinished(_ url: URL) {
        state.isRecording = false
        if Preferences().copyAfterRecording {
            Clipboard.copy(fileURL: url)
        }
        Confetti.burst(from: recordingRegion)
        Task {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 480, height: 480)
            let thumbnail = try? await generator.image(at: .zero).image
            QuickAccessController.shared.add(videoURL: url, thumbnail: thumbnail)
        }
    }

    /// Uses the video editor's last GIF settings.
    func exportGIF(_ videoURL: URL) {
        let prefs = Preferences()
        let options = prefs.videoExportOptions
        let gifURL = FileNaming.uniqueURL(in: videoURL.deletingLastPathComponent(), date: Date(), pathExtension: "gif", prefix: prefs.filePrefix)
        Toast.show("Exporting GIF…", duration: nil)
        Task {
            do {
                let result = try await GIFExporter.export(videoURL: videoURL, to: gifURL, fps: Double(options.gifFrameRate), maxWidth: options.gifMaxWidth) { fraction in
                    Task { @MainActor in
                        Toast.show("Exporting GIF… \(Int(fraction * 100))%", duration: nil)
                    }
                }
                let note = result.truncated ? " (first \(Int(GIFExporter.maxDuration)) s only)" : ""
                Toast.show("Saved \(gifURL.lastPathComponent)\(note)", duration: .seconds(3))
            } catch {
                Toast.error("GIF export failed: \(error.localizedDescription)")
            }
        }
    }

    /// Runs the enabled after-capture actions: save, copy, then Quick Access or the editor. `frame` is where the capture was
    /// on screen, as an AppKit global rect.
    func finish(image original: CGImage, scale originalScale: CGFloat, from frame: CGRect) async throws {
        let prefs = Preferences()
        if prefs.playSound {
            Sound.capture()
        }
        let downscale = prefs.downscaleRetina && originalScale > 1
        let format = prefs.imageFormat
        let source = SendableImage(original)
        let encoded = await Task.detached { () -> (file: Data?, png: Data?, image: SendableImage) in
            let image = downscale ? ImageCodec.downscaled(source.image, scale: originalScale) : source.image
            let scale = downscale ? 1 : originalScale
            let file = ImageCodec.data(from: image, scale: scale, format: format)
            let png = format == .png ? file : ImageCodec.data(from: image, scale: scale)
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
            log.notice("Saved \(url.path)")
        }
        if prefs.copyAfterCapture {
            Clipboard.copy(png: png, image: image)
        }
        if let savedURL, prefs.openEditorAfterCapture {
            EditorWindowController.open(savedURL)
        } else if let savedURL, prefs.quickAccessAfterCapture {
            QuickAccessController.shared.add(fileURL: savedURL, thumbnail: image, scale: scale)
        } else if prefs.copyAfterCapture {
            Toast.show("Copied to clipboard")
        } else if savedURL != nil {
            Toast.show("Saved")
        }
        Confetti.burst(from: frame)
    }

    func report(_ error: Error) {
        log.error("Action failed: \(error.localizedDescription, privacy: .public)")
        if !Permissions.hasScreenCapture {
            Permissions.showOnboarding()
        }
        Toast.error(error.localizedDescription)
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

    /// Copies the image as PNG, which is the file's own bytes when it is one; false if it can't be read.
    static func copy(imageAt url: URL) -> Bool {
        guard let image = ImageCodec.image(at: url) else {
            return false
        }
        let png = ImageFormat(fileExtension: url.pathExtension) == .png ? try? Data(contentsOf: url) : nil
        guard let data = png ?? ImageCodec.data(from: image, scale: ImageCodec.scale(ofFileAt: url)) else {
            return false
        }
        copy(png: data, image: image)
        return true
    }

    static func copy(fileURL: URL) {
        copy(fileURLs: [fileURL])
    }

    static func copy(fileURLs: [URL]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(fileURLs.map { $0 as NSURL })
    }

    private static let annotationType = NSPasteboard.PasteboardType(AnnotationClipboard.pasteboardType)

    static func copy(annotation: Annotation) throws {
        let data = try AnnotationClipboard.data(for: annotation)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setData(data, forType: annotationType)
    }

    /// The annotation on the pasteboard, or `nil` if it holds something else.
    static func annotation() throws -> Annotation? {
        guard let data = NSPasteboard.general.data(forType: annotationType) else {
            return nil
        }
        return try AnnotationClipboard.annotation(from: data)
    }

    private static let imageFiles: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true,
        .urlReadingContentsConformToTypes: [UTType.image.identifier],
    ]

    /// Whether `pasteboard` holds an image `images(on:)` can read, without reading it.
    static func hasImages(on pasteboard: NSPasteboard) -> Bool {
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            return pasteboard.canReadObject(forClasses: [NSURL.self], options: imageFiles)
        }
        return imageType(on: pasteboard) != nil
    }

    /// The images on `pasteboard`, encoded: the contents of each image file, else its PNG, else its
    /// first image type. Files that aren't images give nothing, rather than the icon Finder copies with them.
    static func images(on pasteboard: NSPasteboard) -> [Data] {
        if pasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) {
            let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: imageFiles) as? [URL] ?? []
            return urls.compactMap { url in
                do {
                    return try Data(contentsOf: url)
                } catch {
                    Toast.error("Could not read \(url.lastPathComponent): \(error.localizedDescription)")
                    return nil
                }
            }
        }
        return imageType(on: pasteboard).flatMap { pasteboard.data(forType: $0) }.map { [$0] } ?? []
    }

    /// PNG if it's there, since it keeps the scale, else the first type that's an image.
    private static func imageType(on pasteboard: NSPasteboard) -> NSPasteboard.PasteboardType? {
        let types = pasteboard.types ?? []
        if types.contains(.png) {
            return .png
        }
        return types.first { UTType($0.rawValue)?.conforms(to: .image) == true }
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
