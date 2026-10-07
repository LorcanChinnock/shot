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
    /// Whether this recording captures the microphone at all; mute only silences it.
    var microphoneOn = false
    var microphoneMuted = false
    let meter = AudioMeter()
    private var accumulated: TimeInterval = 0
    private var runningSince: Date?

    func elapsed(at date: Date) -> TimeInterval {
        accumulated + (runningSince.map { date.timeIntervalSince($0) } ?? 0)
    }

    func run() {
        runningSince = Date()
    }

    func hold() {
        accumulated = elapsed(at: Date())
        runningSince = nil
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

    /// Choices made for one recording; Settings only holds the defaults they start from.
    struct Options {
        let camera: Bool
        let microphone: Bool
        let showsCursor: Bool
    }

    private struct Session {
        let screen: NSScreen
        let region: CGRect
        let microphone: Bool
        let showsCursor: Bool
        /// `nil` means the system default.
        let microphoneID: String?
        let finalURL: URL
    }

    private var session: Session?
    private var segments: [URL] = []
    private var segmentAudio: [VideoConcatenator.SegmentAudio] = []
    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var segmentFinished: CheckedContinuation<Void, Never>?
    private var segmentTimeout: Task<Void, Never>?
    private var finishing: Task<Void, Never>?
    private var border: RecordingBorderPanel?
    private var controls: NSPanel?
    private var sampleSink = SampleSink(meter: AudioMeter())
    private var model = RecordingSessionModel()
    /// Stretches of the recording, in recorded seconds, whose audio is silenced when the segments are joined.
    private var mutes = CutList()
    private var mutedSince: TimeInterval?

    // MARK: Session

    /// `region` is an AppKit global rect inside `screen`.
    func start(screen: NSScreen, region: CGRect, options: Options) async throws {
        let prefs = Preferences()
        var microphone = options.microphone
        if microphone, !(await AVCaptureDevice.requestAccess(for: .audio)) {
            microphone = false
            Toast.error("Microphone access denied; recording without it")
        }
        if options.camera, !CameraBubble.shared.isVisible {
            await CameraBubble.shared.showFromPreferences(in: region)
        } else if !options.camera {
            CameraBubble.shared.hide()
        }
        let folder = prefs.captureFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let finalURL = FileNaming.uniqueURL(in: folder, date: Date(), pathExtension: "mp4", prefix: prefs.filePrefix)
        let microphoneID = prefs.microphoneDeviceID.isEmpty ? nil : AVCaptureDevice(uniqueID: prefs.microphoneDeviceID)?.uniqueID
        session = Session(screen: screen, region: region, microphone: microphone, showsCursor: options.showsCursor, microphoneID: microphoneID, finalURL: finalURL)
        segments = []
        segmentAudio = []
        mutes = CutList()
        mutedSince = nil
        model = RecordingSessionModel()
        model.cameraOn = CameraBubble.shared.isVisible
        model.microphoneOn = microphone
        // Panels exist before the stream so the filter can exclude them by window ID.
        showPanels(screen: screen, region: region, prefs: prefs)
        do {
            try await startSegment()
        } catch {
            hidePanels()
            CameraBubble.shared.hide()
            session = nil
            throw error
        }
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
        log.notice("Recording paused after \(self.segments.count) segments")
    }

    func resume() async {
        guard phase == .paused else {
            return
        }
        do {
            try await startSegment()
            phase = .recording
            model.isPaused = false
            model.run()
            border?.setStyle(.recording)
            log.notice("Recording resumed")
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
        endMute()
        hidePanels()
        // Also waits for a segment that a pause is still finishing.
        await finishSegment()
        CameraBubble.shared.hide()
        await complete(discard: discard)
    }

    private func complete(discard: Bool) async {
        await sampleSink.finish()
        let parts = segments
        let audio = segmentAudio.count == parts.count ? segmentAudio : []
        let finalURL = session?.finalURL
        let muted = mutes
        segments = []
        segmentAudio = []
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

    private func join(_ parts: [URL], audio: [VideoConcatenator.SegmentAudio], to finalURL: URL?, muting muted: CutList) async {
        guard let finalURL, !parts.isEmpty else {
            return
        }
        do {
            try await VideoConcatenator.concatenate(parts, audio: audio, to: finalURL, muting: muted)
            let size = (try? FileManager.default.attributesOfItem(atPath: finalURL.path)[.size] as? Int) ?? 0
            log.notice("Recording finished: \(finalURL.path), \(parts.count) segments, \(size) bytes")
            onFinish?(finalURL)
        } catch {
            log.error("Joining segments failed; parts kept at \(parts.first?.deletingLastPathComponent().path ?? "")")
            onError?(error)
        }
    }

    // MARK: Microphone

    /// Mutes or unmutes without a gap in the video: the microphone keeps recording and the muted
    /// stretches are silenced when the segments are joined.
    func toggleMute() {
        guard isRecording, session?.microphone == true else {
            return
        }
        if mutedSince != nil {
            endMute()
        } else {
            mutedSince = model.elapsed(at: Date())
        }
        model.microphoneMuted = mutedSince != nil
        log.notice("Microphone \(self.model.microphoneMuted ? "muted" : "unmuted")")
    }

    private func endMute() {
        if let mutedSince {
            mutes = mutes.adding(mutedSince..<model.elapsed(at: Date()))
        }
        mutedSince = nil
    }

    // MARK: Camera

    func toggleCamera() async {
        guard let session else {
            return
        }
        if CameraBubble.shared.isVisible {
            CameraBubble.shared.hide()
        } else {
            await CameraBubble.shared.showFromPreferences(in: session.region)
        }
        model.cameraOn = CameraBubble.shared.isVisible
        await refreshFilter()
    }

    func cycleCameraSize() {
        CameraBubble.shared.cycleSize()
    }

    /// Re-applies the filter so a bubble shown or hidden mid-recording is included or dropped.
    private func refreshFilter() async {
        guard phase == .recording, let stream, let session else {
            return
        }
        do {
            try await stream.updateContentFilter(try await makeFilter(screen: session.screen))
        } catch {
            log.error("updateContentFilter failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Segments

    private func makeFilter(screen: NSScreen) async throws -> SCContentFilter {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
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
        let prefs = Preferences()
        let filter = try await makeFilter(screen: session.screen)
        let scale = session.screen.backingScaleFactor
        let local = Geometry.displayLocalTopLeft(session.region, screenFrame: session.screen.frame)
        let config = SCStreamConfiguration()
        config.sourceRect = local
        config.width = Geometry.evenFloor(local.width * scale)
        config.height = Geometry.evenFloor(local.height * scale)
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(prefs.recordingFPS))
        config.showsCursor = session.showsCursor
        config.captureMicrophone = session.microphone
        config.microphoneCaptureDeviceID = session.microphoneID
        config.capturesAudio = prefs.recordSystemAudio
        config.excludesCurrentProcessAudio = true

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Shot/segments")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let id = UUID().uuidString
        let url = folder.appendingPathComponent("\(id).mp4")
        // SCK mixes the microphone into system audio's track, so with both on each is also written apart, to mute only the microphone.
        let audio = session.microphone && prefs.recordSystemAudio
            ? VideoConcatenator.SegmentAudio(system: folder.appendingPathComponent("\(id)-system.mov"), microphone: folder.appendingPathComponent("\(id)-microphone.mov"))
            : nil
        sampleSink = SampleSink(meter: model.meter, audio: audio)
        let outputConfig = SCRecordingOutputConfiguration()
        outputConfig.outputURL = url
        outputConfig.outputFileType = .mp4
        outputConfig.videoCodecType = .h264

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        // Without a screen output SCK logs a dropped-frame error for every frame.
        try stream.addStreamOutput(sampleSink, type: .screen, sampleHandlerQueue: sampleSink.queue)
        if session.microphone {
            try stream.addStreamOutput(sampleSink, type: .microphone, sampleHandlerQueue: sampleSink.queue)
        }
        if audio != nil {
            try stream.addStreamOutput(sampleSink, type: .audio, sampleHandlerQueue: sampleSink.queue)
        }
        let output = SCRecordingOutput(configuration: outputConfig, delegate: self)
        try stream.addRecordingOutput(output)
        try await stream.startCapture()
        self.stream = stream
        recordingOutput = output
        segments.append(url)
        if let audio {
            segmentAudio.append(audio)
        }
        log.notice("Segment \(self.segments.count) started: \(config.width)x\(config.height) at \(prefs.recordingFPS) fps, mic \(session.microphone), system audio \(prefs.recordSystemAudio), camera \(CameraBubble.shared.isVisible)")
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
                await sink.finish()
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

    private func showPanels(screen: NSScreen, region: CGRect, prefs: Preferences) {
        if prefs.showRecordingBorder {
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
        // The notch is dead space, so it holds the controls when the floating panel would cover the recording.
        let controls: NSPanel = if let notch = screen.notch, RecordingControlPanel.covers(region, on: screen, microphone: model.microphoneOn) {
            NotchRecordingPanel(notch: notch, model: model, actions: actions)
        } else {
            RecordingControlPanel(region: region, screen: screen, model: model, actions: actions)
        }
        controls.orderFrontRegardless()
        self.controls = controls
    }

    private func hidePanels() {
        border?.orderOut(nil)
        border = nil
        controls?.orderOut(nil)
        controls = nil
    }

    private func failed(_ error: Error) {
        guard isRecording else {
            return
        }
        log.error("Recording failed: \(error.localizedDescription, privacy: .public)")
        phase = .finishing
        endMute()
        hidePanels()
        stream = nil
        recordingOutput = nil
        resolveSegment()
        CameraBubble.shared.hide()
        onError?(error)
        // Keep whatever was recorded before the failure.
        Task { await complete(discard: false) }
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
        Task { @MainActor in self.failed(error) }
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

    func finish() async {
        await system?.finish()
        await microphone?.finish()
    }

    private static func isComplete(_ frame: CMSampleBuffer) -> Bool {
        let attachments = CMSampleBufferGetSampleAttachmentsArray(frame, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]]
        return attachments?.first?[.status] as? Int == SCFrameStatus.complete.rawValue
    }
}
