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
    /// The files agents' recordings are saved as, by ID, so one that Undo saves after a discard is still theirs.
    private var agentRecordings: [URL: String] = [:]

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
                case .pickColor, .copyPath:
                    break
                }
            } catch {
                report(error)
            }
        }
    }

    /// Copies the path of the newest capture, preferring an edited version over its original as the agent tools do, so
    /// it pastes into an agent's prompt as the file itself.
    private func copyLatestPath() async {
        let folder = Preferences().captureFolder
        let latest = await Task.detached {
            AgentCaptures.latest(Gallery.items(in: folder).map { AgentCaptures.Entry(url: $0.url, isVideo: $0.kind == .video, date: $0.date) }, kind: .any)?.url
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
            if source != nil {
                let owner = NSRunningApplication(processIdentifier: info.ownerPID)
                source = CaptureRecord.Source(mode: "window", app: info.ownerName ?? owner?.localizedName, bundleID: owner?.bundleIdentifier, windowTitle: info.title)
            }
        case let .fullDisplay(index):
            image = frozen[index].image
            scale = frozen[index].scale
            frame = frozen[index].frame
            source?.mode = "fullscreen"
        }
        try await finish(image: image, scale: scale, from: frame, windowShadow: windowShadow, source: source)
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
        // An agent's recording is only saved: no copy, Quick Access card or confetti.
        if let id = agentRecordings[url] {
            Task { await agentRecordingSaved(url, id: id) }
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
    }

    /// Saves a capture to the capture folder and does nothing else: no sound, copy, Quick Access, editor or confetti. For
    /// a capture an agent asked for, whose record always says which window it came from. Gives back the file and its
    /// size in pixels.
    func saveCapture(image: CGImage, scale: CGFloat, from frame: CGRect, windowShadow: Bool, source: CaptureRecord.Source) async throws -> (url: URL, width: Int, height: Int) {
        let prefs = Preferences()
        let encoded = try await encode(image, scale: scale, from: frame, windowShadow: windowShadow, source: source, record: true, clipboard: false, prefs: prefs)
        let url = try await write(encoded.file, prefs: prefs, thumbnail: false).url
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

    /// Encodes the capture off the main actor as Settings ask, with its record inside the file when `record` is set, and
    /// a PNG for the clipboard when `clipboard` is.
    private func encode(
        _ original: CGImage, scale originalScale: CGFloat, from frame: CGRect, windowShadow: Bool, source: CaptureRecord.Source?, record: Bool, clipboard copies: Bool,
        prefs: Preferences
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
            let file = ImageCodec.data(from: image, scale: scale, format: format, windowShadow: windowShadow, record: record)
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
        let url = FileNaming.uniqueURL(in: folder, date: Date(), pathExtension: prefs.imageFormat.fileExtension, prefix: prefs.filePrefix)
        let thumbnail = try await Task.detached { () throws -> SendableImage? in
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url)
            return showsCard ? ImageCodec.thumbnail(from: data, maxPixelSize: 480).map(SendableImage.init) : nil
        }.value?.image
        log.notice("Saved \(url.path)")
        return (url, thumbnail)
    }

    // MARK: Agents

    /// A screenshot of the open window `query` names, for an agent. It's saved and nothing else, as `saveCapture` does,
    /// and a notice says so, since the user didn't ask for it themselves. Never shows the permission onboarding, which
    /// would take focus from whatever the agent is working on.
    func agentCapture(window query: String) async throws(ShotCommandError) -> [String: JSONValue] {
        guard Permissions.hasScreenCapture else {
            throw .noPermission("Shot doesn't have the Screen Recording permission. Grant it in System Settings › Privacy & Security › Screen & System Audio Recording.")
        }
        guard !busy, setup == nil else {
            throw .busy("Shot is in the middle of a capture or the recording setup; try again once it's done.")
        }
        let (info, match) = try matchWindow(query)
        busy = true
        defer { busy = false }
        let owner = NSRunningApplication(processIdentifier: info.ownerPID)
        let app = info.ownerName ?? owner?.localizedName ?? match.label
        let source = CaptureRecord.Source(mode: "window", app: app, bundleID: owner?.bundleIdentifier, windowTitle: info.title)
        let saved: (url: URL, width: Int, height: Int)
        do {
            let shadow = Preferences().windowShadow
            let captured = try await WindowCapturer.capture(windowID: info.windowID, includeShadow: shadow)
            let frame = Geometry.flip(info.frame, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
            saved = try await saveCapture(image: captured.image, scale: captured.scale, from: frame, windowShadow: shadow, source: source)
        } catch CaptureError.windowNotFound {
            throw .noInput("\(match.label) closed before Shot could capture it.")
        } catch {
            throw .io("Couldn't capture \(match.label): \(error.localizedDescription)")
        }
        log.notice("Agent captured window \(info.windowID) of \(app, privacy: .public)")
        Toast.show("An agent took a screenshot of \(app)", duration: .seconds(3))
        let bytes = (try? saved.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return [
            "path": .string(saved.url.path),
            "size": .object(["width": .number(Double(saved.width)), "height": .number(Double(saved.height))]),
            "bytes": .number(Double(bytes)),
            "window": .object(["app": .string(app), "title": .string(info.title ?? "")]),
        ]
    }

    /// The open window `query` names best, or a `.noInput` error listing the open ones.
    private func matchWindow(_ query: String) throws(ShotCommandError) -> (info: WindowInfo, match: WindowMatch.Candidate) {
        let windows = WindowCapturer.onScreenWindows()
        let candidates = windows.map { WindowMatch.Candidate(id: $0.windowID, app: $0.ownerName ?? "", title: $0.title ?? "") }
        guard let match = WindowMatch.best(query, in: candidates), let info = windows.first(where: { $0.windowID == match.id }) else {
            throw .noInput("No open window matches \"\(query)\". \(WindowMatch.listing(candidates))")
        }
        return (info, match)
    }

    /// Starts recording the open window `query` names, for an agent: never the microphone or camera, always with the
    /// red border and the stop controls, and for at most `AgentRequest.maximumDuration`. Answers with the recording's
    /// ID at once, or with `duration`, with the saved recording once it ends.
    func agentRecord(window query: String, duration: Double?) async throws(ShotCommandError) -> [String: JSONValue] {
        guard Permissions.hasScreenCapture else {
            throw .noPermission("Shot doesn't have the Screen Recording permission. Grant it in System Settings › Privacy & Security › Screen & System Audio Recording.")
        }
        guard !busy, setup == nil, !recorder.isRecording, agentSession == nil else {
            throw .busy("Shot is already recording, or in the middle of a capture or the recording setup; try again once it's done.")
        }
        let (info, match) = try matchWindow(query)
        let app = info.ownerName ?? match.label
        let (screen, region) = RecordingSetupController.region(of: info)
        let options = Recorder.Options(camera: false, microphone: false, showsCursor: Preferences().recordShowsCursor, windowID: info.windowID, alwaysShowsBorder: true)
        busy = true
        do {
            recordingRegion = region
            try await recorder.start(screen: screen, region: region, options: options)
        } catch {
            busy = false
            throw .io("Couldn't record \(match.label): \(error.localizedDescription)")
        }
        busy = false
        guard let url = recorder.outputURL else {
            throw .internal("the recording started without a file to save to")
        }
        let id = String(UUID().uuidString.prefix(8)).lowercased()
        let started = Date()
        var session = AgentSession(id: id, app: app, window: .object(["app": .string(app), "title": .string(info.title ?? "")]), started: started)
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
        agentRecordings[url] = id
        log.notice("Agent started recording window \(info.windowID) of \(app, privacy: .public) as \(id, privacy: .public)")
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
        throw .noInput("No agent recording is in progress.")
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

    /// Answers whoever waits for the agent's recording saved at `url`.
    private func agentRecordingSaved(_ url: URL, id: String) async {
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
        }
        endAgentRecording(id, with: .success(fields))
    }

    private func recordingEnded(_ url: URL?, _ ending: Recorder.Ending) {
        guard let url, let id = agentRecordings[url] else {
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
            agentRecordings = agentRecordings.filter { $0.value != id }
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
        return ["capturing": .bool(busy || setup != nil), "recording": recording]
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
            Permissions.showOnboarding()
        }
        Toast.error(error.localizedDescription)
    }
}
