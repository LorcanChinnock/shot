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
    /// The recording an agent started, until it ends.
    private var agentSession: AgentSession?
    /// How agents' recordings ended, by ID, so a stop that comes after the user stopped one still gets its answer.
    private var agentEndings: [String: (result: Result<[String: JSONValue], ShotCommandError>, at: Date)] = [:]
    /// The files agents' recordings are saved as, with their IDs and who asked for them, so one that Undo saves after a
    /// discard is still theirs.
    private var agentRecordings: [URL: (id: String, origin: ProjectOrigin?)] = [:]

    private struct AgentSession {
        let id: String
        let app: String
        /// `app` and `title`, as the answers give it.
        let window: JSONValue
        let started: Date
        /// The requests waiting for it to end: a timed `record`, and any `stop`.
        var waiters: [CheckedContinuation<Result<[String: JSONValue], ShotCommandError>, Never>] = []
        /// Stops it after its duration, or after `AgentRequest.maximumDuration` at most.
        var limit: Task<Void, Never>?
        /// The moments the agent marked, at the recording's elapsed time, pauses left out.
        var marks: [RecordingMark] = []
    }

    init(state: AppState) {
        self.state = state
        recorder.onFinish = { [weak self] url in
            self?.recordingFinished(url)
        }
        recorder.onEnd = { [weak self] url, ending in
            self?.recordingEnded(url, ending)
        }
        recorder.onPhaseChange = { [weak self] phase in
            self?.state.isRecording = phase == .recording || phase == .paused
            TextIndexer.shared.isRecording = phase == .recording || phase == .paused
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
        let source = frontmostSource(mode: "fullscreen")
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
        try await finish(image: image, scale: frozen.scale, from: screen.fullCaptureFrame, source: source)
    }

    private func captureWithOverlay(windowMode: Bool) async throws {
        // Read before the overlay shows, which makes Shot the frontmost app.
        var source = frontmostSource(mode: "area")
        let start = ContinuousClock.now
        let windows = WindowCapturer.onScreenWindows()
        let frozen = try await DisplayCapturer.captureAll()
        log.debug("Freeze capture of \(frozen.count) displays took \(ContinuousClock.now - start, privacy: .public)")
        let displays = frozen.map { OverlayDisplay(frame: $0.frame, scale: $0.scale, image: $0.image) }
        guard let selection = await SelectionOverlayController.select(displays: displays, windowMode: windowMode, windows: windows) else {
            return
        }
        let picked = try await picture(of: selection, frozen: frozen)
        switch selection {
        case .area:
            previousArea = picked.frame
        case let .window(info):
            if source != nil {
                source = Self.windowSource(info)
            }
        case .fullDisplay:
            source?.mode = "fullscreen"
        }
        try await finish(image: picked.image, scale: picked.scale, from: picked.frame, windowShadow: picked.windowShadow, source: source)
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

    /// Where a picked window came from, for the capture's record.
    private static func windowSource(_ info: WindowInfo) -> CaptureRecord.Source {
        let owner = NSRunningApplication(processIdentifier: info.ownerPID)
        return CaptureRecord.Source(mode: "window", app: info.ownerName ?? owner?.localizedName, bundleID: owner?.bundleIdentifier, windowTitle: info.title)
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
        let source = frontmostSource(mode: "area")
        guard let frozen = try await DisplayCapturer.captureAll(screens: [screen]).first else {
            throw CaptureError.displayNotFound
        }
        let local = area.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        let pixels = Geometry.pixelRect(forViewRect: local, viewHeight: frozen.frame.height, scale: frozen.scale)
        guard let image = frozen.image.cropping(to: pixels) else {
            throw CaptureError.encodingFailed
        }
        try await finish(image: image, scale: frozen.scale, from: area, source: source)
    }

    /// What the capture's record says about where it came from, when the Agents setting is on: the frontmost app, which
    /// is the one on screen. `nil` when it's off, so the default capture path does none of this.
    private func frontmostSource(mode: String) -> CaptureRecord.Source? {
        guard Preferences().agentHandoff else {
            return nil
        }
        let app = NSWorkspace.shared.frontmostApplication
        return CaptureRecord.Source(mode: mode, app: app?.localizedName, bundleID: app?.bundleIdentifier)
    }

    /// `frame`, an AppKit global rect, as the record gives it: CoreGraphics global points, top-left origin.
    private static func recordFrame(_ frame: CGRect) -> CaptureRecord.Frame {
        let flipped = Geometry.flip(frame, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
        return CaptureRecord.Frame(x: flipped.minX, y: flipped.minY, width: flipped.width, height: flipped.height)
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
        // An agent's recording is only saved: no copy, Quick Access card or confetti.
        if let (id, origin) = agentRecordings[url] {
            Task { await agentRecordingSaved(url, id: id, origin: origin) }
            return
        }
        let prefs = Preferences()
        let plan = AfterCapture.plan(prefs: prefs, isVideo: true)
        if plan.copies {
            Clipboard.copy(fileURL: url)
        }
        Confetti.burst(from: recordingRegion)
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
    /// capture on the clipboard, and the clipboard doesn't wait for the file. `source` is what the capture's record says
    /// about where it came from, given only while the Agents setting is on.
    func finish(image original: CGImage, scale originalScale: CGFloat, from frame: CGRect, windowShadow: Bool = false, source: CaptureRecord.Source? = nil) async throws {
        let prefs = Preferences()
        if prefs.playSound {
            Sound.capture()
        }
        let plan = AfterCapture.plan(prefs: prefs, isVideo: false)
        let copies = plan.copies
        let encoded = try await encode(original, scale: originalScale, from: frame, windowShadow: windowShadow, source: source, record: prefs.agentHandoff, clipboard: copies, prefs: prefs)
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
        Confetti.burst(from: frame)
        WelcomeWindow.captureFinished()
    }

    /// Saves a capture to the capture folder and does nothing else: no sound, copy, Quick Access, editor or confetti. For
    /// a capture an agent asked for, whose record always says which window it came from, and whose project keeps
    /// `origin`, who asked. Gives back the file and its size in pixels.
    func saveCapture(
        image: CGImage, scale: CGFloat, from frame: CGRect, windowShadow: Bool, source: CaptureRecord.Source, origin: ProjectOrigin?
    ) async throws -> (url: URL, width: Int, height: Int) {
        let prefs = Preferences()
        let projectID = origin == nil ? nil : ProjectKey.newID()
        let encoded = try await encode(image, scale: scale, from: frame, windowShadow: windowShadow, source: source, record: true, clipboard: false, prefs: prefs, projectID: projectID)
        let url = try await write(encoded.file, prefs: prefs, thumbnail: false).url
        if let origin {
            // Dated now, when it's saved, rather than when it was asked for.
            let saved = ProjectOrigin(via: origin.via, client: origin.client, action: origin.action)
            await Task.detached { VersionWriter.keep(origin: saved, of: url, id: projectID, in: .app) }.value
        }
        return (url, encoded.image.width, encoded.image.height)
    }

    /// A capture encoded for its file, and as a PNG for the clipboard when it's copied.
    private struct EncodedCapture {
        let file: Data
        let png: Data?
        /// The image as encoded, downscaled if Settings ask for that, and its scale.
        let image: CGImage
        let scale: CGFloat
    }

    /// Encodes the capture off the main actor as Settings ask, with its record inside the file when `record` is set,
    /// `projectID` stamped in it when it has a project, and a PNG for the clipboard when `clipboard` is.
    private func encode(
        _ original: CGImage, scale originalScale: CGFloat, from frame: CGRect, windowShadow: Bool, source: CaptureRecord.Source?, record: Bool, clipboard copies: Bool,
        prefs: Preferences, projectID: String? = nil
    ) async throws -> EncodedCapture {
        let downscale = prefs.downscaleRetina && originalScale > 1
        let format = prefs.imageFormat
        let sendable = SendableImage(original)
        var source = source
        source?.screenFrame = Self.recordFrame(frame)
        let recordSource = source
        let encoded = await Task.detached { () -> (file: Data?, png: Data?, image: SendableImage) in
            let image = downscale ? ImageCodec.downscaled(sendable.image, scale: originalScale) : sendable.image
            let scale = downscale ? 1 : originalScale
            // Written in the same encode, so the record costs no second pass. A PNG's goes on the clipboard with it.
            let record = record ? CaptureRecord(kind: "image", created: Date(), size: CaptureRecord.Size(width: image.width, height: image.height), scale: scale, source: recordSource) : nil
            let file = ImageCodec.data(from: image, scale: scale, format: format, windowShadow: windowShadow, record: record, projectID: projectID)
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

    // MARK: Agents

    private static let noPermission = ShotCommandError.noPermission("Shot doesn't have the Screen Recording permission. Grant it in System Settings › Privacy & Security › Screen & System Audio Recording.")

    /// The open windows, front to back, and the displays, numbered as `display` targets them, for an agent to pick from.
    func agentWindows() throws(ShotCommandError) -> [String: JSONValue] {
        // Without the permission the window list has no titles, so an agent couldn't tell the windows apart.
        guard Permissions.hasScreenCapture else {
            throw Self.noPermission
        }
        let displays: [JSONValue] = NSScreen.screens.enumerated().map { index, screen in
            .object([
                "display": .number(Double(index + 1)),
                "name": .string(screen.localizedName),
                "size": .object(["width": .number(screen.frame.width), "height": .number(screen.frame.height)]),
                "scale": .number(screen.backingScaleFactor),
                "main": .bool(index == 0),
            ])
        }
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return ["windows": WindowMatch.json(Self.candidates(WindowCapturer.onScreenWindows()), frontmostBundleID: frontmost), "displays": .array(displays)]
    }

    /// A screenshot of the window or display `target` names, for an agent. It's saved and nothing else, as
    /// `saveCapture` does, and a notice says so, since the user didn't ask for it themselves. Never shows the permission
    /// onboarding, which would take focus from whatever the agent is working on.
    func agentCapture(_ target: AgentTarget, origin: ProjectOrigin?) async throws(ShotCommandError) -> [String: JSONValue] {
        guard Permissions.hasScreenCapture else {
            throw Self.noPermission
        }
        guard !busy, setup == nil else {
            throw .busy("Shot is in the middle of a capture or the recording setup; try again once it's done.")
        }
        if let display = target.display {
            return try await agentCapture(display: display, target, origin: origin)
        }
        let (info, match) = try matchWindow(target)
        busy = true
        defer { busy = false }
        let owner = NSRunningApplication(processIdentifier: info.ownerPID)
        let app = info.ownerName ?? owner?.localizedName ?? match.label
        let source = CaptureRecord.Source(mode: "window", app: app, bundleID: owner?.bundleIdentifier, windowTitle: info.title)
        let saved: (url: URL, width: Int, height: Int)
        do {
            // Part of a window is cut from the window itself, so the shadow, which would offset it, stays out.
            let shadow = !target.noShadow && target.rect == nil && Preferences().windowShadow
            let captured = try await Self.settled(within: target.waitStable) {
                try await WindowCapturer.capture(windowID: info.windowID, includeShadow: shadow)
            } image: { $0.image }
            guard let area = target.area(in: info.frame),
                  let pixels = target.pixels(width: captured.image.width, height: captured.image.height, scale: captured.scale),
                  let image = captured.image.cropping(to: pixels)
            else {
                throw ShotCommandError.data("The \(target.rectText) is off \(match.label), which is \(Int(info.frame.width))×\(Int(info.frame.height)) points.")
            }
            let frame = Geometry.flip(area, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
            saved = try await saveCapture(image: image, scale: captured.scale, from: frame, windowShadow: shadow, source: source, origin: origin)
        } catch let error as ShotCommandError {
            throw error
        } catch CaptureError.windowNotFound {
            throw .noInput("\(match.label) closed before Shot could capture it.")
        } catch {
            throw .io("Couldn't capture \(match.label): \(error.localizedDescription)")
        }
        log.notice("Agent captured window \(info.windowID) of \(app, privacy: .public)")
        Toast.show("An agent took a screenshot of \(app)", duration: .seconds(3))
        return Self.captured(saved, window: .object(["app": .string(app), "title": .string(info.title ?? "")]))
    }

    /// Asks the person to pick an area, window or display on the overlay, with `prompt` and who's asking shown above the
    /// hint, then saves the screenshot as `saveCapture` does. Esc, or no pick within `timeout` seconds, ends it with an
    /// error saying which. The person makes the selection, so this doesn't need Let agents capture and record.
    func agentPick(prompt: String?, timeout: Double, origin: ProjectOrigin?) async throws(ShotCommandError) -> [String: JSONValue] {
        guard Permissions.hasScreenCapture else {
            throw Self.noPermission
        }
        guard !busy, setup == nil else {
            throw .busy("Shot is in the middle of a capture or the recording setup; try again once it's done.")
        }
        busy = true
        defer { busy = false }
        let asker = origin?.clientName ?? (origin?.via == .cli ? String(localized: "The shot command") : String(localized: "An agent"))
        let message = prompt.map { String(localized: "\(asker) asks: \($0)") } ?? String(localized: "\(asker) asks you to pick something to capture")
        // Read before the overlay shows, which makes Shot the frontmost app.
        let app = NSWorkspace.shared.frontmostApplication
        let saved: (url: URL, width: Int, height: Int)
        let shows: JSONValue
        do {
            let windows = WindowCapturer.onScreenWindows()
            let frozen = try await DisplayCapturer.captureAll()
            let displays = frozen.map { OverlayDisplay(frame: $0.frame, scale: $0.scale, image: $0.image) }
            let deadline = ContinuousClock.now + .milliseconds(Int64(timeout * 1000))
            guard let selection = await SelectionOverlayController.select(displays: displays, windowMode: false, windows: windows, prompt: message, timeout: deadline - .now) else {
                if ContinuousClock.now >= deadline {
                    throw ShotCommandError.noInput("The user didn't pick anything within \(String(format: "%g", timeout)) seconds, so the selection closed.")
                }
                throw ShotCommandError.noInput("The user cancelled the selection.")
            }
            let picked = try await picture(of: selection, frozen: frozen)
            let source: CaptureRecord.Source
            switch selection {
            case .area:
                source = CaptureRecord.Source(mode: "area", app: app?.localizedName, bundleID: app?.bundleIdentifier)
                shows = .object(["area": .bool(true)])
            case let .window(info):
                source = Self.windowSource(info)
                shows = .object(["app": .string(source.app ?? ""), "title": .string(info.title ?? "")])
            case let .fullDisplay(index):
                source = CaptureRecord.Source(mode: "fullscreen", app: nil, bundleID: nil)
                shows = .object(["display": .number(Double(index + 1))])
            }
            saved = try await saveCapture(image: picked.image, scale: picked.scale, from: picked.frame, windowShadow: picked.windowShadow, source: source, origin: origin)
        } catch let error as ShotCommandError {
            throw error
        } catch CaptureError.windowNotFound {
            throw .noInput("The window closed before Shot could capture it.")
        } catch {
            throw .io("Couldn't capture what the user picked: \(error.localizedDescription)")
        }
        log.notice("Agent pick saved \(saved.url.lastPathComponent, privacy: .public)")
        Toast.show("Sent to \(asker)", duration: .seconds(3))
        return Self.captured(saved, window: shows)
    }

    /// A screenshot of display `number`, counted from 1, or the part of it `target.rect` covers.
    private func agentCapture(display number: Int, _ target: AgentTarget, origin: ProjectOrigin?) async throws(ShotCommandError) -> [String: JSONValue] {
        let screen = try Self.screen(number)
        busy = true
        defer { busy = false }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let source = CaptureRecord.Source(mode: "fullscreen", app: nil, bundleID: nil)
        let saved: (url: URL, width: Int, height: Int)
        do {
            let frozen = try await Self.settled(within: target.waitStable) {
                guard let frozen = try await DisplayCapturer.captureAll(screens: [screen]).first else {
                    throw CaptureError.displayNotFound
                }
                return frozen
            } image: { $0.image }
            guard let area = target.area(in: Geometry.flip(screen.frame, primaryHeight: primaryHeight)),
                  let pixels = target.pixels(width: frozen.image.width, height: frozen.image.height, scale: frozen.scale),
                  let image = frozen.image.cropping(to: pixels)
            else {
                throw ShotCommandError.data("The \(target.rectText) is off display \(number), which is \(Int(screen.frame.width))×\(Int(screen.frame.height)) points.")
            }
            saved = try await saveCapture(image: image, scale: frozen.scale, from: Geometry.flip(area, primaryHeight: primaryHeight), windowShadow: false, source: source, origin: origin)
        } catch let error as ShotCommandError {
            throw error
        } catch {
            throw .io("Couldn't capture display \(number): \(error.localizedDescription)")
        }
        log.notice("Agent captured display \(number)")
        Toast.show("An agent took a screenshot of \(screen.localizedName)", duration: .seconds(3))
        return Self.captured(saved, window: .object(["display": .number(Double(number)), "name": .string(screen.localizedName)]))
    }

    /// What an agent's screenshot answers with: where it was saved, its size and what it shows.
    private static func captured(_ saved: (url: URL, width: Int, height: Int), window: JSONValue) -> [String: JSONValue] {
        let bytes = (try? saved.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return [
            "path": .string(saved.url.path),
            "size": .object(["width": .number(Double(saved.width)), "height": .number(Double(saved.height))]),
            "bytes": .number(Double(bytes)),
            "window": window,
        ]
    }

    /// What `capture` gives back once the picture stops changing, taking it a few times a second for up to `timeout`
    /// seconds, or at once without one. A picture that never settles is taken anyway at the timeout.
    private static func settled<Picture>(within timeout: Double?, _ capture: () async throws -> Picture, image: (Picture) -> CGImage) async throws -> Picture {
        var shot = try await capture()
        guard let timeout else {
            return shot
        }
        var wait = StableWait(timeout: timeout)
        let start = ContinuousClock.now
        func elapsed() -> Double {
            let time = (ContinuousClock.now - start).components
            return Double(time.seconds) + Double(time.attoseconds) / 1e18
        }
        while wait.add(KeyFrameExtractor.gray(image(shot)), elapsed: elapsed()) == .wait {
            try await Task.sleep(for: .seconds(StableWait.interval))
            shot = try await capture()
        }
        return shot
    }

    /// The screen numbered `number` from 1, as `agentWindows` lists them.
    private static func screen(_ number: Int) throws(ShotCommandError) -> NSScreen {
        let screens = NSScreen.screens
        guard (1...screens.count).contains(number) else {
            throw .noInput("There's no display \(number); this Mac has \(screens.count). shot windows lists them.")
        }
        return screens[number - 1]
    }

    /// The windows as `WindowMatch` sees them, each with its app's bundle ID.
    private static func candidates(_ windows: [WindowInfo]) -> [WindowMatch.Candidate] {
        var bundleIDs: [pid_t: String] = [:]
        return windows.map { info in
            if bundleIDs[info.ownerPID] == nil {
                bundleIDs[info.ownerPID] = NSRunningApplication(processIdentifier: info.ownerPID)?.bundleIdentifier ?? ""
            }
            return WindowMatch.Candidate(id: info.windowID, app: info.ownerName ?? "", title: info.title ?? "", bundleID: bundleIDs[info.ownerPID] ?? "", width: info.frame.width, height: info.frame.height)
        }
    }

    /// The open window `target` names best, or a `.noInput` error listing the open ones.
    private func matchWindow(_ target: AgentTarget) throws(ShotCommandError) -> (info: WindowInfo, match: WindowMatch.Candidate) {
        let windows = WindowCapturer.onScreenWindows()
        let candidates = Self.candidates(windows)
        let query = target.window ?? ""
        guard let match = WindowMatch.best(query, bundleID: target.bundleID, in: candidates), let info = windows.first(where: { $0.windowID == match.id }) else {
            let named = [target.bundleID.map { "of \($0)" }, target.window.map { "matches \"\($0)\"" }].compactMap { $0 }.joined(separator: " ")
            throw .noInput("No open window \(named). \(WindowMatch.listing(candidates))")
        }
        return (info, match)
    }

    /// Starts recording the window or display `target` names, for an agent: never the microphone or camera, always
    /// with the red border and the stop controls, and for at most `AgentRequest.maximumDuration`. Answers with the
    /// recording's ID at once, or with `duration`, with the saved recording once it ends. Part of a window is recorded
    /// as that part of the screen, so whatever covers it shows too.
    func agentRecord(_ target: AgentTarget, duration: Double?, origin: ProjectOrigin?) async throws(ShotCommandError) -> [String: JSONValue] {
        guard Permissions.hasScreenCapture else {
            throw Self.noPermission
        }
        guard !busy, setup == nil, !recorder.isRecording, agentSession == nil else {
            throw .busy("Shot is already recording, or in the middle of a capture or the recording setup; try again once it's done.")
        }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let app: String
        let screen: NSScreen
        let region: CGRect
        let windowID: CGWindowID?
        let description: JSONValue
        if let number = target.display {
            screen = try Self.screen(number)
            guard let area = target.area(in: Geometry.flip(screen.frame, primaryHeight: primaryHeight)) else {
                throw .data("The \(target.rectText) is off display \(number), which is \(Int(screen.frame.width))×\(Int(screen.frame.height)) points.")
            }
            app = screen.localizedName
            region = Geometry.flip(area, primaryHeight: primaryHeight)
            windowID = nil
            description = .object(["display": .number(Double(number)), "name": .string(app)])
        } else {
            let (info, match) = try matchWindow(target)
            app = info.ownerName ?? match.label
            description = .object(["app": .string(app), "title": .string(info.title ?? "")])
            if target.rect == nil {
                (screen, region) = RecordingSetupController.region(of: info)
                windowID = info.windowID
            } else {
                guard let area = target.area(in: info.frame) else {
                    throw .data("The \(target.rectText) is off \(match.label), which is \(Int(info.frame.width))×\(Int(info.frame.height)) points.")
                }
                let part = Geometry.flip(area, primaryHeight: primaryHeight)
                screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: part.midX, y: part.midY)) } ?? NSScreen.screens[0]
                region = part.intersection(screen.frame)
                windowID = nil
            }
        }
        let options = Recorder.Options(camera: false, microphone: false, showsCursor: Preferences().recordShowsCursor, windowID: windowID, alwaysShowsBorder: true, ignoresShadow: target.noShadow)
        busy = true
        do {
            recordingRegion = region
            try await recorder.start(screen: screen, region: region, options: options)
        } catch {
            busy = false
            throw .io("Couldn't record \(app): \(error.localizedDescription)")
        }
        busy = false
        guard let url = recorder.outputURL else {
            throw .internal("the recording started without a file to save to")
        }
        let id = String(UUID().uuidString.prefix(8)).lowercased()
        let started = Date()
        var session = AgentSession(id: id, app: app, window: description, started: started)
        let seconds = min(duration ?? AgentRequest.maximumDuration, AgentRequest.maximumDuration)
        session.limit = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self, agentSession?.id == id, recorder.isRecording else {
                return
            }
            log.notice("Agent recording \(id, privacy: .public) reached its \(seconds, privacy: .public) s limit")
            stopRecording(discard: false)
        }
        agentSession = session
        agentRecordings[url] = (id, origin)
        log.notice("Agent started recording \(app, privacy: .public) as \(id, privacy: .public)")
        Toast.show("An agent is recording \(app)", duration: .seconds(3))
        guard duration != nil else {
            return ["id": .string(id), "window": session.window, "started": .string(ISO8601DateFormatter().string(from: started))]
        }
        return try await agentRecordingResult(id)
    }

    /// Stops the agent's recording `id`, or the agent's recording in progress, and answers once it's saved. One that has
    /// already ended answers with how it ended. A recording the user started is theirs alone to stop.
    func agentStop(id: String?) async throws(ShotCommandError) -> [String: JSONValue] {
        pruneAgentEndings()
        if let session = agentSession, id == nil || id == session.id {
            if recorder.isRecording {
                Toast.show("An agent stopped recording \(session.app)", duration: .seconds(3))
                stopRecording(discard: false)
            }
            return try await agentRecordingResult(session.id)
        }
        if let id, let ending = agentEndings[id] {
            return try ending.result.get()
        }
        if let id {
            throw .noInput("No agent recording has the id \(id). Finished ones are kept for \(Int(AgentRequest.maximumDuration / 60)) minutes.")
        }
        if recorder.isRecording {
            throw .busy("The recording in progress was started by the user, not an agent, so only they can stop it.")
        }
        throw .noInput("No agent recording is in progress. To get one that has already ended, stop it by the id it started with.")
    }

    /// Stamps `label` on the agent's recording `id`, or the agent's recording in progress, at its elapsed time, so its
    /// key frames show that moment. A recording the user started can't be marked.
    func agentMark(label: String, id: String?) throws(ShotCommandError) -> [String: JSONValue] {
        guard var session = agentSession, id == nil || id == session.id, recorder.isRecording else {
            if let id, agentEndings[id] != nil || agentSession?.id == id {
                throw .noInput("The agent recording \(id) has ended, so it can't be marked.")
            }
            if let id {
                throw .noInput("No agent recording has the id \(id).")
            }
            if recorder.isRecording, agentSession == nil {
                throw .busy("The recording in progress was started by the user, not an agent, so it can't be marked.")
            }
            throw .noInput("No agent recording is in progress to mark.")
        }
        guard session.marks.count < RecordingMark.maximumCount else {
            throw .usage(nil, "This recording already has \(RecordingMark.maximumCount) marks, the most it keeps.")
        }
        let mark = RecordingMark(time: (recorder.elapsed * 1000).rounded() / 1000, label: String(label.prefix(RecordingMark.maximumLabel)))
        session.marks.append(mark)
        agentSession = session
        log.notice("Agent marked recording \(session.id, privacy: .public) at \(mark.time, privacy: .public) s")
        return ["id": .string(session.id), "time": .number(mark.time), "label": .string(mark.label)]
    }

    /// Waits for the agent's recording `id` to end, and gives how it ended.
    private func agentRecordingResult(_ id: String) async throws(ShotCommandError) -> [String: JSONValue] {
        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<[String: JSONValue], ShotCommandError>, Never>) in
            if agentSession?.id == id {
                agentSession?.waiters.append(continuation)
            } else {
                continuation.resume(returning: agentEndings[id]?.result ?? .failure(.noInput("No agent recording has the id \(id).")))
            }
        }
        return try result.get()
    }

    /// Answers whoever waits for the agent's recording saved at `url`, once it's stamped with its project, which keeps
    /// `origin`, who asked for it.
    private func agentRecordingSaved(_ url: URL, id: String, origin: ProjectOrigin?) async {
        if let origin {
            // Dated now, when it's saved, rather than when it was asked for.
            let saved = ProjectOrigin(via: origin.via, client: origin.client, action: origin.action)
            await Task.detached { VersionWriter.keep(origin: saved, of: url, id: nil, in: .app) }.value
        }
        let media = try? await MediaProbe.probe(url)
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        var fields: [String: JSONValue] = [
            "id": .string(id),
            "path": .string(url.path),
            "bytes": .number(Double(bytes)),
            "duration": .number(((media?.duration ?? 0) * 10).rounded() / 10),
        ]
        if let size = media?.size {
            fields["size"] = .object(["width": .number(Double(Int(size.width))), "height": .number(Double(Int(size.height)))])
        }
        if let session = agentSession, session.id == id {
            Toast.show("Saved the agent's recording of \(session.app)", duration: .seconds(3))
            if !session.marks.isEmpty {
                let marks = session.marks
                fields["marks"] = .array(marks.map { .object(["time": .number($0.time), "label": .string($0.label)]) })
                // Saved before answering, so the key frames the answer leads to show the marks.
                let store = RecordingMarks.url(bundleID: Bundle.main.bundleIdentifier ?? "dev.lorcan.Shot.dev")
                do {
                    try await Task.detached { try RecordingMarks.save(marks, for: url, in: store) }.value
                } catch {
                    log.error("Couldn't keep the marks of \(url.path): \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        endAgentRecording(id, with: .success(fields))
    }

    private func recordingEnded(_ url: URL?, _ ending: Recorder.Ending) {
        guard let url, let id = agentRecordings[url]?.id else {
            return
        }
        switch ending {
        case .saved:
            // `agentRecordingSaved`, started from `onFinish`, answers once it has read the file.
            break
        case .discarded:
            endAgentRecording(id, with: .failure(.noInput("The user discarded this recording.")))
        case .failed:
            endAgentRecording(id, with: .failure(.io("The recording failed, and nothing was saved.")))
        }
    }

    /// Records how the agent's recording `id` ended, and answers everyone waiting for it.
    private func endAgentRecording(_ id: String, with result: Result<[String: JSONValue], ShotCommandError>) {
        agentEndings[id] = (result, Date())
        pruneAgentEndings()
        guard let session = agentSession, session.id == id else {
            return
        }
        agentSession = nil
        session.limit?.cancel()
        for waiter in session.waiters {
            waiter.resume(returning: result)
        }
    }

    /// Forgets endings older than `AgentRequest.maximumDuration`.
    private func pruneAgentEndings() {
        let cutoff = Date().addingTimeInterval(-AgentRequest.maximumDuration)
        for (id, ending) in agentEndings where ending.at < cutoff {
            agentEndings[id] = nil
            agentRecordings = agentRecordings.filter { $0.value.id != id }
        }
    }

    /// What an agent's status request answers: whether a capture or the recording setup is under way, and the
    /// recording in progress, if any, with its ID when an agent started it.
    func agentStatus() -> [String: JSONValue] {
        var recording: JSONValue = .null
        if recorder.isRecording {
            var fields: [String: JSONValue] = ["byAgent": .bool(agentSession != nil), "elapsed": .number((recorder.elapsed * 10).rounded() / 10)]
            if let agentSession {
                fields["id"] = .string(agentSession.id)
                fields["window"] = agentSession.window
            }
            recording = .object(fields)
        }
        return [
            "capturing": .bool(busy || setup != nil),
            "recording": recording,
            // For shot doctor, which can't check the app's permission or which copy is running from outside.
            "screenRecording": .bool(Permissions.hasScreenCapture),
            "version": .string(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"),
        ]
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
