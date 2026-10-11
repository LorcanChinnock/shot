import AppKit

/// How both editors' canvases show what's selected: a dashed outline and white handles bordered in the system accent
/// colour, which follows the user's macOS setting and stands out on most screenshots.
@MainActor
enum SelectionStyle {
    private static let lineWidth: CGFloat = 1.5
    private static let dash: [CGFloat] = [4, 3]
    private static let handleSize: CGFloat = 8

    /// A dashed outline round `rect`, in view points.
    static func outline(_ rect: CGRect) {
        let path = NSBezierPath(rect: rect)
        path.lineWidth = lineWidth
        path.setLineDash(dash, count: dash.count, phase: 0)
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }

    /// A resize handle at `center`, in view points: a square, or a dot for a corner-radius handle.
    static func handle(at center: CGPoint, round: Bool = false) {
        let box = CGRect(x: center.x - handleSize / 2, y: center.y - handleSize / 2, width: handleSize, height: handleSize)
        let path = round ? NSBezierPath(ovalIn: box) : NSBezierPath(rect: box)
        NSColor.white.setFill()
        path.fill()
        path.lineWidth = lineWidth
        NSColor.controlAccentColor.setStroke()
        path.stroke()
    }
}
