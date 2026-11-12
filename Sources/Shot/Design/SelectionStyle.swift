import AppKit
import SwiftUI

/// How both editors' canvases show what's selected: a dashed outline and white handles bordered in the system accent
/// colour, which follows the user's macOS setting and stands out on most screenshots.
@MainActor
enum SelectionStyle {
    static let lineWidth: CGFloat = 1.5
    static let dash: [CGFloat] = [4, 3]
    static let handleSize: CGFloat = 8

    /// The system accent colour, for SwiftUI views drawn over a canvas, such as the video editor's clip handles.
    static var color: Color { Color(nsColor: .controlAccentColor) }

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

/// `SelectionStyle.handle` for SwiftUI: an 8 pt white square, or a dot, bordered in the system accent colour, centred in
/// a larger frame that catches the pointer, so the handle is easy to grab.
struct SelectionHandle: View {
    var round = false
    var hitSize: CGFloat = 20

    var body: some View {
        ZStack {
            if round {
                Circle().fill(.white).overlay(Circle().stroke(SelectionStyle.color, lineWidth: SelectionStyle.lineWidth))
            } else {
                Rectangle().fill(.white).overlay(Rectangle().stroke(SelectionStyle.color, lineWidth: SelectionStyle.lineWidth))
            }
        }
        .frame(width: SelectionStyle.handleSize, height: SelectionStyle.handleSize)
        .frame(width: hitSize, height: hitSize)
        .contentShape(Rectangle())
    }
}
