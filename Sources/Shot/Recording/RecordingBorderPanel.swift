import AppKit

/// Red outline around the recorded region; Shot is excluded from the capture, so it never appears in the video.
final class RecordingBorderPanel: NSPanel {
    static let lineWidth: CGFloat = 2

    init(region: CGRect) {
        let frame = region.insetBy(dx: -Self.lineWidth, dy: -Self.lineWidth)
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = BorderView()
        setFrame(frame, display: false)
    }

    private final class BorderView: NSView {
        override func draw(_ dirtyRect: NSRect) {
            NSColor.systemRed.setStroke()
            let path = NSBezierPath(rect: bounds.insetBy(dx: RecordingBorderPanel.lineWidth / 2, dy: RecordingBorderPanel.lineWidth / 2))
            path.lineWidth = RecordingBorderPanel.lineWidth
            path.stroke()
        }
    }
}
