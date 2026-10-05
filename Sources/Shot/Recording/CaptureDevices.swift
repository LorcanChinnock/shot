import AVFoundation

enum CaptureDevices {
    static func cameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera], mediaType: .video, position: .unspecified).devices
    }

    static func microphones() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
    }

    /// The device saved in Settings, or the system default when `id` is empty or no longer connected.
    static func device(id: String, for mediaType: AVMediaType) -> AVCaptureDevice? {
        (id.isEmpty ? nil : AVCaptureDevice(uniqueID: id)) ?? AVCaptureDevice.default(for: mediaType)
    }
}

/// Lets a session start and stop off the main actor; `AVCaptureSession` is thread-safe but not `Sendable`.
struct SessionBox: @unchecked Sendable {
    let session: AVCaptureSession
}
