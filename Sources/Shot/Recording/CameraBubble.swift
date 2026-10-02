import AppKit
import AVFoundation
import os
import ShotCore

private let log = Logger(subsystem: "dev.lorcan.Shot", category: "camera")

enum CameraError: LocalizedError {
    case noCamera

    var errorDescription: String? { "No camera found" }
}

/// Floating round webcam preview; the recorder includes its window in the video.
@MainActor
final class CameraBubble {
    static let shared = CameraBubble()
    static let inset: CGFloat = 24

    private var panel: CameraBubblePanel?
    private var session: AVCaptureSession?

    var windowID: CGWindowID? { panel.map { CGWindowID($0.windowNumber) } }

    static func cameras() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera], mediaType: .video, position: .unspecified).devices
    }

    /// `region` is the recorded area in AppKit global space.
    func show(in region: CGRect, preferred: CameraBubbleSize, deviceID: String) async throws {
        hide()
        guard let size = CameraBubbleSize.fitting(preferred, in: region, inset: Self.inset) else {
            log.notice("Region too small for the camera bubble")
            return
        }
        let device = (deviceID.isEmpty ? nil : AVCaptureDevice(uniqueID: deviceID)) ?? AVCaptureDevice.default(for: .video)
        guard let device else {
            throw CameraError.noCamera
        }
        let session = AVCaptureSession()
        session.sessionPreset = .high
        let input = try AVCaptureDeviceInput(device: device)
        if session.canAddInput(input) {
            session.addInput(input)
        }
        let panel = CameraBubblePanel(session: session, frame: CameraBubbleLayout.initialFrame(in: region, diameter: size.diameter, inset: Self.inset), size: size)
        // startRunning blocks until the camera is live, so the first recorded frames already show it.
        let box = SessionBox(session: session)
        await Task.detached { box.session.startRunning() }.value
        panel.orderFrontRegardless()
        self.session = session
        self.panel = panel
        log.notice("Camera bubble shown: \(device.localizedName, privacy: .public), \(size.rawValue, privacy: .public)")
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        if let session {
            let box = SessionBox(session: session)
            Task.detached { box.session.stopRunning() }
        }
        session = nil
    }
}

private struct SessionBox: @unchecked Sendable {
    let session: AVCaptureSession
}

private final class CameraBubblePanel: NSPanel {
    private static let border: CGFloat = 5
    private static let shadow: CGFloat = 7

    private let previewLayer: AVCaptureVideoPreviewLayer
    private let ringLayer = CALayer()
    private let shadowLayer = CAShapeLayer()
    private var size: CameraBubbleSize

    /// `frame` is the circle; the window adds room for the hard shadow.
    init(session: AVCaptureSession, frame: CGRect, size: CameraBubbleSize) {
        self.size = size
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(contentRect: Self.windowFrame(forCircle: frame), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        previewLayer.videoGravity = .resizeAspectFill
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        let view = BubbleView()
        view.onDoubleClick = { [weak self] in self?.cycleSize() }
        view.wantsLayer = true
        view.layer?.addSublayer(shadowLayer)
        view.layer?.addSublayer(ringLayer)
        ringLayer.addSublayer(previewLayer)
        ringLayer.masksToBounds = true
        ringLayer.borderColor = NSColor(srgbRed: 0.07, green: 0.07, blue: 0.10, alpha: 1).cgColor
        ringLayer.borderWidth = Self.border
        ringLayer.backgroundColor = NSColor.black.cgColor
        shadowLayer.fillColor = ringLayer.borderColor
        contentView = view
        layoutLayers()
    }

    private static func windowFrame(forCircle circle: CGRect) -> CGRect {
        CGRect(x: circle.minX, y: circle.minY - shadow, width: circle.width + shadow, height: circle.height + shadow)
    }

    private func layoutLayers() {
        let diameter = size.diameter
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let circle = CGRect(x: 0, y: Self.shadow, width: diameter, height: diameter)
        ringLayer.frame = circle
        ringLayer.cornerRadius = diameter / 2
        previewLayer.frame = ringLayer.bounds
        shadowLayer.path = CGPath(ellipseIn: circle.offsetBy(dx: Self.shadow, dy: -Self.shadow), transform: nil)
        CATransaction.commit()
    }

    private func cycleSize() {
        let circle = CGRect(x: frame.minX, y: frame.minY + Self.shadow, width: size.diameter, height: size.diameter)
        size = size.next
        UserDefaults.standard.set(size.rawValue, forKey: PreferenceKey.cameraSize)
        setFrame(Self.windowFrame(forCircle: CameraBubbleLayout.resized(circle, to: size.diameter)), display: true)
        layoutLayers()
    }
}

private final class BubbleView: NSView {
    var onDoubleClick: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
        } else {
            window?.performDrag(with: event)
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }
}
