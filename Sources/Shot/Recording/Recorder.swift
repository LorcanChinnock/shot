import AppKit
import AVFoundation
import Observation
import os
import ScreenCaptureKit
import ShotCore

private let log = Logger.shot("recording")

/// What the on-screen controls show; elapsed time excludes paused stretches.
@MainActor
@Observable
final class RecordingSessionModel {
    var isPaused = false
    var cameraOn = false
    var cameraAvailable = true
    /// Whether this recording captures the microphone at all; mute only silences it.
    var microphoneOn = false
    private(set) var microphoneMuted = false
    let meter = AudioMeter()
    private(set) var timeline = RecordingTimeline()

    func elapsed(at date: Date) -> TimeInterval {
        timeline.elapsed(at: date)
    }

    func run() {
        timeline.run(at: Date())
    }

    func hold() {
        timeline.hold(at: Date())
    }

    func toggleMute() {
        timeline.toggleMute(at: Date())
        microphoneMuted = timeline.isMuted
    }

    func endMute() {
        timeline.endMute(at: Date())
    }
}

/// Records one session as segments, so it can pause; segments are joined on stop.
@MainActor
final class Recorder: NSObject {
    enum Phase {
        case idle, recording, paused, finishing
    }

    var onFinish: ((URL) -> Void)?
    var onError: ((Error) -> Void)?
    /// Called by the on-screen controls; `true` means discard.
    var onStopRequested: ((Bool) -> Void)?
    var onPhaseChange: ((Phase) -> Void)?

    private(set) var phase: Phase = .idle {
        didSet { onPhaseChange?(phase) }
    }

    var isRecording: Bool { phase == .recording || phase == .paused }

    /// The file the recording in progress will be saved as.
    var outputURL: URL? { session?.finalURL }

    /// How long the recording in progress has run, leaving out pauses.
    var elapsed: TimeInterval { model.elapsed(at: Date()) }

    /// Choices made for one recording; Settings only holds the defaults they start from.
    struct Options {
        let camera: Bool
        let microphone: Bool
        let showsCursor: Bool
        /// Set when recording one window, which then follows the window and leaves out anything covering it.
        let windowID: CGWindowID?
        /// Set with `windowID` to record only a browser window's page.
        let pageInsets: PageInsets?
    }

    private struct Session {
        /// Tells a segment start that finished after its session ended apart from one that belongs to the current session.
        let id = UUID()
        let screen: NSScreen
        let region: CGRect
        let windowID: CGWindowID?
        let pageInsets: PageInsets?
        let microphone: Bool
        let showsCursor: Bool
        let showsClicks: Bool
        /// The microphone picked in Settings, or the default at start; `nil` only with no microphone at all.
        let microphoneID: String?
        /// Read once at start, so every segment of one recording has the same frame rate, audio tracks and microphone.
        let fps: Int
        let systemAudio: Bool
        let finalURL: URL
        /// A window recording keeps the size it started at, whatever the window does after, so every segment joins.
        var outputPixels: CGSize?
    }

    private var session: Session?
    private var segments = RecordingSegments()
    private var stream: SCStream?
    private var streamConfig: SCStreamConfiguration?
    /// Watches the recorded window, so the border and the video follow it when it moves or resizes.
    private var windowTracker: Task<Void, Never>?
    private var recordingOutput: SCRecordingOutput?
    private var segmentFinished: CheckedContinuation<Void, Never>?
    private var segmentTimeout: Task<Void, Never>?
    private var finishing: Task<Void, Never>?
    /// A resume's segment start; a stop waits for it so the new stream is stopped and kept rather than left running.
    private var starting: Task<Void, Error>?
    private var border: RecordingBorderPanel?
    private var controls: NSPanel?
    private var sampleSink = SampleSink(meter: AudioMeter())
    private var model = RecordingSessionModel()
    /// Set once this recording has said its microphone file failed.
    private var microphoneFailureShown = false

    /// Where each segment and its audio are written until the recording is joined.
    nonisolated static var segmentsFolder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("Shot/segments")
    }

    // MARK: Session

    /// `region` is an AppKit global rect inside `screen`.
    func start(screen: NSScreen, region: CGRect, options: Options) async throws {
        let prefs = Preferences()
        var microphone = options.microphone
        if microphone, !(await AVCaptureDevice.requestAccess(for: .audio)) {
            microphone = false
            Toast.error("Recording without the microphone. Turn it on in System Settings › Privacy & Security › Microphone.")
        }
        // A window recording captures only that window, so the bubble would never appear in it.
        let camera = options.camera && options.windowID == nil
        if camera, !CameraBubble.shared.isVisible {
            await CameraBubble.shared.showFromPreferences(in: region)
        } else if !camera {
            CameraBubble.shared.hide()
        }
        let folder = prefs.captureFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let finalURL = FileNaming.uniqueURL(in: folder, date: Date(), pathExtension: "mp4", prefix: prefs.filePrefix)
        let microphoneID = CaptureDevices.device(id: prefs.microphoneDeviceID, for: .audio)?.uniqueID
        session = Session(screen: screen, region: region, windowID: options.windowID, pageInsets: options.pageInsets, microphone: microphone, showsCursor: options.showsCursor, showsClicks: prefs.recordShowsClicks, microphoneID: microphoneID, fps: RecordingFrameRate.effective(setting: prefs.recordingFPS, displayRate: screen.maximumFramesPerSecond), systemAudio: prefs.recordSystemAudio, finalURL: finalURL)
        segments = RecordingSegments()
        microphoneFailureShown = false
        model = RecordingSessionModel()
        model.cameraOn = CameraBubble.shared.isVisible
        model.cameraAvailable = options.windowID == nil
        model.microphoneOn = microphone
        // Panels exist before the stream so the filter can exclude them by window ID.
        showPanels(screen: screen, region: region, border: prefs.showRecordingBorder)
        do {
            try await startSegment()
        } catch {
            hidePanels()
            CameraBubble.shared.hide()
            session = nil
            throw error
        }
        trackWindow()
        model.run()
        phase = .recording
    }

    func pause() async {
        guard phase == .recording else {
            return
        }
        phase = .paused
        model.isPaused = true
        model.hold()
        border?.setStyle(.paused)
        await finishSegment()
        model.meter.reset()
        log.notice("Recording paused after \(self.segments.videos.count) segments")
    }

    func resume() async {
        guard phase == .paused, starting == nil else {
            return
        }
        // A quick pause then resume would otherwise start a segment while the last one is still being written.
        await finishing?.value
        guard phase == .paused, starting == nil else {
            return
        }
        let task = Task { try await self.startSegment() }
        starting = task
        defer {
            if starting == task {
                starting = nil
            }
        }
        do {
            try await task.value
            // A stop while the segment started has already ended the recording.
            guard phase == .paused else {
                return
            }
            phase = .recording
            model.isPaused = false
            model.run()
            border?.setStyle(.recording)
            log.notice("Recording resumed")
        } catch is CancellationError {
            log.notice("Resume abandoned; the recording ended while its segment started")
        } catch {
            failed(error)
        }
    }

    func togglePause() async {
        if phase == .paused {
            await resume()
        } else {
            await pause()
        }
    }

    func stop(discard: Bool = false) async {
        guard isRecording else {
            return
        }
        phase = .finishing
        model.endMute()
        hidePanels()
        // A resume still starting its segment would otherwise leave a live stream after the session ends.
        _ = try? await starting?.value
        // Also waits for a segment that a pause is still finishing.
        await finishSegment()
        CameraBubble.shared.hide()
        await complete(discard: discard)
    }

    private func complete(discard: Bool) async {
        reportAudio(await sampleSink.finish())
        let parts = segments.videos
        let audio = segments.joinableAudio
        let finalURL = session?.finalURL
        let muted = model.timeline.mutes
        segments = RecordingSegments()
        session = nil
        phase = .idle
        if discard {
            let pending = PendingAction(
                commit: {
                    for url in parts + audio.flatMap(\.files) {
                        try? FileManager.default.removeItem(at: url)
                    }
                    log.notice("Recording discarded")
                },
                undo: { [weak self] in
                    log.notice("Discard undone")
                    Task { await self?.join(parts, audio: audio, to: finalURL, muting: muted) }
                }
            )
            Toast.show("Recording discarded", duration: .seconds(5), undoable: pending)
            return
        }
        await join(parts, audio: audio, to: finalURL, muting: muted)
    }

    /// Joins the segments into `finalURL`; false when there was nothing to join or joining failed.
    @discardableResult
    private func join(_ parts: [URL], audio: [VideoConcatenator.SegmentAudio], to finalURL: URL?, muting muted: CutList) async -> Bool {
        guard let finalURL, !parts.isEmpty else {
            return false
        }
        do {
            try await VideoConcatenator.concatenate(parts, audio: audio, to: finalURL, muting: muted)
            let size = (try? FileManager.default.attributesOfItem(atPath: finalURL.path)[.size] as? Int) ?? 0
            log.notice("Recording finished: \(finalURL.path), \(parts.count) segments, \(size) bytes")
            onFinish?(finalURL)
            return true
        } catch {
            log.error("Joining segments failed: \(error.localizedDescription, privacy: .public)")
            if let kept = await Self.keepAsIs(parts, date: Date()) {
                log.notice("Kept the segments as \(kept.count) files in \(kept[0].deletingLastPathComponent().path, privacy: .public)")
                Toast.show("Couldn't join the recording. Its parts are saved in your save folder.", duration: .seconds(8), reveal: kept[0])
            } else {
                log.error("Couldn't keep the segments; they stay in \(parts.first?.deletingLastPathComponent().path ?? "", privacy: .public)")
                onError?(error)
            }
            return false
        }
    }

    // MARK: Microphone

    /// Mutes or unmutes without a gap in the video: the microphone keeps recording and the muted
    /// stretches are silenced when the segments are joined.
    func toggleMute() {
        guard isRecording, session?.microphone == true else {
            return
        }
        model.toggleMute()
        log.notice("Microphone \(self.model.microphoneMuted ? "muted" : "unmuted")")
    }

    // MARK: Camera

    func toggleCamera() async {
        guard let session, session.windowID == nil else {
            return
        }
        let wasVisible = CameraBubble.shared.isVisible
        if wasVisible {
            CameraBubble.shared.hide()
        } else {
            await CameraBubble.shared.showFromPreferences(in: session.region)
        }
        model.cameraOn = CameraBubble.shared.isVisible
        guard await refreshFilter() else {
            // The video didn't follow, so the bubble goes back to how the recording has it.
            if wasVisible {
                await CameraBubble.shared.showFromPreferences(in: session.region)
            } else {
                CameraBubble.shared.hide()
            }
            model.cameraOn = CameraBubble.shared.isVisible
            Toast.error(wasVisible ? "Couldn't hide the camera bubble in the recording" : "Couldn't show the camera bubble in the recording")
            return
        }
    }

    func cycleCameraSize() {
        CameraBubble.shared.cycleSize()
    }

    /// Re-applies the filter so a bubble shown or hidden mid-recording is included or dropped. False when that failed;
    /// while paused there's no stream, and the next segment picks the bubble up.
    private func refreshFilter() async -> Bool {
        guard phase == .recording, let stream, let session else {
            return true
        }
        do {
            try await stream.updateContentFilter(try await makeFilter(session))
            return true
        } catch {
            log.error("updateContentFilter failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: Following the window

    /// Fits the window, or its page, inside an output that keeps one size, without stretching it.
    private func applyWindowGeometry(to config: SCStreamConfiguration, windowSize: CGSize, pageInsets: PageInsets?, output: CGSize) {
        let window = CGRect(origin: .zero, size: windowSize)
        let source = pageInsets?.page(in: window) ?? window
        config.sourceRect = source
        config.destinationRect = AspectFit.rect(for: source.size, in: output)
    }

    private func trackWindow() {
        guard let windowID = session?.windowID else {
            return
        }
        windowTracker = Task { [weak self] in
            var last: CGRect?
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let frame = Self.frame(ofWindow: windowID), frame != last else {
                    continue
                }
                last = frame
                self?.windowChanged(to: frame)
            }
        }
    }

    private func windowChanged(to frame: CGRect) {
        guard let session else {
            return
        }
        let page = session.pageInsets?.page(in: frame) ?? frame
        border?.setRegion(Geometry.flip(page, primaryHeight: NSScreen.screens.first?.frame.height ?? 0))
        guard let stream, let streamConfig, let output = session.outputPixels else {
            return
        }
        applyWindowGeometry(to: streamConfig, windowSize: frame.size, pageInsets: session.pageInsets, output: output)
        Task {
            do {
                try await stream.updateConfiguration(streamConfig)
            } catch {
                log.error("Following the window failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private nonisolated static func frame(ofWindow id: CGWindowID) -> CGRect? {
        let list = CGWindowListCopyWindowInfo(.optionIncludingWindow, id) as? [[String: Any]]
        guard let bounds = list?.first?[kCGWindowBounds as String] as? NSDictionary else {
            return nil
        }
        return CGRect(dictionaryRepresentation: bounds)
    }

    // MARK: Segments

    private func makeFilter(_ session: Session) async throws -> SCContentFilter {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        if let windowID = session.windowID {
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                throw CaptureError.windowNotFound
            }
            return SCContentFilter(desktopIndependentWindow: window)
        }
        guard let display = content.displays.first(where: { $0.displayID == session.screen.displayID }) else {
            throw CaptureError.displayNotFound
        }
        if !Preferences().hidesShotUI {
            // Show Shot's windows such as Quick Access cards, but never the recording chrome.
            let chrome = Set([border?.windowNumber, controls?.windowNumber].compactMap { $0 }.map { CGWindowID($0) })
            return SCContentFilter(display: display, excludingWindows: content.windows.filter { chrome.contains($0.windowID) })
        }
        let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        // Shot's windows stay out of the video, except the camera bubble.
        let cameraWindows = content.windows.filter { $0.windowID == CameraBubble.shared.windowID }
        if CameraBubble.shared.isVisible, cameraWindows.isEmpty {
            log.error("Camera bubble window not found in shareable content")
        }
        return SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: cameraWindows)
    }

    private func startSegment() async throws {
        guard let session else {
            return
        }
        let filter = try await makeFilter(session)
        guard self.session?.id == session.id else {
            throw CancellationError()
        }
        let config = SCStreamConfiguration()
        if session.windowID != nil {
            let scale = CGFloat(filter.pointPixelScale)
            let window = CGRect(origin: .zero, size: filter.contentRect.size)
            let output = self.session?.outputPixels ?? CGSize(
                width: Geometry.evenFloor((session.pageInsets?.page(in: window) ?? window).width * scale),
                height: Geometry.evenFloor((session.pageInsets?.page(in: window) ?? window).height * scale)
            )
            self.session?.outputPixels = output
            config.width = Int(output.width)
            config.height = Int(output.height)
            applyWindowGeometry(to: config, windowSize: window.size, pageInsets: session.pageInsets, output: output)
        } else {
            let scale = session.screen.backingScaleFactor
            let local = Geometry.displayLocalTopLeft(session.region, screenFrame: session.screen.frame)
            config.sourceRect = local
            config.width = Geometry.evenFloor(local.width * scale)
            config.height = Geometry.evenFloor(local.height * scale)
        }
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(session.fps))
        config.showsCursor = session.showsCursor
        config.showMouseClicks = session.showsClicks
        config.captureMicrophone = session.microphone
        config.microphoneCaptureDeviceID = session.microphoneID
        config.capturesAudio = session.systemAudio
        config.excludesCurrentProcessAudio = true

        let folder = Self.segmentsFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let id = UUID().uuidString
        // With both on, each is also written apart, to mute only the microphone.
        let (url, audio) = RecordingSegments.files(in: folder, id: id, microphone: session.microphone, systemAudio: session.systemAudio)
        let sink = SampleSink(meter: model.meter, audio: audio)
        let outputConfig = SCRecordingOutputConfiguration()
        outputConfig.outputURL = url
        outputConfig.outputFileType = .mp4
        outputConfig.videoCodecType = RecordingFrameRate.usesHEVC(fps: session.fps) ? .hevc : .h264

        streamConfig = config
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        // Without a screen output SCK logs a dropped-frame error for every frame.
        try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue)
        if session.microphone {
            try stream.addStreamOutput(sink, type: .microphone, sampleHandlerQueue: sink.queue)
        }
        if audio != nil {
            try stream.addStreamOutput(sink, type: .audio, sampleHandlerQueue: sink.queue)
        }
        let output = SCRecordingOutput(configuration: outputConfig, delegate: self)
        try stream.addRecordingOutput(output)
        try await stream.startCapture()
        guard self.session?.id == session.id else {
            // The recording ended while this segment started, so nothing would ever stop or join it.
            try? await stream.stopCapture()
            _ = await sink.finish()
            for file in [url] + (audio?.files ?? []) {
                try? FileManager.default.removeItem(at: file)
            }
            throw CancellationError()
        }
        sampleSink = sink
        self.stream = stream
        recordingOutput = output
        segments.append(url, audio: audio)
        log.notice("Segment \(self.segments.videos.count) started: \(config.width)x\(config.height) at \(session.fps) fps, mic \(session.microphone), system audio \(session.systemAudio), camera \(CameraBubble.shared.isVisible)")
    }

    /// Logs an audio file that couldn't be written, and says so once per recording when it's the microphone's: the
    /// recording then has no microphone in it.
    private func reportAudio(_ failures: SampleSink.Failures) {
        if let message = failures.system {
            log.error("System audio file failed: \(message, privacy: .public)")
        }
        if let message = failures.microphone {
            log.error("Microphone file failed: \(message, privacy: .public)")
            if !microphoneFailureShown {
                microphoneFailureShown = true
                Toast.error("The microphone couldn't be recorded: \(message)")
            }
        }
    }

    /// Stops the current stream and waits until SCK has finished writing its file.
    /// Concurrent callers (a stop during a pause) share the same wait.
    private func finishSegment() async {
        if let stream {
            self.stream = nil
            recordingOutput = nil
            let sink = sampleSink
            finishing = Task {
                await stopCapture(stream)
                reportAudio(await sink.finish())
            }
        }
        await finishing?.value
        finishing = nil
    }

    private func stopCapture(_ stream: SCStream) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            segmentFinished = continuation
            segmentTimeout = Task {
                guard (try? await Task.sleep(for: .seconds(5))) != nil, self.segmentFinished != nil else {
                    return
                }
                log.error("No finish callback 5 s after stop; using the segment as is")
                self.resolveSegment()
            }
            Task {
                do {
                    try await stream.stopCapture()
                } catch {
                    log.error("stopCapture failed: \(error.localizedDescription, privacy: .public)")
                    self.resolveSegment()
                }
            }
        }
    }

    private func resolveSegment() {
        segmentTimeout?.cancel()
        segmentTimeout = nil
        segmentFinished?.resume()
        segmentFinished = nil
    }

    // MARK: Panels

    private func showPanels(screen: NSScreen, region: CGRect, border showsBorder: Bool) {
        if showsBorder {
            let border = RecordingBorderPanel(region: region, style: .recording)
            border.orderFrontRegardless()
            self.border = border
        }
        let actions = RecordingControlPanel.Actions(
            togglePause: { [weak self] in Task { await self?.togglePause() } },
            toggleMute: { [weak self] in self?.toggleMute() },
            toggleCamera: { [weak self] in Task { await self?.toggleCamera() } },
            cycleCameraSize: { [weak self] in self?.cycleCameraSize() },
            stop: { [weak self] discard in self?.onStopRequested?(discard) }
        )
        let controls = RecordingControlPanel(region: region, screen: screen, model: model, actions: actions)
        controls.orderFrontRegardless()
        self.controls = controls
    }

    private func hidePanels() {
        windowTracker?.cancel()
        windowTracker = nil
        border?.orderOut(nil)
        border = nil
        controls?.orderOut(nil)
        controls = nil
    }

    /// Keeps the segment a failed recording output left, if it can still be played, as the end of the recording; otherwise deletes it.
    private func keepOrDrop(_ video: URL, audio: VideoConcatenator.SegmentAudio?) async {
        if await Self.isPlayable(video) {
            segments.append(video, audio: audio)
            log.notice("Kept the segment whose recording failed")
        } else {
            for url in [video] + (audio?.files ?? []) {
                try? FileManager.default.removeItem(at: url)
            }
            log.notice("Left out the segment whose recording failed")
        }
    }

    /// Ends the recording after `error`, keeping what was recorded before it. `output` is the recording output that
    /// failed, if one did: its segment's file is kept only if it can still be played.
    private func failed(_ error: Error, output: ObjectIdentifier? = nil) {
        guard isRecording else {
            return
        }
        log.error("Recording failed: \(error.localizedDescription, privacy: .public)")
        phase = .finishing
        model.endMute()
        hidePanels()
        // A recording output can fail, a full disk say, while its stream goes on capturing the display and microphone.
        let stopping = stream
        var truncated: (video: URL, audio: VideoConcatenator.SegmentAudio?)?
        if let output, output == recordingOutput.map(ObjectIdentifier.init), let failed = segments.removeLast() {
            truncated = failed
        }
        stream = nil
        recordingOutput = nil
        resolveSegment()
        CameraBubble.shared.hide()
        onError?(error)
        // Keep whatever was recorded before the failure, and the failed segment too if it can still be played.
        Task {
            // Wait for the stream to stop, so the failed segment isn't judged or joined while it's still being written.
            try? await stopping?.stopCapture()
            if let truncated {
                await keepOrDrop(truncated.video, audio: truncated.audio)
            }
            await complete(discard: false)
        }
    }
}

extension Recorder: SCStreamDelegate, SCRecordingOutputDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in self.failed(error) }
    }

    nonisolated func recordingOutputDidStartRecording(_ recordingOutput: SCRecordingOutput) {
        log.notice("Recording output started")
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        let output = ObjectIdentifier(recordingOutput)
        Task { @MainActor in self.failed(error, output: output) }
    }

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in self.resolveSegment() }
    }
}

/// Feeds the microphone level meter and, with `audio`, writes system audio and the microphone to their own files.
/// Screen frames time those files, and are otherwise only taken so SCK doesn't log them as dropped.
private final class SampleSink: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "Shot.samples")
    private let meter: AudioMeter
    private let system: AudioFileWriter?
    private let microphone: AudioFileWriter?
    /// Read and written on `queue`.
    private var reported = false

    init(meter: AudioMeter, audio: VideoConcatenator.SegmentAudio? = nil) {
        self.meter = meter
        system = audio.map { AudioFileWriter(url: $0.system) }
        microphone = audio.map { AudioFileWriter(url: $0.microphone) }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        switch type {
        case .screen:
            // Taken as the start of the recording file, so the audio files line up with it.
            guard system != nil, Self.isComplete(sampleBuffer) else {
                return
            }
            system?.start(at: sampleBuffer.presentationTimeStamp)
            microphone?.start(at: sampleBuffer.presentationTimeStamp)
        case .audio:
            system?.append(sampleBuffer)
        case .microphone:
            meter.measure(sampleBuffer)
            microphone?.append(sampleBuffer)
        @unknown default:
            break
        }
    }

    /// Why the system audio or microphone file couldn't be written, if either couldn't; messages, so they can reach
    /// the main actor.
    struct Failures: Sendable {
        var system: String?
        var microphone: String?
    }

    /// Finishes both files and says which failed. Only the first call reports a failure, so it's told once.
    func finish() async -> Failures {
        await system?.finish()
        await microphone?.finish()
        let first = queue.sync {
            defer { reported = true }
            return !reported
        }
        return first ? Failures(system: system?.failure?.localizedDescription, microphone: microphone?.failure?.localizedDescription) : Failures()
    }

    private static func isComplete(_ frame: CMSampleBuffer) -> Bool {
        let attachments = CMSampleBufferGetSampleAttachmentsArray(frame, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]]
        return attachments?.first?[.status] as? Int == SCFrameStatus.complete.rawValue
    }
}
