import AppKit
import ShotCore

/// Draws a ring where you click inside the area while it records, when Settings › Recording › Show clicks is on
/// (Record › While recording). The ring lives in one small panel that the recording lets in, unlike Shot's other windows,
/// so it shows in the video as well as on screen. Clicks come from event monitors, which need no permission.
@MainActor
final class ClickRings {
    private let panel = ClickRingPanel()
    private let region: CGRect
    private let shouldShow: @MainActor () -> Bool
    private var monitors: [Any] = []

    /// `region` is the recorded area in AppKit global coordinates. `shouldShow` says whether a click now gets a ring, so
    /// clicks while paused, when nothing is recorded, don't.
    init(region: CGRect, shouldShow: @escaping @MainActor () -> Bool) {
        self.region = region
        self.shouldShow = shouldShow
    }

    /// The panel's window, which the recording's filter lets in.
    var windowID: CGWindowID { CGWindowID(panel.windowNumber) }

    /// Puts the empty panel on screen, so the filter built next can find it, and starts listening for clicks.
    func start() {
        panel.setFrame(ClickRing.frame(at: CGPoint(x: region.midX, y: region.midY)), display: false)
        panel.orderFrontRegardless()
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.clicked() }
        }) {
            monitors.append(global)
        }
        // Clicks on Shot's own windows, such as the gallery, which a recording keeps in.
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.clicked() }
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        panel.orderOut(nil)
    }

    private func clicked() {
        let point = NSEvent.mouseLocation
        guard shouldShow(), ClickRing.shows(at: point, in: region) else {
            return
        }
        panel.ring(at: point)
    }
}

/// The one panel a click ring is drawn in, moved to each click. A new click restarts the ring where it lands.
private final class ClickRingPanel: NSPanel {
    private let ring = CALayer()
    private let halo = CAShapeLayer()
    private let accent = CAShapeLayer()
    private let edge = CAShapeLayer()

    init() {
        let size = CGSize(width: ClickRing.extent, height: ClickRing.extent)
        super.init(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        // Above menus, so a click that opens one still shows its ring.
        level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        let view = NSView(frame: CGRect(origin: .zero, size: size))
        view.wantsLayer = true
        contentView = view
        ring.frame = view.bounds
        ring.opacity = 0
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        for (shape, radius) in [(halo, ClickRing.haloRadius), (accent, ClickRing.ringRadius), (edge, ClickRing.diameter / 2 + ClickRing.contrastEdgeWidth / 2)] {
            shape.frame = view.bounds
            shape.fillColor = nil
            shape.path = CGPath(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2), transform: nil)
            ring.addSublayer(shape)
        }
        view.layer?.addSublayer(ring)
    }

    func ring(at point: CGPoint) {
        setFrame(ClickRing.frame(at: point), display: false)
        let scale = backingScaleFactor
        let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        halo.lineWidth = Brutal.inkWidth(ClickRing.haloWidth, scale: scale)
        halo.strokeColor = Brutal.yellowNS.withAlphaComponent(contrast ? ClickRing.contrastHaloOpacity : ClickRing.haloOpacity).cgColor
        accent.lineWidth = Brutal.inkWidth(ClickRing.ringWidth, scale: scale)
        accent.strokeColor = Brutal.yellowNS.withAlphaComponent(ClickRing.ringOpacity).cgColor
        // Increase Contrast adds an ink edge inside the ring, so it reads on white.
        edge.isHidden = !contrast
        edge.lineWidth = Brutal.inkWidth(ClickRing.contrastEdgeWidth, scale: scale)
        edge.strokeColor = Brutal.inkNS.cgColor
        for shape in [halo, accent, edge] {
            shape.contentsScale = scale
        }
        ring.removeAllAnimations()
        // The model value is the end state; the animation holds the ring whole, then fades it, or with Reduce Motion
        // holds it and lets it go at once.
        ring.opacity = 0
        let hold = ClickRing.hold
        let fade = Motion.reduced ? 0 : Moment.clickRing.duration
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = fade > 0 ? [1, 1, 0] : [1, 1]
        animation.keyTimes = fade > 0 ? [0, NSNumber(value: hold / (hold + fade)), 1] : [0, 1]
        animation.timingFunctions = fade > 0 ? [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .easeOut)] : nil
        animation.duration = hold + fade
        ring.add(animation, forKey: "click")
        CATransaction.commit()
    }
}
