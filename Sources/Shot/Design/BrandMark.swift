import AppKit

/// The app icon's viewfinder mark as a menu bar template image; macOS tints it for light and dark menu bars.
enum BrandMark {
    enum State {
        case idle, recording, paused
    }

    static let size = NSSize(width: 18, height: 18)

    static func menuBarImage(_ state: State) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.set()
            drawBrackets(in: rect.insetBy(dx: 1.5, dy: 1.5))
            let center = CGPoint(x: rect.midX, y: rect.midY)
            switch state {
            case .idle:
                NSBezierPath(ovalIn: CGRect(x: center.x - 2.75, y: center.y - 2.75, width: 5.5, height: 5.5)).fill()
            case .recording:
                NSBezierPath(roundedRect: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6), xRadius: 1, yRadius: 1).fill()
            case .paused:
                NSBezierPath(roundedRect: CGRect(x: center.x - 3, y: center.y - 3.25, width: 2.2, height: 6.5), xRadius: 0.6, yRadius: 0.6).fill()
                NSBezierPath(roundedRect: CGRect(x: center.x + 0.8, y: center.y - 3.25, width: 2.2, height: 6.5), xRadius: 0.6, yRadius: 0.6).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Shot"
        return image
    }

    /// Corner brackets matching the app icon's proportions.
    private static func drawBrackets(in frame: CGRect) {
        let arm = frame.width * 0.32
        let path = NSBezierPath()
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: frame.minX, y: frame.maxY), 1, -1),
            (CGPoint(x: frame.maxX, y: frame.maxY), -1, -1),
            (CGPoint(x: frame.minX, y: frame.minY), 1, 1),
            (CGPoint(x: frame.maxX, y: frame.minY), -1, 1),
        ]
        for (corner, dx, dy) in corners {
            path.move(to: CGPoint(x: corner.x, y: corner.y + dy * arm))
            path.line(to: corner)
            path.line(to: CGPoint(x: corner.x + dx * arm, y: corner.y))
        }
        path.lineWidth = 2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }
}
