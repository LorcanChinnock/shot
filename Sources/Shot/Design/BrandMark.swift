import AppKit
import Observation
import ShotCore

/// The app icon's viewfinder mark as a menu bar template image; macOS tints it for light and dark menu bars.
/// The centre mark shows the state, and a corner dot shows an update is waiting. While counting down the digit flips each
/// second, and while recording a ring breathes out of the mark (`MenuBarAnimation`).
enum BrandMark {
    enum State: Equatable {
        case idle, recording, paused
        /// Seconds left before a timed screenshot or a recording starts.
        case countdown(Int)
    }

    static let size = NSSize(width: 18, height: 18)

    /// `flip` is the digit counted down from and how far through its flip the icon is; `pulse` is how far through a breath.
    static func menuBarImage(_ state: State, updateAvailable: Bool = false, flip: MenuBarAnimation.Flip? = nil, pulse: Double? = nil) -> NSImage {
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.set()
            drawBrackets(in: rect.insetBy(dx: 1.5, dy: 1.5), badged: updateAvailable)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            switch state {
            case .idle:
                NSBezierPath(ovalIn: CGRect(x: center.x - 2.75, y: center.y - 2.75, width: 5.5, height: 5.5)).fill()
            case .recording:
                if let pulse {
                    drawPulse(pulse, centeredAt: center)
                }
                NSBezierPath(roundedRect: CGRect(x: center.x - 3, y: center.y - 3, width: 6, height: 6), xRadius: 1, yRadius: 1).fill()
            case .paused:
                NSBezierPath(roundedRect: CGRect(x: center.x - 3, y: center.y - 3.25, width: 2.2, height: 6.5), xRadius: 0.6, yRadius: 0.6).fill()
                NSBezierPath(roundedRect: CGRect(x: center.x + 0.8, y: center.y - 3.25, width: 2.2, height: 6.5), xRadius: 0.6, yRadius: 0.6).fill()
            case let .countdown(seconds):
                if let flip {
                    let frame = Moment.flip(flip.progress)
                    drawNumber(frame.showsPrevious ? flip.previous : seconds, centeredAt: center, height: frame.height)
                } else {
                    drawNumber(seconds, centeredAt: center)
                }
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
    /// `height` squashes it towards its middle, for a flip.
    private static func drawNumber(_ number: Int, centeredAt center: CGPoint, height: Double = 1) {
        guard height > 0.02 else {
            return
        }
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y)
        transform.scaleX(by: 1, yBy: height)
        transform.translateX(by: -center.x, yBy: -center.y)
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        transform.concat()
        let text = "\(number)"
        let font = NSFont.systemFont(ofSize: text.count > 1 ? 8.5 : 10.5, weight: .heavy)
        let string = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.black])
        let bounds = string.boundingRect(with: .zero, options: [.usesLineFragmentOrigin, .usesFontLeading])
        // Centre the digits' cap height rather than the line, whose descender would push them up.
        let origin = CGPoint(x: center.x - bounds.width / 2, y: center.y - font.capHeight / 2 + font.descender)
        string.draw(at: origin)
    }

    /// A faint disc behind the recording mark, growing and fading as `phase` runs through a breath.
    private static func drawPulse(_ phase: Double, centeredAt center: CGPoint) {
        let breath = Moment.pulse(phase)
        guard breath.opacity > 0.01 else {
            return
        }
        let radius = 3.5 + 3 * breath.spread
        NSColor.black.withAlphaComponent(breath.opacity).set()
        NSBezierPath(ovalIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)).fill()
        NSColor.black.set()
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

/// Drives the menu bar icon's moments: the countdown digit flipping each second, and the recording mark breathing. It runs
/// a frame loop only while one is playing, so the icon costs nothing at rest. Reduce Motion turns both off.
@MainActor
@Observable
final class MenuBarAnimation {
    struct Flip: Equatable {
        let previous: Int
        let progress: Double
    }

    private(set) var flip: Flip?
    private(set) var pulse: Double?
    @ObservationIgnored private var flipStart: (previous: Int, at: ContinuousClock.Instant)?
    @ObservationIgnored private var pulseStart: ContinuousClock.Instant?
    @ObservationIgnored private var loop: Task<Void, Never>?

    func countdownChanged(from old: Int?, to new: Int?) {
        guard let old, let new, old != new, !Motion.reduced else {
            flipStart = nil
            flip = nil
            return
        }
        flipStart = (old, .now)
        run()
    }

    func recordingChanged(_ live: Bool) {
        guard live, !Motion.reduced else {
            pulseStart = nil
            pulse = nil
            return
        }
        if pulseStart == nil {
            pulseStart = .now
            run()
        }
    }

    private func run() {
        step()
        guard loop == nil else {
            return
        }
        loop = Task { [weak self] in
            while let self, flipStart != nil || pulseStart != nil {
                // Smooth for the short flip, gentler on the long breath.
                try? await Task.sleep(for: .milliseconds(flipStart != nil ? 33 : 50))
                step()
            }
            self?.loop = nil
        }
    }

    private func step() {
        let now = ContinuousClock.now
        if let start = flipStart {
            let progress = seconds(now - start.at) / Moment.countdownFlip.duration
            if progress >= 1 {
                flipStart = nil
                flip = nil
            } else {
                flip = Flip(previous: start.previous, progress: progress)
            }
        }
        if let start = pulseStart {
            pulse = seconds(now - start) / Moment.recordingPulse.duration
        }
    }

    private func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}
