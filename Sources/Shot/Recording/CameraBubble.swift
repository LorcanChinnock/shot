import AppKit
import AVFoundation
import os
import ShotCore

private let log = Logger.shot("camera")

enum CameraError: LocalizedError {
    case noCamera
    case cannotUseCamera
    case regionTooSmall

    var errorDescription: String? {
        switch self {
        case .noCamera: String(localized: "No camera found")
        case .cannotUseCamera: String(localized: "The camera is in use or unavailable")
        case .regionTooSmall: String(localized: "The area is too small for the camera bubble")
        }
    }
}

/// Floating round webcam preview; the recorder includes its window in the video.
@MainActor
final class CameraBubble {
    static let shared = CameraBubble()

    private var panel: CameraBubblePanel?
    private var session: AVCaptureSession?
    /// Bumped by every show and hide, so a show still starting the camera can tell it was superseded.
    private var generation = 0

    var windowID: CGWindowID? { panel.map { CGWindowID($0.windowNumber) } }
    var isVisible: Bool { panel != nil }

    /// Shows the resize handle, which only checking before recording offers.
    var showsHandle = false {
        didSet { panel?.showsHandle = showsHandle }
    }

    /// One size larger (`by: 1`) or smaller (`by: -1`), as ⌘+ and ⌘− do on the check-before-recording bar.
    func step(by step: Int) {
        panel?.step(by: step)
    }

    func move(by delta: CGVector) {
        guard let panel else {
            return
        }
        panel.setFrameOrigin(CGPoint(x: panel.frame.minX + delta.dx, y: panel.frame.minY + delta.dy))
    }

    /// Keeps the bubble inside `region`, the recorded area in AppKit global space.
    func setRegion(_ region: CGRect) {
        panel?.region = region
    }

    /// Asks for camera access and shows the preferred camera, reporting problems with a toast.
    /// Returns whether the bubble is showing.
    @discardableResult
    func showFromPreferences(in region: CGRect) async -> Bool {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            Toast.error("Shot can't use the camera. Turn it on in System Settings › Privacy & Security › Camera.")
            return false
        }
        let prefs = Preferences()
        do {
            try await show(in: region, preferred: prefs.cameraSize, deviceID: prefs.cameraDeviceID)
        } catch CameraError.regionTooSmall {
            Toast.error(CameraError.regionTooSmall.localizedDescription)
        } catch {
            Toast.error("Camera unavailable: \(error.localizedDescription)")
        }
        return isVisible
    }

    /// `region` is the recorded area in AppKit global space.
    func show(in region: CGRect, preferred: CameraBubbleSize, deviceID: String) async throws {
        hide()
        let current = generation
        guard let size = CameraBubbleSize.fitting(preferred, in: region, inset: CameraBubbleStyle.inset) else {
            throw CameraError.regionTooSmall
        }
        guard let device = CaptureDevices.device(id: deviceID, for: .video) else {
            throw CameraError.noCamera
        }
        let session = AVCaptureSession()
        session.sessionPreset = .high
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CameraError.cannotUseCamera
        }
        session.addInput(input)
        // A camera's first frames, before it has set its exposure, are black. They're counted here so the bubble only
        // shows, and the recording only starts, once the picture is live.
        let warmUp = CameraWarmUp(device: device)
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(output) {
            output.setSampleBufferDelegate(warmUp, queue: DispatchQueue(label: "camera-warm-up"))
            session.addOutput(output)
        } else {
            warmUp.finish()
        }
        let panel = CameraBubblePanel(session: session, frame: CameraBubbleLayout.initialFrame(in: region, diameter: size.diameter, inset: CameraBubbleStyle.inset), size: size, region: region)
        panel.showsHandle = showsHandle
        let box = SessionBox(session: session)
        await Task.detached { box.session.startRunning() }.value
        await warmUp.wait(upTo: .milliseconds(1500))
        // Once it's warm the frames aren't needed, so nothing handles them while recording.
        output.setSampleBufferDelegate(nil, queue: nil)
        guard current == generation else {
            Task.detached { box.session.stopRunning() }
            return
        }
        panel.orderFrontRegardless()
        // The preview layer draws its first frame a moment after the window appears.
        try? await Task.sleep(for: .milliseconds(100))
        guard current == generation else {
            panel.orderOut(nil)
            Task.detached { box.session.stopRunning() }
            return
        }
        self.session = session
        self.panel = panel
        log.notice("Camera bubble shown: \(device.localizedName, privacy: .public), \(size.rawValue, privacy: .public)")
    }

    func hide() {
        generation += 1
        panel?.orderOut(nil)
        panel = nil
        if let session {
            let box = SessionBox(session: session)
            Task.detached { box.session.stopRunning() }
        }
        session = nil
    }
}

/// Waits for the camera's first few frames and for its exposure to settle, so the bubble never starts black.
private final class CameraWarmUp: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    /// About a sixth of a second at 30 fps: enough for most cameras to stop sending black frames.
    private static let framesNeeded = 5

    private let device: AVCaptureDevice
    private let lock = NSLock()
    private var frames = 0
    private var done = false
    private var continuation: CheckedContinuation<Void, Never>?

    init(device: AVCaptureDevice) {
        self.device = device
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        lock.lock()
        frames += 1
        let ready = frames >= Self.framesNeeded && !device.isAdjustingExposure
        lock.unlock()
        if ready {
            finish()
        }
    }

    /// Returns once the camera is warm, or after `timeout` for one that never settles.
    func wait(upTo timeout: Duration) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if done {
                lock.unlock()
                continuation.resume()
                return
            }
            self.continuation = continuation
            lock.unlock()
            Task {
                try? await Task.sleep(for: timeout)
                self.finish()
            }
        }
    }

    func finish() {
        lock.lock()
        done = true
        let waiting = continuation
        continuation = nil
        lock.unlock()
        waiting?.resume()
    }
}

/// The bubble's window: the circle and its ring, with macOS's own shadow, which follows the circle and catches no clicks.
private final class CameraBubblePanel: NSPanel {
    private let previewLayer: AVCaptureVideoPreviewLayer
    private let videoLayer = CALayer()
    private let ringLayer = CAShapeLayer()
    private let contrastLayer = CAShapeLayer()
    private let handleLayer = CAShapeLayer()
    private let bubbleView = BubbleView()
    private(set) var size: CameraBubbleSize
    var region: CGRect {
        didSet { place(circle) }
    }

    var showsHandle = false {
        didSet {
            guard showsHandle != oldValue else {
                return
            }
            layoutLayers()
        }
    }

    /// `frame` is the circle; the window adds room for the ring around it.
    init(session: AVCaptureSession, frame: CGRect, size: CameraBubbleSize, region: CGRect) {
        self.size = size
        self.region = region
        previewLayer = AVCaptureVideoPreviewLayer(session: session)
        super.init(contentRect: Self.windowFrame(forCircle: frame), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        previewLayer.videoGravity = .resizeAspectFill
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        bubbleView.panel = self
        bubbleView.wantsLayer = true
        for layer in [contrastLayer, ringLayer, videoLayer, handleLayer] {
            bubbleView.layer?.addSublayer(layer)
        }
        videoLayer.addSublayer(previewLayer)
        videoLayer.masksToBounds = true
        videoLayer.backgroundColor = NSColor.black.cgColor
        ringLayer.fillColor = NSColor.white.cgColor
        contrastLayer.fillColor = nil
        contrastLayer.strokeColor = Brutal.inkNS.cgColor
        handleLayer.fillColor = NSColor.white.cgColor
        handleLayer.strokeColor = Brutal.inkNS.cgColor
        contentView = bubbleView
        layoutLayers()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(displayOptionsChanged), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func displayOptionsChanged() {
        layoutLayers()
    }

    private static func windowFrame(forCircle circle: CGRect) -> CGRect {
        circle.insetBy(dx: -CameraBubbleStyle.margin, dy: -CameraBubbleStyle.margin)
    }

    /// The circle in AppKit global space.
    var circle: CGRect {
        frame.insetBy(dx: CameraBubbleStyle.margin, dy: CameraBubbleStyle.margin)
    }

    /// The handle's centre in the view, or `nil` while it's hidden.
    var handleCenter: CGPoint? {
        guard showsHandle else {
            return nil
        }
        let center = CameraBubbleLayout.handleCenter(for: circle, in: region)
        return CGPoint(x: center.x - frame.minX, y: center.y - frame.minY)
    }

    /// Whether the handle sits on the circle's right, so the pointer can show the matching resize arrows.
    var handleOnRight: Bool {
        CameraBubbleLayout.handleCenter(for: circle, in: region).x > circle.midX
    }

    private func layoutLayers() {
        let scale = backingScaleFactor
        let margin = CameraBubbleStyle.margin
        let ring = CameraBubbleStyle.ringWidth
        let local = CGRect(x: margin, y: margin, width: size.diameter, height: size.diameter)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoLayer.frame = local
        videoLayer.cornerRadius = size.diameter / 2
        previewLayer.frame = videoLayer.bounds
        // The ring is a white disc behind the camera, so its inner edge never shows a seam against the clipped picture.
        ringLayer.path = CGPath(ellipseIn: local.insetBy(dx: -ring, dy: -ring), transform: nil)
        let edge = Brutal.inkWidth(CameraBubbleStyle.contrastEdgeWidth, scale: scale)
        contrastLayer.lineWidth = edge
        contrastLayer.path = CGPath(ellipseIn: local.insetBy(dx: -ring - edge / 2, dy: -ring - edge / 2), transform: nil)
        contrastLayer.isHidden = !NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        if let center = handleCenter {
            let width = Brutal.inkWidth(CameraBubbleStyle.handleEdgeWidth, scale: scale)
            let side = CameraBubbleStyle.handleDiameter + width
            handleLayer.lineWidth = width
            handleLayer.path = CGPath(ellipseIn: CGRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side), transform: nil)
            handleLayer.isHidden = false
        } else {
            handleLayer.isHidden = true
        }
        CATransaction.commit()
        invalidateShadow()
        invalidateCursorRects(for: bubbleView)
        bubbleView.updateAccessibility(size: size)
    }

    private func place(_ circle: CGRect) {
        setFrame(Self.windowFrame(forCircle: CameraBubbleLayout.clamped(circle, in: region, inset: CameraBubbleStyle.inset)), display: true)
        layoutLayers()
    }

    /// Moves the bubble so the window's origin is `origin`, kept inside the recorded area.
    func place(windowOrigin origin: CGPoint) {
        let margin = CameraBubbleStyle.margin
        place(CGRect(x: origin.x + margin, y: origin.y + margin, width: size.diameter, height: size.diameter))
    }

    /// Changes the size around the bubble's centre. `remember` makes it the size the next bubble starts at.
    func resize(to newSize: CameraBubbleSize, remember: Bool) {
        if remember {
            SettingsStore.shared.set(newSize.rawValue, forKey: PreferenceKey.cameraSize)
        }
        guard newSize != size else {
            return
        }
        let circle = circle
        size = newSize
        place(CameraBubbleLayout.resized(circle, to: size.diameter))
    }

    func cycleSize() {
        resize(to: CameraBubbleSize.fitting(size.next, in: region, inset: CameraBubbleStyle.inset) == size.next ? size.next : .small, remember: true)
    }

    /// One size larger or smaller, stopping at the largest that fits. Returns whether the size changed.
    @discardableResult
    func step(by step: Int) -> Bool {
        guard let next = size.stepped(by: step), CameraBubbleSize.fitting(next, in: region, inset: CameraBubbleStyle.inset) == next else {
            return false
        }
        resize(to: next, remember: true)
        return true
    }

    /// Whether a step that way would change the size, so VoiceOver offers only the actions that work.
    func canStep(by step: Int) -> Bool {
        guard let next = size.stepped(by: step) else {
            return false
        }
        return CameraBubbleSize.fitting(next, in: region, inset: CameraBubbleStyle.inset) == next
    }

    /// The size a handle drag at `pointer`, in AppKit global space, asks for.
    func resizeTarget(at pointer: CGPoint) -> CameraBubbleSize? {
        CameraBubbleLayout.resizeTarget(pointer: pointer, circle: circle, region: region, inset: CameraBubbleStyle.inset)
    }
}

/// Takes the bubble's mouse: dragging moves it, double-clicking changes its size, and while checking before recording
/// dragging the handle resizes it. VoiceOver reads it as the camera bubble with its size, and can make it larger or smaller.
private final class BubbleView: NSView {
    weak var panel: CameraBubblePanel?
    private enum Drag {
        case move(grab: CGVector)
        case resize(start: CameraBubbleSize)
    }
    private var drag: Drag?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func onHandle(_ point: CGPoint) -> Bool {
        guard let center = panel?.handleCenter else {
            return false
        }
        let half = CameraBubbleStyle.handleHitSize / 2
        return abs(point.x - center.x) <= half && abs(point.y - center.y) <= half
    }

    override func mouseDown(with event: NSEvent) {
        guard let panel else {
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        if onHandle(point) {
            drag = .resize(start: panel.size)
        } else if event.clickCount == 2 {
            drag = nil
            panel.cycleSize()
        } else {
            let mouse = NSEvent.mouseLocation
            drag = .move(grab: CGVector(dx: mouse.x - panel.frame.minX, dy: mouse.y - panel.frame.minY))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let panel, let drag else {
            return
        }
        let mouse = NSEvent.mouseLocation
        switch drag {
        case .move(let grab):
            panel.place(windowOrigin: CGPoint(x: mouse.x - grab.dx, y: mouse.y - grab.dy))
        case .resize:
            if let target = panel.resizeTarget(at: mouse) {
                panel.resize(to: target, remember: false)
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        if case .resize(let start) = drag, let panel, panel.size != start {
            panel.resize(to: panel.size, remember: true)
        }
        drag = nil
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
        if let panel, let center = panel.handleCenter {
            let half = CameraBubbleStyle.handleHitSize / 2
            let rect = CGRect(x: center.x - half, y: center.y - half, width: half * 2, height: half * 2)
            addCursorRect(rect, cursor: .frameResize(position: panel.handleOnRight ? .bottomRight : .bottomLeft, directions: .all))
        }
    }

    // MARK: Accessibility

    func updateAccessibility(size: CameraBubbleSize) {
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "Camera bubble"))
        setAccessibilityValue(size.title)
        setAccessibilityHelp(String(localized: "Drag to move it. Double-click to change its size."))
        var actions: [NSAccessibilityCustomAction] = []
        if panel?.canStep(by: 1) == true {
            actions.append(NSAccessibilityCustomAction(name: String(localized: "Make larger")) { [weak self] in
                self?.panel?.step(by: 1) ?? false
            })
        }
        if panel?.canStep(by: -1) == true {
            actions.append(NSAccessibilityCustomAction(name: String(localized: "Make smaller")) { [weak self] in
                self?.panel?.step(by: -1) ?? false
            })
        }
        setAccessibilityCustomActions(actions)
    }

    override func accessibilityPerformIncrement() -> Bool {
        panel?.step(by: 1) ?? false
    }

    override func accessibilityPerformDecrement() -> Bool {
        panel?.step(by: -1) ?? false
    }
}

extension CameraBubbleSize {
    /// The size's name, as Settings › Recording and VoiceOver say it.
    var title: String {
        switch self {
        case .small: String(localized: "Small")
        case .medium: String(localized: "Medium")
        case .large: String(localized: "Large")
        }
    }
}
