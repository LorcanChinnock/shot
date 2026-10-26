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
    /// The region being recorded, as an AppKit global rect, and whether it is a window or the whole screen.
    private var recordingRegion = CGRect.zero
    /// The last area an area screenshot took, as a global AppKit rect, for Capture Previous Area. It's forgotten on quit.
    private var previousArea: CGRect?
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
        // Both phase changes and errors arrive after the recorder has left `.recording`, so `onPhaseChange` has already cleared `state`.
        recorder.onError = { [weak self] error in
            self?.report(error)
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
        // Picking a colour captures nothing, so it doesn't hold up captures while the loupe waits for a click.
        if action == .pickColor {
            Task { await pickColor() }
            return
        }
        if action == .copyPath {
            Task { await copyLatestPath() }
            return
        }
        if action == .focusQuickAccess {
            QuickAccessController.shared.focusNewest()
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
                case .capturePrevious:
                    try await capturePreviousArea()
                case .copyText:
                    try await copyTextFromArea()
                case .record:
                    try await startRecording(mode: .area)
                case .recordFullscreen:
                    try await startRecording(mode: .screen)
                case .recordWindow:
                    try await startRecording(mode: .window)
                case .pickColor, .copyPath, .focusQuickAccess:
                    break
                }
            } catch {
                report(error)
            }
        }
    }

    /// Counts down on screen, then takes a full-screen screenshot of the screen under the pointer, so menus and hover states
    /// set up in the meantime are in it. Esc or Cancel on the countdown takes nothing.
    func captureAfterCountdown(seconds: Int) {
        guard !busy else {
            return
        }
        busy = true
        Task {
            defer { busy = false }
            let screen = NSScreen.underPointer ?? NSScreen.screens[0]
            guard await ScreenshotCountdown(onTick: { [state] in state.countdown = $0 }).run(seconds: seconds, on: screen) else {
                return
            }
            do {
                try await captureFullscreen()
            } catch {
                report(error)
            }
        }
    }

    /// Copies the path of the newest capture, preferring an edited version over its original, so it pastes as the file
    /// itself.
    private func copyLatestPath() async {
        let folder = Preferences().captureFolder
        let latest = await Task.detached {
            Gallery.latest(in: Gallery.items(in: folder))?.url
        }.value
        guard let latest else {
            Toast.show("No captures in \(folder.lastPathComponent) yet")
            return
        }
        Clipboard.copy(string: latest.path)
        Toast.show("Copied the path of \(latest.lastPathComponent)")
    }

    /// Copies the hex of the colour clicked on screen. Esc copies nothing.
    private func pickColor() async {
        guard let color = await ColorSampler.sample() else {
            return
        }
        Clipboard.copy(string: color.hex)
        Toast.show("Copied \(color.hex)")
    }

    /// Opens a capture in the editor that suits it.
    func annotate(_ url: URL) {
        edit(EditorRoute(fileURL: url))
    }

    func edit(_ route: EditorRoute) {
        switch route {
        // A GIF the video editor exported reopens there, with its project.
        case let .image(url) where url.pathExtension.lowercased() == "gif" && VersionWriter.project(of: url, in: .app) != nil:
            log.notice("Video edit requested for a GIF with a project: \(url.path)")
            VideoEditorWindowController.open(url)
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
        let windows = WindowCapturer.onScreenWindows()
        let frozen = try await DisplayCapturer.captureAll()
        log.debug("Freeze capture of \(frozen.count) displays took \(ContinuousClock.now - start, privacy: .public)")
        let displays = frozen.map { OverlayDisplay(frame: $0.frame, scale: $0.scale, image: $0.image) }
        guard let selection = await SelectionOverlayController.select(displays: displays, windowMode: windowMode, windows: windows) else {
            return
        }
        let picked = try await picture(of: selection, frozen: frozen)
        if case .area = selection {
            previousArea = picked.frame
        }
        try await finish(image: picked.image, scale: picked.scale, from: picked.frame, windowShadow: picked.windowShadow)
    }

    /// What `selection` shows: cut from the frozen displays, or for a window, captured afresh, with the shadow if
    /// Settings ask for it. `frame` is in AppKit global points.
    private func picture(of selection: OverlaySelection, frozen: [FrozenDisplay]) async throws -> (image: CGImage, scale: CGFloat, frame: CGRect, windowShadow: Bool) {
        switch selection {
        case let .area(index, rect, _):
            let display = frozen[index]
            let pixels = Geometry.pixelRect(forViewRect: rect, viewHeight: display.frame.height, scale: display.scale)
            guard let cropped = display.image.cropping(to: pixels) else {
                throw CaptureError.encodingFailed
            }
            return (cropped, display.scale, rect.offsetBy(dx: display.frame.minX, dy: display.frame.minY), false)
        case let .window(info):
            let windowShadow = Preferences().windowShadow
            let result = try await WindowCapturer.capture(windowID: info.windowID, includeShadow: windowShadow)
            return (result.image, result.scale, Geometry.flip(info.frame, primaryHeight: NSScreen.screens.first?.frame.height ?? 0), windowShadow)
        case let .fullDisplay(index):
            return (frozen[index].image, frozen[index].scale, frozen[index].frame, false)
        }
    }

    /// Reads the text in the area, window or display picked on the overlay and copies it. Nothing is saved, and the
    /// area isn't remembered for Capture Previous Area.
    private func copyTextFromArea() async throws {
        let windows = WindowCapturer.onScreenWindows()
        let frozen = try await DisplayCapturer.captureAll()
        let displays = frozen.map { OverlayDisplay(frame: $0.frame, scale: $0.scale, image: $0.image) }
        guard let selection = await SelectionOverlayController.select(displays: displays, windowMode: false, windows: windows) else {
            return
        }
        let image: CGImage
        switch selection {
        case let .area(index, rect, _):
            let display = frozen[index]
            let pixels = Geometry.pixelRect(forViewRect: rect, viewHeight: display.frame.height, scale: display.scale)
            guard let cropped = display.image.cropping(to: pixels) else {
                throw CaptureError.encodingFailed
            }
            image = cropped
        case let .window(info):
            image = try await WindowCapturer.capture(windowID: info.windowID, includeShadow: false).image
        case let .fullDisplay(index):
            image = frozen[index].image
        }
        await Clipboard.copyText(in: image)
    }

    /// Takes the area the last area screenshot took, without the overlay.
    private func capturePreviousArea() async throws {
        guard let area = previousArea else {
            Toast.show("No previous area yet. Capture an area first.")
            return
        }
        // The display layout may have changed since, so the area must still sit on one display.
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(area) }) else {
            Toast.show("The previous area isn't on a display now")
            return
        }
        guard let frozen = try await DisplayCapturer.captureAll(screens: [screen]).first else {
            throw CaptureError.displayNotFound
        }
        let local = area.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        let pixels = Geometry.pixelRect(forViewRect: local, viewHeight: frozen.frame.height, scale: frozen.scale)
        guard let image = frozen.image.cropping(to: pixels) else {
            throw CaptureError.encodingFailed
        }
        try await finish(image: image, scale: frozen.scale, from: area)
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
        let controller = RecordingSetupController(mode: mode, screen: pick.screen, region: pick.region, windowID: pick.windowID, ratio: pick.ratio, start: start) { [state] in
            state.countdown = $0
        }
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
        let prefs = Preferences()
        let plan = AfterCapture.plan(prefs: prefs, isVideo: true)
        if plan.copies {
            Clipboard.copy(fileURL: url)
        }
        switch plan.next {
        case .quickAccess:
            Task {
                let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 480, height: 480)
                let thumbnail = try? await generator.image(at: .zero).image
                QuickAccessController.shared.add(videoURL: url, thumbnail: thumbnail)
            }
        case let .toast(message):
            Toast.show(message)
        case .editor, .nothing:
            break
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
                if result.truncated {
                    Toast.show("Saved \(gifURL.lastPathComponent) (first \(Int(GIFExporter.maxDuration)) s only).\(TemporaryCaptures.toastNote(for: gifURL))", duration: .seconds(3))
                } else {
                    Toast.show("Saved \(gifURL.lastPathComponent).\(TemporaryCaptures.toastNote(for: gifURL))", duration: .seconds(3))
                }
            } catch where Task.isCancelled {
                try? FileManager.default.removeItem(at: gifURL)
                Toast.show("Export cancelled")
            } catch {
                try? FileManager.default.removeItem(at: gifURL)
                Toast.error("Couldn't export the GIF: \(error.localizedDescription)")
            }
        }
    }

    /// Runs the enabled after-capture actions: copy, save, then Quick Access or the editor. `frame` is where the capture was
    /// on screen, as an AppKit global rect. `windowShadow` marks a window captured with the macOS shadow, which the file
    /// records so the editor doesn't offer a second one. The copy comes first, so a save that fails still leaves the
    /// capture on the clipboard, and the clipboard doesn't wait for the file.
    func finish(image original: CGImage, scale originalScale: CGFloat, from frame: CGRect, windowShadow: Bool = false) async throws {
        let prefs = Preferences()
        if prefs.playSound {
            Sound.capture()
        }
        let plan = AfterCapture.plan(prefs: prefs, isVideo: false)
        let copies = plan.copies
        let encoded = try await encode(original, scale: originalScale, windowShadow: windowShadow, clipboard: copies, prefs: prefs)
        let image = encoded.image
        let scale = encoded.scale
        let format = prefs.imageFormat
        if copies, let png = encoded.png {
            Clipboard.copy(png: png)
            endCaptureInterval("copied")
        }
        var savedURL: URL?
        var thumbnail: CGImage?
        if plan.writesFile {
            // Only a Quick Access card needs the thumbnail.
            let saved = try await write(encoded.file, prefs: prefs, thumbnail: plan.next == .quickAccess)
            savedURL = saved.url
            thumbnail = saved.thumbnail
            newCaptures = Array((newCaptures + [saved.url]).suffix(QuickAccessController.maxCards))
        }
        var card: URL?
        switch plan.next {
        case .editor:
            if let savedURL {
                EditorWindowController.open(savedURL, newCaptureStyle: newCaptureStyle(opening: savedURL))
            }
        case .quickAccess:
            if let savedURL {
                let size = NSSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
                QuickAccessController.shared.add(fileURL: savedURL, thumbnail: thumbnail ?? image, size: size)
                card = savedURL
            }
        case let .toast(message):
            Toast.show(message)
        case .nothing:
            break
        }
        if let newCaptureStyle = prefs.newCaptureStyle, copies || card != nil {
            style(
                image, scale: scale, with: newCaptureStyle, background: EditorDocument.defaultBackground(for: format), windowShadow: windowShadow,
                copy: copies, card: card
            )
        }
        WelcomeWindow.captureFinished()
    }

    /// A capture encoded for its file, and as a PNG for the clipboard when it's copied.
    private struct EncodedCapture {
        let file: Data
        let png: Data?
        /// The image as encoded, downscaled if Settings ask for that, and its scale.
        let image: CGImage
        let scale: CGFloat
    }

    /// Encodes the capture off the main actor as Settings ask, and as a PNG for the clipboard when `clipboard` is.
    private func encode(
        _ original: CGImage, scale originalScale: CGFloat, windowShadow: Bool, clipboard copies: Bool, prefs: Preferences
    ) async throws -> EncodedCapture {
        let downscale = prefs.downscaleRetina && originalScale > 1
        let format = prefs.imageFormat
        let sendable = SendableImage(original)
        let encoded = await Task.detached { () -> (file: Data?, png: Data?, image: SendableImage) in
            let image = downscale ? ImageCodec.downscaled(sendable.image, scale: originalScale) : sendable.image
            let scale = downscale ? 1 : originalScale
            let file = ImageCodec.data(from: image, scale: scale, format: format, windowShadow: windowShadow)
            // The clipboard takes a PNG, which a PNG capture's file already is.
            let png = format == .png ? file : copies ? ImageCodec.data(from: image, scale: scale) : nil
            return (file, png, SendableImage(image))
        }.value
        guard let file = encoded.file, !copies || encoded.png != nil else {
            throw CaptureError.encodingFailed
        }
        return EncodedCapture(file: file, png: encoded.png, image: encoded.image.image, scale: downscale ? 1 : originalScale)
    }

    /// Writes a capture's file as a new file in the capture folder, with a thumbnail for its Quick Access card if
    /// `thumbnail` is set.
    private func write(_ data: Data, prefs: Preferences, thumbnail showsCard: Bool) async throws -> (url: URL, thumbnail: CGImage?) {
        let folder = prefs.captureFolder
        let fileExtension = prefs.imageFormat.fileExtension, prefix = prefs.filePrefix
        let (url, thumbnail) = try await Task.detached { () throws -> (URL, SendableImage?) in
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = try FileNaming.writeNew(data, in: folder) {
                FileNaming.uniqueURL(in: folder, date: Date(), pathExtension: fileExtension, prefix: prefix)
            }
            return (url, showsCard ? ImageCodec.thumbnail(from: data, maxPixelSize: 480).map(SendableImage.init) : nil)
        }.value
        log.notice("Saved \(url.path)")
        return (url, thumbnail?.image)
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
    /// else was copied in the meantime, keeping `path` beside it if the plain copy had it, and gives the Quick Access card
    /// for `card` its look for its thumbnail, Copy and drag.
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
            WelcomeWindow.showIfNeeded()
        }
        Toast.error(error.localizedDescription)
    }
}
