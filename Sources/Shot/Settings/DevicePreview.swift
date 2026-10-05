import AVFoundation
import Observation
import SwiftUI

/// Runs a camera or microphone from Settings so people can check it before recording.
@MainActor
@Observable
final class DevicePreview {
    static let camera = DevicePreview(mediaType: .video)
    static let microphone = DevicePreview(mediaType: .audio)

    let meter = AudioMeter()
    private(set) var session: AVCaptureSession?
    var isRunning: Bool { session != nil }

    @ObservationIgnored private let mediaType: AVMediaType
    @ObservationIgnored private let sink: AudioSink
    /// Bumped by every start and stop, so a start still waiting on the device can tell it was superseded.
    @ObservationIgnored private var generation = 0

    private init(mediaType: AVMediaType) {
        self.mediaType = mediaType
        sink = AudioSink(meter: meter)
    }

    static func stopAll() {
        camera.stop()
        microphone.stop()
    }

    /// `deviceID` empty means the system default.
    func start(deviceID: String) async {
        stop()
        let current = generation
        guard await AVCaptureDevice.requestAccess(for: mediaType) else {
            Toast.show(mediaType == .video ? "Camera access denied" : "Microphone access denied")
            return
        }
        guard current == generation else {
            return
        }
        guard let device = CaptureDevices.device(id: deviceID, for: mediaType) else {
            Toast.show(mediaType == .video ? "No camera found" : "No microphone found")
            return
        }
        let session = AVCaptureSession()
        do {
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else {
                throw CameraError.cannotUseCamera
            }
            session.addInput(input)
        } catch {
            Toast.show("\(device.localizedName) is unavailable")
            return
        }
        if mediaType == .audio {
            let output = AVCaptureAudioDataOutput()
            output.setSampleBufferDelegate(sink, queue: sink.queue)
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
        }
        self.session = session
        let box = SessionBox(session: session)
        await Task.detached { box.session.startRunning() }.value
        if current != generation {
            Task.detached { box.session.stopRunning() }
        }
    }

    func stop() {
        generation += 1
        if let session {
            let box = SessionBox(session: session)
            Task.detached { box.session.stopRunning() }
        }
        session = nil
        meter.reset()
    }
}

private final class AudioSink: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    let queue = DispatchQueue(label: "Shot.preview.audio")
    private let meter: AudioMeter

    init(meter: AudioMeter) {
        self.meter = meter
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        meter.measure(sampleBuffer)
    }
}

/// Live, mirrored camera video, as the camera bubble shows it.
struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        if let connection = layer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
