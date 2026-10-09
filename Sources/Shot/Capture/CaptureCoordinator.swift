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
    private var gifExports: [URL: Task<Void, Never>] = [:]
    /// From a full-screen capture action to its clipboard write; ended with "copied", or "not copied" when nothing was copied.
    /// Area and window captures wait for the user's selection, so their time says nothing about Shot's speed.
    private var captureInterval: OSSignpostIntervalState?
    /// The latest captures not yet opened in the editor, as many as Quick Access shows: the ones Use this style for new
    /// captures still styles when they're opened. An older file opened from the Gallery stays as it is.
    private var newCaptures: [URL] = []

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
        if action == .captureFullscreen {
            captureInterval = Perf.signposter.beginInterval("Capture to clipboard", id: Perf.signposter.makeSignpostID())
        }
        Task {
            defer {
                busy = false
                endCaptureInterval("not copied")
            }
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
            EditorWindowController.open(url, newCaptureStyle: newCaptureStyle(opening: url))
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
        var windowShadow = false
        switch selection {
        case let .area(index, rect, _):
            let display = frozen[index]
            let pixels = Geometry.pixelRect(forViewRect: rect, viewHeight: display.frame.height, scale: display.scale)
            guard let cropped = display.image.cropping(to: pixels) else {
                throw CaptureError.encodingFailed
            }
            image = cropped
            scale = display.scale
            frame = rect.offsetBy(dx: display.frame.minX, dy: display.frame.minY)
        case let .window(info):
            windowShadow = Preferences().windowShadow
            let result = try await WindowCapturer.capture(windowID: info.windowID, includeShadow: windowShadow)
            image = result.image
            scale = result.scale
            frame = Geometry.flip(info.frame, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
        case let .fullDisplay(index):
            image = frozen[index].image
            scale = frozen[index].scale
            frame = frozen[index].frame
        }
        try await finish(image: image, scale: scale, from: frame, windowShadow: windowShadow)
    }

    func togglePause() {
        Task {
            await recorder.togglePause()
        }
    }

    var isRecording: Bool { recorder.isRecording }

    /// Stops and saves the recording in progress, as quitting does, waiting at most `timeout` for it to be written.
    func finishRecording(within timeout: Duration) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.recorder.stop(discard: false) }
            group.addTask { try? await Task.sleep(for: timeout) }
            await group.next()
            group.cancelAll()
        }
    }

    func stopRecording(discard: Bool) {
        Task {
            await recorder.stop(discard: discard)
        }
    }

    /// Picks the area, then starts recording, first showing the setup panel or a countdown if Settings asks for them.
    private func startRecording(mode: RecordingMode) async throws {
        guard let pick = await RecordingSetupController.pickRegion(mode: mode) else {
            return
        }
        let prefs = Preferences()
        // Record Fullscreen has no pick to end, so `pickRegion` never reports ⌥ for it; its hotkey may itself hold ⌥.
        let start = RecordingStart.after(adjustBeforeRecording: prefs.adjustBeforeRecording, countdown: prefs.recordingCountdown, optionHeld: pick.optionHeld)
        let controller = RecordingSetupController(mode: mode, screen: pick.screen, region: pick.region, windowID: pick.windowID, ratio: pick.ratio, start: start)
        setup = controller
        let result = await controller.run()
        setup = nil
        guard case let .start(screen, region, options) = result else {
            return
        }
        recordingRegion = region
        try await recorder.start(screen: screen, region: region, options: options)
    }

    private func recordingFinished(_ url: URL) {
        state.isRecording = false
        let prefs = Preferences()
        if prefs.copyAfterRecording {
            Clipboard.copy(fileURL: url)
        }
        Confetti.burst(from: recordingRegion)
        guard prefs.quickAccessAfterCapture else {
            if prefs.copyAfterRecording {
                Toast.show("Copied to clipboard")
            } else if prefs.saveAfterCapture {
                Toast.show("Saved")
            }
            return
        }
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
        guard gifExports[videoURL] == nil else {
            Toast.error("That video's GIF is already exporting")
            return
        }
        let prefs = Preferences()
        let options = prefs.videoExportOptions
        let gifURL = FileNaming.uniqueURL(in: videoURL.deletingLastPathComponent(), date: Date(), pathExtension: "gif", prefix: prefs.filePrefix)
        let cancel: @MainActor @Sendable () -> Void = { [weak self] in self?.gifExports[videoURL]?.cancel() }
        Toast.show("Exporting GIF…", duration: nil, cancel: cancel)
        let progress = PercentProgress { [weak self] percent in
            Task { @MainActor in
                guard let export = self?.gifExports[videoURL], !export.isCancelled else {
                    return
                }
                Toast.progress("Exporting GIF… \(percent)%")
            }
        }
        gifExports[videoURL] = Task {
            defer { gifExports[videoURL] = nil }
            do {
                let result = try await GIFExporter.export(videoURL: videoURL, to: gifURL, fps: Double(options.gifFrameRate), maxWidth: options.gifMaxWidth, progress: progress.report)
                let note = result.truncated ? " (first \(Int(GIFExporter.maxDuration)) s only)" : ""
                Toast.show("Saved \(gifURL.lastPathComponent)\(note)", duration: .seconds(3))
            } catch where Task.isCancelled {
                try? FileManager.default.removeItem(at: gifURL)
                Toast.show("Export cancelled")
            } catch {
                try? FileManager.default.removeItem(at: gifURL)
                Toast.error("GIF export failed: \(error.localizedDescription)")
            }
        }
    }

    /// Runs the enabled after-capture actions: save, copy, then Quick Access or the editor. `frame` is where the capture was
    /// on screen, as an AppKit global rect. `windowShadow` marks a window captured with the macOS shadow, which the file
    /// records so the editor doesn't offer a second one.
    func finish(image original: CGImage, scale originalScale: CGFloat, from frame: CGRect, windowShadow: Bool = false) async throws {
        let prefs = Preferences()
        if prefs.playSound {
            Sound.capture()
        }
        let downscale = prefs.downscaleRetina && originalScale > 1
        let format = prefs.imageFormat
        let source = SendableImage(original)
        let encoded = await Task.detached { () -> (file: Data?, png: Data?, image: SendableImage, thumbnail: SendableImage?) in
            let image = downscale ? ImageCodec.downscaled(source.image, scale: originalScale) : source.image
            let scale = downscale ? 1 : originalScale
            let file = ImageCodec.data(from: image, scale: scale, format: format, windowShadow: windowShadow)
            let png = format == .png ? file : ImageCodec.data(from: image, scale: scale)
            let thumbnail = file.flatMap { ImageCodec.thumbnail(from: $0, maxPixelSize: 480) }.map(SendableImage.init)
            return (file, png, SendableImage(image), thumbnail)
        }.value
        guard let fileData = encoded.file, let png = encoded.png else {
            throw CaptureError.encodingFailed
        }
        let image = encoded.image.image
        let scale = downscale ? 1 : originalScale
        var savedURL: URL?
        if prefs.saveAfterCapture || prefs.quickAccessAfterCapture || prefs.openEditorAfterCapture {
            let folder = prefs.captureFolder
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = FileNaming.uniqueURL(in: folder, date: Date(), pathExtension: format.fileExtension, prefix: prefs.filePrefix)
            try fileData.write(to: url)
            savedURL = url
            log.notice("Saved \(url.path)")
        }
        if prefs.copyAfterCapture {
            Clipboard.copy(png: png)
            endCaptureInterval("copied")
        }
        if let savedURL {
            newCaptures = Array((newCaptures + [savedURL]).suffix(QuickAccessController.maxCards))
        }
        var card: URL?
        if let savedURL, prefs.openEditorAfterCapture {
            EditorWindowController.open(savedURL, newCaptureStyle: newCaptureStyle(opening: savedURL))
        } else if let savedURL, prefs.quickAccessAfterCapture {
            let size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
            QuickAccessController.shared.add(fileURL: savedURL, thumbnail: encoded.thumbnail?.image ?? image, size: size)
            card = savedURL
        } else if prefs.copyAfterCapture {
            Toast.show("Copied to clipboard")
        } else if savedURL != nil {
            Toast.show("Saved")
        }
        if let newCaptureStyle = prefs.newCaptureStyle, prefs.copyAfterCapture || card != nil {
            style(
                image, scale: scale, with: newCaptureStyle, background: EditorDocument.defaultBackground(for: format), windowShadow: windowShadow,
                copy: prefs.copyAfterCapture, card: card
            )
        }
        Confetti.burst(from: frame)
    }

    /// The style a capture opens with: the one Use this style for new captures saved, if `url` is a new capture opened
    /// for the first time and the setting is still on.
    private func newCaptureStyle(opening url: URL) -> CopiedStyle? {
        guard let index = newCaptures.firstIndex(of: url) else {
            return nil
        }
        newCaptures.remove(at: index)
        return Preferences().newCaptureStyle
    }

    /// Draws `style` on the capture just taken, over `background` as the editor shows it, off the main actor, so the copy
    /// and Quick Access wait for nothing. Then, if `copy`, it replaces the plain capture on the clipboard, unless something
    /// else was copied in the meantime, and gives the Quick Access card for `card` its look for its thumbnail, Copy and drag.
    private func style(_ image: CGImage, scale: CGFloat, with style: CopiedStyle, background: RGBA?, windowShadow: Bool, copy: Bool, card: URL?) {
        let copied = NSPasteboard.general.changeCount
        let source = SendableImage(image)
        Task {
            let start = ContinuousClock.now
            let styled = await Task.detached { () -> (png: Data, thumbnail: SendableImage?, size: CGSize)? in
                guard let styled = style.styledCapture(source.image, scale: scale, background: background, windowShadow: windowShadow),
                      let png = ImageCodec.data(from: styled, scale: scale)
                else {
                    return nil
                }
                let size = CGSize(width: CGFloat(styled.width) / scale, height: CGFloat(styled.height) / scale)
                return (png, ImageCodec.thumbnail(from: png, maxPixelSize: 480).map(SendableImage.init), size)
            }.value
            guard let styled else {
                // A style the capture can't take, such as a shadow alone on a window with its own, leaves it plain.
                return
            }
            if copy, NSPasteboard.general.changeCount == copied {
                Clipboard.copy(png: styled.png)
            }
            if let card, let thumbnail = styled.thumbnail {
                await QuickAccessController.shared.setStyled(styled.png, thumbnail: thumbnail.image, size: styled.size, of: card)
            }
            log.debug("Styled capture took \(ContinuousClock.now - start, privacy: .public)")
        }
    }

    private func endCaptureInterval(_ outcome: StaticString) {
        if let captureInterval {
            Perf.signposter.endInterval("Capture to clipboard", captureInterval, "\(String(describing: outcome), privacy: .public)")
            self.captureInterval = nil
        }
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
    /// PNG only: apps read it, and a TIFF beside it cost about 15 ms and a screen-sized buffer per capture (#276).
    static func copy(png: Data) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
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
        copy(png: data)
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
