import AppKit
import ShotCore

/// Outline around a recording's region, or a scrolling capture's area; Shot is excluded from the capture, so it never
/// appears in the video or the frames. Shape layers draw it, so a large area adds no bitmap.
final class RecordingBorderPanel: NSPanel {
    enum Style {
        /// Record › While recording: 2 pt record red hugging the area with a 4 pt glow outside it.
        case recording
        /// The same 2 pt line, dashed in amber and without the glow, since red means recording (rule 6).
        case paused
        /// A scrolling capture's outline: the accent against the area with ink outside it, 1.5 pt each.
        case scrolling

        var outset: CGFloat {
            switch self {
            case .recording, .paused: RecordingBorder.outset
            case .scrolling: 3
            }
        }
    }

    private let outset: CGFloat

    init(region: CGRect, style: Style = .recording) {
        outset = style.outset
        let frame = region.insetBy(dx: -outset, dy: -outset)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = BorderView(style: style)
        setFrame(frame, display: false)
    }

    func setRegion(_ region: CGRect) {
        setFrame(region.insetBy(dx: -outset, dy: -outset), display: true)
    }

    /// Switches between recording and paused, which share an outset.
    func setStyle(_ style: Style) {
        (contentView as? BorderView)?.style = style
    }

    private final class BorderView: NSView {
        var style: Style {
            didSet { needsLayout = true }
        }

        private let outer = CAShapeLayer()
        private let inner = CAShapeLayer()

        init(style: Style) {
            self.style = style
            super.init(frame: .zero)
            wantsLayer = true
            for shape in [outer, inner] {
                shape.fillColor = nil
                layer?.addSublayer(shape)
            }
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(displayOptionsChanged), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        @objc private func displayOptionsChanged() {
            needsLayout = true
        }

        override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            needsLayout = true
        }

        override func layout() {
            super.layout()
            let scale = window?.backingScaleFactor ?? 2
            let contrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for shape in [outer, inner] {
                shape.frame = bounds
                shape.contentsScale = scale
                shape.lineDashPattern = nil
                shape.isHidden = false
            }
            switch style {
            case .recording, .paused:
                let ring = RecordingBorder.ring(in: bounds)
                inner.path = CGPath(roundedRect: ring.rect, cornerWidth: ring.radius, cornerHeight: ring.radius, transform: nil)
                inner.lineWidth = Brutal.inkWidth(RecordingBorder.lineWidth, scale: scale)
                if style == .recording {
                    inner.strokeColor = Self.recordRed.cgColor
                    let glow = RecordingBorder.glow(in: bounds)
                    outer.path = CGPath(roundedRect: glow.rect, cornerWidth: glow.radius, cornerHeight: glow.radius, transform: nil)
                    outer.lineWidth = Brutal.inkWidth(RecordingBorder.glowWidth, scale: scale)
                    let glowOpacity = contrast ? RecordingBorder.contrastGlowOpacity : RecordingBorder.glowOpacity
                    outer.strokeColor = Self.recordRed.withAlphaComponent(glowOpacity).cgColor
                } else {
                    inner.strokeColor = Self.amber.cgColor
                    inner.lineDashPattern = RecordingBorder.pausedDash.map { NSNumber(value: Double($0)) }
                    outer.isHidden = true
                }
            case .scrolling:
                let half = Brutal.inkWidth(1.5, scale: scale)
                outer.path = CGPath(rect: bounds.insetBy(dx: half / 2, dy: half / 2), transform: nil)
                outer.lineWidth = half
                outer.strokeColor = Brutal.inkNS.cgColor
                inner.path = CGPath(rect: bounds.insetBy(dx: half * 1.5, dy: half * 1.5), transform: nil)
                inner.lineWidth = half
                inner.strokeColor = Brutal.yellowNS.cgColor
            }
            CATransaction.commit()
        }

        /// The board's record red, `#FF453A`, which reads on light and dark content alike.
        static let recordRed = NSColor(srgbRed: 1, green: 0x45 / 255, blue: 0x3A / 255, alpha: 1)
        /// The paused marks' amber, as on the recording controls.
        static let amber = NSColor(srgbRed: 1, green: 0xB6 / 255, blue: 0x48 / 255, alpha: 1)
    }
}
