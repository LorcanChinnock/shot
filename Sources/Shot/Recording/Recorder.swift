import AppKit
import AVFoundation
import os
import ScreenCaptureKit
import ShotCore

private let log = Logger(subsystem: "dev.lorcan.Shot", category: "recording")

@MainActor
final class Recorder: NSObject {
    var onFinish: ((URL) -> Void)?
    var onError: ((Error) -> Void)?

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    private var outputURL: URL?
    private var border: RecordingBorderPanel?
    private var isStopping = false
    private let frameSink = FrameSink()

    var isRecording: Bool { stream != nil && !isStopping }

    /// `region` is an AppKit global rect inside `screen`.
    func start(screen: NSScreen, region: CGRect) async throws {
        let prefs = Preferences()
        var microphone = prefs.recordMicrophone
        if microphone, !(await AVCaptureDevice.requestAccess(for: .audio)) {
            microphone = false
            Toast.show("Microphone access denied; recording without it")
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else {
            throw CaptureError.displayNotFound
        }
        let ownApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])

        let scale = screen.backingScaleFactor
        let local = Geometry.displayLocalTopLeft(region, screenFrame: screen.frame)
        let config = SCStreamConfiguration()
        config.sourceRect = local
        config.width = Geometry.evenFloor(local.width * scale)
        config.height = Geometry.evenFloor(local.height * scale)
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(prefs.recordingFPS))
        config.showsCursor = prefs.recordShowsCursor
        config.captureMicrophone = microphone

        let folder = prefs.saveFolder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = FileNaming.uniqueURL(in: folder, date: Date(), pathExtension: "mp4")
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
        outputURL = url
        let border = RecordingBorderPanel(region: region)
        border.orderFrontRegardless()
        self.border = border
        log.notice("Recording started: \(config.width)x\(config.height) at \(prefs.recordingFPS) fps, mic \(microphone), to \(url.path, privacy: .public)")
    }

    /// Keeps the stream and recording output alive until SCK reports the file finished.
    func stop() async {
        guard let stream, !isStopping else {
            return
        }
        isStopping = true
        border?.orderOut(nil)
        border = nil
        do {
            try await stream.stopCapture()
        } catch {
            log.error("stopCapture failed: \(error.localizedDescription, privacy: .public)")
        }
        try? await Task.sleep(for: .seconds(5))
        if outputURL != nil {
            log.error("No finish callback 5 s after stop; using the file as is")
            finished()
        }
    }

    private func tearDown() {
        border?.orderOut(nil)
        border = nil
        stream = nil
        recordingOutput = nil
        isStopping = false
    }

    private func finished() {
        guard let url = outputURL else {
            return
        }
        outputURL = nil
        tearDown()
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        log.notice("Recording finished: \(url.path, privacy: .public), \(size) bytes")
        onFinish?(url)
    }

    private func failed(_ error: Error) {
        log.error("Recording failed: \(error.localizedDescription, privacy: .public)")
        tearDown()
        outputURL = nil
        onError?(error)
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
        Task { @MainActor in self.finished() }
    }
}

private final class FrameSink: NSObject, SCStreamOutput {
    let queue = DispatchQueue(label: "dev.lorcan.Shot.frames")

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {}
}
