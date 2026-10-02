import AppKit
import AVFoundation
import Observation
import os
import ScreenCaptureKit
import ShotCore

private let log = Logger(subsystem: "dev.lorcan.Shot", category: "recording")

/// What the on-screen controls show; elapsed time excludes paused stretches.
@MainActor
@Observable
final class RecordingSessionModel {
    var isPaused = false
    var cameraOn = false
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

    private struct Session {
        let screen: NSScreen
        let region: CGRect
        let microphone: Bool
        let finalURL: URL
    }

    private var session: Session?
    private var segments: [URL] = []
    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var segmentFinished: CheckedContinuation<Void, Never>?
    private var border: RecordingBorderPanel?
    private var controls: RecordingControlPanel?
    private let frameSink = FrameSink()
    private var model = RecordingSessionModel()

    // MARK: Session

    /// `region` is an AppKit global rect inside `screen`.
    func start(screen: NSScreen, region: CGRect) async throws {
        let prefs = Preferences()
        var microphone = prefs.recordMicrophone
        if microphone, !(await AVCaptureDevice.requestAccess(for: .audio)) {
            microphone = false
            Toast.show("Microphone access denied; recording without it")
        }
        if prefs.recordCamera, !CameraBubble.shared.isVisible {
            await showCamera(in: region)
        } else if !prefs.recordCamera {
            CameraBubble.shared.hide()
        }
        let folder = prefs.saveFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let finalURL = FileNaming.uniqueURL(in: folder, date: Date(), pathExtension: "mp4", prefix: prefs.filePrefix)
        session = Session(screen: screen, region: region, microphone: microphone, finalURL: finalURL)
        segments = []
        model = RecordingSessionModel()
        model.cameraOn = CameraBubble.shared.isVisible
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
        let wasRecording = phase == .recording
        phase = .finishing
        hidePanels()
        if wasRecording {
            await finishSegment()
        }
        CameraBubble.shared.hide()
        await complete(discard: discard)
    }

    private func complete(discard: Bool) async {
        let parts = segments
        let finalURL = session?.finalURL
        segments = []
        session = nil
        phase = .idle
        if discard {
            for url in parts {
                try? FileManager.default.removeItem(at: url)
            }
            log.notice("Recording discarded")
            Toast.show("Recording discarded")
            return
        }
        guard let finalURL, !parts.isEmpty else {
            return
        }
        do {
            try await VideoConcatenator.concatenate(parts, to: finalURL)
            let size = (try? FileManager.default.attributesOfItem(atPath: finalURL.path)[.size] as? Int) ?? 0
            log.notice("Recording finished: \(finalURL.path, privacy: .public), \(parts.count) segments, \(size) bytes")
            onFinish?(finalURL)
        } catch {
            log.error("Joining segments failed; parts kept at \(parts.first?.deletingLastPathComponent().path ?? "", privacy: .public)")
            onError?(error)
        }
    }

    // MARK: Camera

    func toggleCamera() async {
        guard let session else {
            return
        }
        if CameraBubble.shared.isVisible {
            CameraBubble.shared.hide()
        } else {
            await showCamera(in: session.region)
        }
        model.cameraOn = CameraBubble.shared.isVisible
        await refreshFilter()
    }

    func cycleCameraSize() {
        CameraBubble.shared.cycleSize()
    }

    private func showCamera(in region: CGRect) async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            Toast.show("Camera access denied")
            return
        }
        let prefs = Preferences()
        do {
            try await CameraBubble.shared.show(in: region, preferred: prefs.cameraSize, deviceID: prefs.cameraDeviceID)
        } catch {
            Toast.show("Camera unavailable: \(error.localizedDescription)")
        }
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
        config.showsCursor = prefs.recordShowsCursor
        config.captureMicrophone = session.microphone
        config.capturesAudio = prefs.recordSystemAudio
        config.excludesCurrentProcessAudio = true

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Shot/segments")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("\(UUID().uuidString).mp4")
        let outputConfig = SCRecordingOutputConfiguration()
        outputConfig.outputURL = url
        outputConfig.outputFileType = .mp4
        outputConfig.videoCodecType = .h264

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        // Without a screen output SCK logs a dropped-frame error for every frame.
        try stream.addStreamOutput(frameSink, type: .screen, sampleHandlerQueue: frameSink.queue)
        let output = SCRecordingOutput(configuration: outputConfig, delegate: self)
        try stream.addRecordingOutput(output)
        try await stream.startCapture()
        self.stream = stream
        recordingOutput = output
        segments.append(url)
        log.notice("Segment \(self.segments.count) started: \(config.width)x\(config.height) at \(prefs.recordingFPS) fps, mic \(session.microphone), system audio \(prefs.recordSystemAudio), camera \(CameraBubble.shared.isVisible)")
    }

    /// Stops the current stream and waits until SCK has finished writing its file.
    private func finishSegment() async {
        guard let stream else {
            return
        }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            segmentFinished = continuation
            Task {
                do {
                    try await stream.stopCapture()
                } catch {
                    log.error("stopCapture failed: \(error.localizedDescription, privacy: .public)")
                    self.resolveSegment()
                }
                try? await Task.sleep(for: .seconds(5))
                if self.segmentFinished != nil {
                    log.error("No finish callback 5 s after stop; using the segment as is")
                    self.resolveSegment()
                }
            }
        }
        self.stream = nil
        recordingOutput = nil
    }

    private func resolveSegment() {
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
        let controls = RecordingControlPanel(region: region, screen: screen, model: model, actions: .init(
            togglePause: { [weak self] in Task { await self?.togglePause() } },
            toggleCamera: { [weak self] in Task { await self?.toggleCamera() } },
            cycleCameraSize: { [weak self] in self?.cycleCameraSize() },
            stop: { [weak self] discard in self?.onStopRequested?(discard) }
        ))
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

private final class FrameSink: NSObject, SCStreamOutput {
    let queue = DispatchQueue(label: "dev.lorcan.Shot.frames")

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {}
}
