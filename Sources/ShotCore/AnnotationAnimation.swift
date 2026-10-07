import CoreGraphics
import Foundation

extension Annotation {
    /// Arrows, lines and pen strokes can be drawn a bit at a time.
    public var canReveal: Bool {
        switch kind {
        case .arrow, .line, .freehand: true
        default: false
        }
    }

    /// Every point of it moved by `delta`.
    public func moved(by delta: CGSize) -> Annotation {
        var copy = self
        copy.offset(by: CGVector(dx: delta.width, dy: delta.height))
        return copy
    }

    /// The annotation scaled by `factor` about the centre of its bounds; strokes, text and counters grow with it.
    public func scaled(by factor: Double) -> Annotation {
        guard abs(factor - 1) > 1e-9, factor > 0 else {
            return self
        }
        let bounds = bounds
        guard !bounds.isNull else {
            return self
        }
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let s = CGFloat(factor)
        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: center.x + (p.x - center.x) * s, y: center.y + (p.y - center.y) * s) }
        func rect(_ r: CGRect) -> CGRect { CGRect(x: center.x + (r.minX - center.x) * s, y: center.y + (r.minY - center.y) * s, width: r.width * s, height: r.height * s) }
        var copy = self
        copy.lineWidth = lineWidth * s
        copy.bend = bend.map { CGVector(dx: $0.dx * s, dy: $0.dy * s) }
        switch kind {
        case let .arrow(from, to): copy.kind = .arrow(from: point(from), to: point(to))
        case let .line(from, to): copy.kind = .line(from: point(from), to: point(to))
        case let .shape(shape, r): copy.kind = .shape(shape, rect: rect(r))
        case let .highlight(r): copy.kind = .highlight(rect(r))
        case let .pixelate(r, amount): copy.kind = .pixelate(rect(r), amount: amount)
        case let .blur(r, amount): copy.kind = .blur(rect(r), amount: amount)
        case let .spotlight(r, style): copy.kind = .spotlight(rect(r), style: style)
        case let .image(image, r): copy.kind = .image(image, rect: rect(r))
        case let .counter(number, c): copy.kind = .counter(number, center: point(c))
        case let .freehand(points): copy.kind = .freehand(points.map(point))
        case let .note(string, r): copy.kind = .note(string, rect: rect(r))
        case let .text(string, origin, fontSize):
            let size = bounds.size
            let scaledSize = CGSize(width: size.width * s, height: size.height * s)
            copy.kind = .text(string, origin: CGPoint(x: center.x - scaledSize.width / 2, y: center.y - scaledSize.height / 2), fontSize: fontSize * s)
            _ = origin
        }
        return copy
    }

    /// Only the first `progress` of an arrow, line or pen stroke, from its start; anything else whole.
    public func revealed(_ progress: Double) -> Annotation {
        let p = min(max(progress, 0), 1)
        guard p < 1 else {
            return self
        }
        var copy = self
        switch kind {
        case let .arrow(from, to):
            copy.kind = .arrow(from: from, to: CGPoint(x: from.x + (to.x - from.x) * p, y: from.y + (to.y - from.y) * p))
            copy.bend = bend.map { CGVector(dx: $0.dx * p, dy: $0.dy * p) }
        case let .line(from, to):
            copy.kind = .line(from: from, to: CGPoint(x: from.x + (to.x - from.x) * p, y: from.y + (to.y - from.y) * p))
            copy.bend = bend.map { CGVector(dx: $0.dx * p, dy: $0.dy * p) }
        case let .freehand(points):
            copy.kind = .freehand(Self.prefix(of: points, fraction: p))
        default:
            break
        }
        return copy
    }

    /// The first `fraction` of the way along `points`, by length, ending exactly there.
    static func prefix(of points: [CGPoint], fraction: Double) -> [CGPoint] {
        guard points.count > 1 else {
            return points
        }
        let lengths = zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        let target = lengths.reduce(0, +) * fraction
        var covered = 0.0
        var result = [points[0]]
        for (index, length) in lengths.enumerated() {
            if covered + length >= target {
                let t = length == 0 ? 0 : (target - covered) / length
                let a = points[index], b = points[index + 1]
                result.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                return result
            }
            covered += length
            result.append(points[index + 1])
        }
        return result
    }
}

extension AnnotationClip {
    /// What to draw at timeline `time`: the annotation with its keyframes applied, and the turn and fade to give the result.
    public func rendered(atTimeline time: Double) -> (annotation: Annotation, rotation: Double, opacity: Double) {
        let values = values(atTimeline: time)
        let drawn = annotation.revealed(values.reveal).scaled(by: values.scale).moved(by: values.position)
        return (drawn, values.rotation, values.opacity)
    }
}
