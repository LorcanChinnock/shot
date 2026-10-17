import AppKit

/// The app icon's viewfinder mark as a menu bar template image; macOS tints it for light and dark menu bars.
/// The centre mark shows the state, and a corner dot shows an update is waiting.
enum BrandMark {
    enum State: Equatable {
        case idle, recording, paused
        /// Seconds left before a timed screenshot or a recording starts.
        case countdown(Int)
    }

    static let size = NSSize(width: 18, height: 18)

    static func menuBarImage(_ state: State, updateAvailable: Bool = false) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.set()
            drawBrackets(in: rect.insetBy(dx: 1.5, dy: 1.5), badged: updateAvailable)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            switch state {
            case .idle:
                NSBezierPath(ovalIn: CGRect(x: center.x - 2.75, y: center.y - 2.75, width: 5.5, height: 5.5)).fill()
            case .recording:
                NSBezierPath(roundedRect: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6), xRadius: 1, yRadius: 1).fill()
            case .paused:
                NSBezierPath(roundedRect: CGRect(x: center.x - 3, y: center.y - 3.25, width: 2.2, height: 6.5), xRadius: 0.6, yRadius: 0.6).fill()
                NSBezierPath(roundedRect: CGRect(x: center.x + 0.8, y: center.y - 3.25, width: 2.2, height: 6.5), xRadius: 0.6, yRadius: 0.6).fill()
            case let .countdown(seconds):
                drawNumber(seconds, centeredAt: center)
            }
            if updateAvailable {
                drawBadge(in: rect)
            }
            return true
        }
        image.isTemplate = true
        let description = switch state {
        case .idle: "Shot"
        case .recording: String(localized: "Shot, recording")
        case .paused: String(localized: "Shot, recording paused")
        case let .countdown(seconds): String(localized: "Shot, starting in \(seconds) seconds")
        }
        image.accessibilityDescription = updateAvailable ? String(localized: "\(description), update available") : description
        return image
    }

    /// The seconds left, sized so two digits still fit between the brackets.
    private static func drawNumber(_ number: Int, centeredAt center: CGPoint) {
        let text = "\(number)"
        let font = NSFont.systemFont(ofSize: text.count > 1 ? 8.5 : 10.5, weight: .heavy)
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.black])
        let bounds = string.boundingRect(with: .zero, options: [.usesLineFragmentOrigin, .usesFontLeading])
        // Centre the digits' cap height rather than the line, whose descender would push them up.
        let origin = CGPoint(x: center.x - bounds.width / 2, y: center.y - font.capHeight / 2 + font.descender)
        string.draw(at: origin)
    }

    /// A dot in place of the top-right bracket.
    private static func drawBadge(in rect: CGRect) {
        NSBezierPath(ovalIn: CGRect(x: rect.maxX - 5.75, y: rect.maxY - 5.75, width: 5, height: 5)).fill()
    }

    /// Corner brackets matching the app icon's proportions. `badged` leaves out the top-right one, where the badge goes.
    private static func drawBrackets(in frame: CGRect, badged: Bool) {
        let arm = frame.width * 0.32
        let path = NSBezierPath()
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (CGPoint(x: frame.minX, y: frame.maxY), 1, -1),
            (CGPoint(x: frame.maxX, y: frame.maxY), -1, -1),
            (CGPoint(x: frame.minX, y: frame.minY), 1, 1),
            (CGPoint(x: frame.maxX, y: frame.minY), -1, 1),
        ]
        for (index, (corner, dx, dy)) in corners.enumerated() where !(badged && index == 1) {
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
