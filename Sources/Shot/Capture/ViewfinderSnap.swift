import AppKit
import QuartzCore
import ShotCore

/// The viewfinder's corners snapping in over a capture with a soft flash, like the app icon's brackets. It plays after
/// the capture is copied and never takes a click, so it can't slow or block anything. Shot leaves its own windows out of
/// every capture, so it never shows up in the next one.
///
/// It's drawn with shape layers rather than a SwiftUI view, so the render server draws it and Shot never paints a
/// screen-sized bitmap for a full-screen capture.
@MainActor
enum ViewfinderSnap {
    private static var panel: NSPanel?
    private static var closeTask: Task<Void, Never>?
    /// Room around the capture for the brackets to fly in from.
    private static let margin: CGFloat = 18
    /// How far out each bracket starts.
    private static let spread: CGFloat = 14
    /// The snap, then a short hold, then a 120 ms fade out.
    private static let hold: TimeInterval = 0.18

    /// Plays over `frame`, the capture's AppKit global rect, cut to the screen it's on.
    static func play(over frame: CGRect) {
        guard let screen = NSScreen.screens.max(by: { area($0.frame.intersection(frame)) < area($1.frame.intersection(frame)) }) else {
            return
        }
        let visible = frame.intersection(screen.frame)
        guard visible.width >= 24, visible.height >= 24 else {
            return
        }
        let reduced = Motion.reduced
        closeTask?.cancel()
        panel?.close()
        let panel = makePanel(frame: visible.insetBy(dx: -margin, dy: -margin))
        self.panel = panel
        let capture = CGRect(origin: CGPoint(x: margin, y: margin), size: visible.size)
        let length = panel.contentView.map { animate(in: $0, capture: capture, reduced: reduced) } ?? 0
        panel.orderFrontRegardless()
        closeTask = Task {
            try? await Task.sleep(for: .seconds(length + 0.05))
            guard !Task.isCancelled else {
                return
            }
            // Closed and let go rather than kept hidden, so nothing of it stays in memory.
            panel.close()
            if self.panel === panel {
                self.panel = nil
            }
        }
    }

    private static func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }

    private static func makePanel(frame: CGRect) -> NSPanel {
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.isReleasedWhenClosed = false
        let view = NSView(frame: CGRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        panel.contentView = view
        return panel
    }

    /// Adds the flash and the four brackets to `view`'s layer and starts them. Returns how long it all lasts.
    private static func animate(in view: NSView, capture: CGRect, reduced: Bool) -> TimeInterval {
        guard let root = view.layer else {
            return 0
        }
        let snap = Moment.viewfinderSnap.duration
        let fade = Moment.reducedFade
        let arrive = reduced ? fade : snap
        let length = arrive + hold + fade
        let scale = view.window?.backingScaleFactor ?? 2

        let flash = CALayer()
        flash.frame = capture
        flash.backgroundColor = NSColor.white.cgColor
        flash.opacity = 0
        root.addSublayer(flash)

        let brackets = CALayer()
        brackets.frame = root.bounds
        brackets.opacity = 0
        root.addSublayer(brackets)

        let arm = min(28, min(capture.width, capture.height) * 0.25)
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: capture.minX, y: capture.minY), 1, 1),
            (CGPoint(x: capture.maxX, y: capture.minY), -1, 1),
            (CGPoint(x: capture.minX, y: capture.maxY), 1, -1),
            (CGPoint(x: capture.maxX, y: capture.maxY), -1, -1),
        ]
        for (corner, dx, dy) in corners {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
            let bracket = CALayer()
            bracket.frame = root.bounds
            for (color, width) in [(NSColor.white.withAlphaComponent(0.9), CGFloat(7)), (NSColor(white: 0.086, alpha: 1), CGFloat(4))] {
                let shape = CAShapeLayer()
                shape.frame = root.bounds
                shape.path = path
                shape.fillColor = nil
                shape.strokeColor = color.cgColor
                shape.lineWidth = width
                shape.lineCap = .round
                shape.lineJoin = .round
                shape.contentsScale = scale
                bracket.addSublayer(shape)
            }
            brackets.addSublayer(bracket)
            guard !reduced else {
                continue
            }
            // Each bracket starts out past its corner, overshoots it a little and settles on it.
            let snapIn = CAKeyframeAnimation(keyPath: "transform")
            snapIn.values = [-spread, 2, 0].map { inset in
                NSValue(caTransform3D: CATransform3DMakeTranslation(dx * inset, dy * inset, 0))
            }
            snapIn.keyTimes = [0, 0.6, 1]
            snapIn.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut)]
            snapIn.duration = snap
            bracket.add(snapIn, forKey: "snap")
        }

        let appear = CAKeyframeAnimation(keyPath: "opacity")
        let shown = reduced ? fade : snap * 0.45
        appear.values = [0, 1, 1, 0]
        appear.keyTimes = [0, shown / length, (arrive + hold) / length, 1].map { NSNumber(value: $0) }
        appear.duration = length
        appear.fillMode = .forwards
        appear.isRemovedOnCompletion = false
        brackets.add(appear, forKey: "appear")

        if !reduced {
            let glow = CAKeyframeAnimation(keyPath: "opacity")
            let peak = snap * 0.6
            glow.values = [0, 0.3, 0]
            glow.keyTimes = [0, NSNumber(value: peak / (peak + 0.15)), 1]
            glow.duration = peak + 0.15
            flash.add(glow, forKey: "flash")
        }
        return length
    }
}
