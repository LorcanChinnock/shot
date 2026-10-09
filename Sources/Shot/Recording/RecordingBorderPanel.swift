import AppKit

/// Outline around the recording region; Shot is excluded from the capture, so it never appears in the video.
final class RecordingBorderPanel: NSPanel {
    enum Style {
        /// Framing before recording: ink line with a white dashed inner line.
        case setup
        case recording
        case paused
    }

    static let lineWidth: CGFloat = 3

    init(region: CGRect, style: Style = .recording) {
        super.init(contentRect: Self.frame(for: region), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = BorderView(style: style)
        setFrame(Self.frame(for: region), display: false)
    }

    private static func frame(for region: CGRect) -> CGRect {
        region.insetBy(dx: -lineWidth, dy: -lineWidth)
    }

    func setRegion(_ region: CGRect) {
        setFrame(Self.frame(for: region), display: true)
    }

    func setStyle(_ style: Style) {
        (contentView as? BorderView)?.style = style
        contentView?.needsDisplay = true
    }

    private final class BorderView: NSView {
        var style: Style

        init(style: Style) {
            self.style = style
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func draw(_ dirtyRect: NSRect) {
            let width = RecordingBorderPanel.lineWidth
            let path = NSBezierPath(rect: bounds.insetBy(dx: width / 2, dy: width / 2))
            path.lineWidth = width
            switch style {
            case .setup:
                Brutal.inkNS.setStroke()
                path.stroke()
                let inner = NSBezierPath(rect: bounds.insetBy(dx: width / 2, dy: width / 2))
                inner.lineWidth = 1.5
                inner.setLineDash([8, 6], count: 2, phase: 0)
                NSColor.white.setStroke()
                inner.stroke()
            case .recording:
                Brutal.redNS.setStroke()
                path.stroke()
            case .paused:
                Brutal.yellowNS.setStroke()
                path.setLineDash([10, 6], count: 2, phase: 0)
                path.stroke()
            }
        }
    }
}
