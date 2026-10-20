import Foundation

// Bounds and hit tests without CGPath, so they work where CoreGraphics doesn't. Curves are measured exactly for the
// bounding box and cut into short lines for containment, and every shape and arc is built from cubics as CoreGraphics
// builds it.

extension CanvasPath {
    /// The smallest rect holding the outline, its curves measured at their extremes rather than their control points,
    /// like `CGPath.boundingBoxOfPath`. `CGRect.null` when the path is empty.
    public var boundingBox: CGRect {
        Self.boundingBox(of: subpaths)
    }

    private static func boundingBox(of subpaths: [Subpath]) -> CGRect {
        var minX = CGFloat.infinity, minY = CGFloat.infinity, maxX = -CGFloat.infinity, maxY = -CGFloat.infinity
        func include(_ p: CGPoint) {
            minX = min(minX, p.x)
            minY = min(minY, p.y)
            maxX = max(maxX, p.x)
            maxY = max(maxY, p.y)
        }
        for subpath in subpaths {
            include(subpath.start)
            var current = subpath.start
            for segment in subpath.segments {
                switch segment {
                case let .line(to):
                    include(to)
                    current = to
                case let .cubic(to, c1, c2):
                    include(to)
                    for t in extremes(current.x, c1.x, c2.x, to.x) + extremes(current.y, c1.y, c2.y, to.y) {
                        include(cubicPoint(current, c1, c2, to, at: t))
                    }
                    current = to
                }
            }
        }
        return minX <= maxX ? CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY) : .null
    }

    /// Whether `point` is inside the outline, filled by the nonzero winding rule as `CGPath.contains` fills it. Open
    /// subpaths count as closed.
    public func contains(_ point: CGPoint) -> Bool {
        let subpaths = subpaths
        guard Self.boundingBox(of: subpaths).contains(point) else {
            return false
        }
        var winding = 0
        for polyline in Self.polylines(of: subpaths) where polyline.points.count > 2 {
            let points = polyline.points
            for (index, a) in points.enumerated() {
                let b = points[(index + 1) % points.count]
                let side = (b.x - a.x) * (point.y - a.y) - (point.x - a.x) * (b.y - a.y)
                if a.y <= point.y {
                    if b.y > point.y && side > 0 {
                        winding += 1
                    }
                } else if b.y <= point.y && side < 0 {
                    winding -= 1
                }
            }
        }
        return winding != 0
    }

    /// Whether `point` is inside the outline a stroke of `width` paints, with `cap` at the ends of open subpaths and
    /// `join` where elements meet, as `CGPath.copy(strokingWithWidth:lineCap:lineJoin:miterLimit:)` outlines it.
    /// Within a curve the stroke bends smoothly, whatever the join.
    public func strokeContains(_ point: CGPoint, width: CGFloat, cap: CanvasLineCap, join: CanvasLineJoin, miterLimit: CGFloat) -> Bool {
        let half = width / 2
        guard half > 0 else {
            return false
        }
        // Nothing reaches further from the outline than a miter's tip or a square cap's corner.
        let reach = half * max(join == .miter ? miterLimit : 1, 2)
        let subpaths = subpaths
        guard Self.boundingBox(of: subpaths).insetBy(dx: -reach, dy: -reach).contains(point) else {
            return false
        }
        func inDisk(_ center: CGPoint) -> Bool { hypot(point.x - center.x, point.y - center.y) <= half }
        for polyline in Self.polylines(of: subpaths) where polyline.draws {
            let points = polyline.points
            guard points.count > 1 else {
                // A zero-length stroke shows only as a round cap's dot.
                if cap == .round, inDisk(points[0]) {
                    return true
                }
                continue
            }
            let edgeCount = polyline.isClosed ? points.count : points.count - 1
            for index in 0..<edgeCount {
                // An open subpath's ends are cut square to the curve there, not to the line cut from it.
                let startEdge = !polyline.isClosed && index == 0 ? polyline.startDirection : nil
                let endEdge = !polyline.isClosed && index == edgeCount - 1 ? polyline.endDirection : nil
                if Self.inBody(point, points[index], points[(index + 1) % points.count], half: half, startEdge: startEdge, endEdge: endEdge) {
                    return true
                }
            }
            let joints = polyline.isClosed ? Array(points.indices) : Array(1..<points.count - 1)
            for index in joints {
                let vertex = points[index]
                let before = points[(index + points.count - 1) % points.count], after = points[(index + 1) % points.count]
                let vertexJoin = polyline.corners[index] ? join : .round
                if Self.inJoin(point, before: before, vertex: vertex, after: after, half: half, join: vertexJoin, miterLimit: miterLimit) {
                    return true
                }
            }
            if !polyline.isClosed {
                let ends = [(points[0], CGPoint(x: -polyline.startDirection.x, y: -polyline.startDirection.y)), (points[points.count - 1], polyline.endDirection)]
                for (end, outward) in ends {
                    switch cap {
                    case .butt:
                        break
                    case .round:
                        if inDisk(end) {
                            return true
                        }
                    case .square:
                        // The body carried on half the width past the end.
                        let length = hypot(outward.x, outward.y)
                        let past = CGPoint(x: end.x + outward.x / length * half, y: end.y + outward.y / length * half)
                        if Self.inBody(point, end, past, half: half) {
                            return true
                        }
                    }
                }
            }
        }
        return false
    }

    /// The distance from `p` to the nearest point on the segment from `a` to `b`.
    public static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(p.x - a.x, p.y - a.y)
        }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// A step of the outline in the few kinds every drawing library has.
    public enum Primitive: Equatable, Sendable {
        case move(to: CGPoint)
        case line(to: CGPoint)
        case curve(to: CGPoint, control1: CGPoint, control2: CGPoint)
        case close
    }

    /// The outline as moves, lines and cubics, built as `CGPath` builds it, so a library without CoreGraphics' shapes
    /// and arcs draws the same outline, starting at the same points and running the same way.
    public var primitives: [Primitive] {
        subpaths.flatMap { subpath -> [Primitive] in
            let segments = subpath.segments.map { segment -> Primitive in
                switch segment {
                case let .line(to): .line(to: to)
                case let .cubic(to, c1, c2): .curve(to: to, control1: c1, control2: c2)
                }
            }
            return [.move(to: subpath.start)] + segments + (subpath.isClosed ? [.close] : [])
        }
    }

    // MARK: - Subpaths

    private enum Segment {
        case line(to: CGPoint)
        case cubic(to: CGPoint, control1: CGPoint, control2: CGPoint)
    }

    /// A run of lines and cubics from `start`. `draws` is false for a lone move, which strokes nothing.
    private struct Subpath {
        var start: CGPoint
        var segments: [Segment] = []
        var isClosed = false
        var draws = false
    }

    /// The path as lines and cubics: quadratic curves raised to cubics, and rects, ellipses, rounded rects and arcs
    /// built as `CGPath` builds them, so they start at the same point and run the same way.
    private var subpaths: [Subpath] {
        var result: [Subpath] = []
        var current: Subpath?
        func finish() {
            if let subpath = current {
                result.append(subpath)
            }
            current = nil
        }
        // A line or curve with no move before it starts where the last subpath did, or at the origin.
        func add(_ segment: Segment) {
            if current == nil {
                current = Subpath(start: result.last?.start ?? .zero)
            }
            current!.segments.append(segment)
            current!.draws = true
        }
        func end() -> CGPoint {
            guard let subpath = current else {
                return result.last?.start ?? .zero
            }
            switch subpath.segments.last {
            case let .line(to): return to
            case let .cubic(to, _, _): return to
            case nil: return subpath.start
            }
        }
        func addClosed(_ start: CGPoint, _ segments: [Segment]) {
            finish()
            result.append(Subpath(start: start, segments: segments, isClosed: true, draws: true))
        }
        for element in elements {
            switch element {
            case let .move(to):
                finish()
                current = Subpath(start: to)
            case let .line(to):
                add(.line(to: to))
            case let .quadCurve(to, control):
                let from = end()
                add(.cubic(
                    to: to,
                    control1: CGPoint(x: from.x + (control.x - from.x) * 2 / 3, y: from.y + (control.y - from.y) * 2 / 3),
                    control2: CGPoint(x: to.x + (control.x - to.x) * 2 / 3, y: to.y + (control.y - to.y) * 2 / 3)
                ))
            case let .curve(to, control1, control2):
                add(.cubic(to: to, control1: control1, control2: control2))
            case let .arc(tangent1End, tangent2End, radius):
                for segment in Self.arc(from: end(), tangent1End: tangent1End, tangent2End: tangent2End, radius: radius) {
                    add(segment)
                }
            case let .rect(rect):
                addClosed(CGPoint(x: rect.minX, y: rect.minY), [
                    .line(to: CGPoint(x: rect.maxX, y: rect.minY)),
                    .line(to: CGPoint(x: rect.maxX, y: rect.maxY)),
                    .line(to: CGPoint(x: rect.minX, y: rect.maxY)),
                ])
            case let .ellipse(rect):
                let corners = Self.roundedCorners(rect, width: rect.width / 2, height: rect.height / 2)
                addClosed(CGPoint(x: rect.maxX, y: rect.midY), corners.map(\.corner))
            case let .roundedRect(rect, cornerWidth, cornerHeight):
                let width = min(cornerWidth, rect.width / 2), height = min(cornerHeight, rect.height / 2)
                guard width > 0, height > 0 else {
                    addClosed(CGPoint(x: rect.minX, y: rect.minY), [
                        .line(to: CGPoint(x: rect.maxX, y: rect.minY)),
                        .line(to: CGPoint(x: rect.maxX, y: rect.maxY)),
                        .line(to: CGPoint(x: rect.minX, y: rect.maxY)),
                    ])
                    continue
                }
                let corners = Self.roundedCorners(rect, width: width, height: height)
                addClosed(CGPoint(x: rect.maxX, y: rect.midY), corners.flatMap { [.line(to: $0.start), $0.corner] })
            case .close:
                if current != nil {
                    current!.isClosed = true
                }
                finish()
            }
        }
        finish()
        return result
    }

    /// The four quarter-ellipse corners of `rect`, each `width` by `height`, from the bottom right on round, with where
    /// each starts, in the order `CGPath(roundedRect:)` and `CGPath(ellipseIn:)` draw them.
    private static func roundedCorners(_ rect: CGRect, width: CGFloat, height: CGFloat) -> [(start: CGPoint, corner: Segment)] {
        // The control point distance that makes a cubic quarter circle, as CoreGraphics uses.
        let k: CGFloat = 0.552284749831
        let kx = width * k, ky = height * k
        return [
            (CGPoint(x: rect.maxX, y: rect.maxY - height), .cubic(
                to: CGPoint(x: rect.maxX - width, y: rect.maxY),
                control1: CGPoint(x: rect.maxX, y: rect.maxY - height + ky),
                control2: CGPoint(x: rect.maxX - width + kx, y: rect.maxY)
            )),
            (CGPoint(x: rect.minX + width, y: rect.maxY), .cubic(
                to: CGPoint(x: rect.minX, y: rect.maxY - height),
                control1: CGPoint(x: rect.minX + width - kx, y: rect.maxY),
                control2: CGPoint(x: rect.minX, y: rect.maxY - height + ky)
            )),
            (CGPoint(x: rect.minX, y: rect.minY + height), .cubic(
                to: CGPoint(x: rect.minX + width, y: rect.minY),
                control1: CGPoint(x: rect.minX, y: rect.minY + height - ky),
                control2: CGPoint(x: rect.minX + width - kx, y: rect.minY)
            )),
            (CGPoint(x: rect.maxX - width, y: rect.minY), .cubic(
                to: CGPoint(x: rect.maxX, y: rect.minY + height),
                control1: CGPoint(x: rect.maxX - width + kx, y: rect.minY),
                control2: CGPoint(x: rect.maxX, y: rect.minY + height - ky)
            )),
        ]
    }

    /// A line from `from` to where the arc starts, then the arc as cubics of at most a quarter turn each. Just the line
    /// to `tangent1End` when there's no corner to round.
    private static func arc(from: CGPoint, tangent1End corner: CGPoint, tangent2End: CGPoint, radius: CGFloat) -> [Segment] {
        let ux = from.x - corner.x, uy = from.y - corner.y, vx = tangent2End.x - corner.x, vy = tangent2End.y - corner.y
        let uLength = hypot(ux, uy), vLength = hypot(vx, vy)
        guard radius > 0, uLength > 0, vLength > 0 else {
            return [.line(to: corner)]
        }
        let u = CGPoint(x: ux / uLength, y: uy / uLength), v = CGPoint(x: vx / vLength, y: vy / vLength)
        let cross = u.x * v.y - u.y * v.x
        let angle = atan2(abs(cross), u.x * v.x + u.y * v.y)
        guard angle > 1e-9, angle < .pi - 1e-9 else {
            return [.line(to: corner)]
        }
        let along = radius / tan(angle / 2)
        let start = CGPoint(x: corner.x + u.x * along, y: corner.y + u.y * along)
        let bisector = hypot(u.x + v.x, u.y + v.y)
        let centreDistance = radius / sin(angle / 2)
        let centre = CGPoint(x: corner.x + (u.x + v.x) / bisector * centreDistance, y: corner.y + (u.y + v.y) / bisector * centreDistance)
        // The arc turns through the angle the corner doesn't, towards the second tangent.
        let sweep = (.pi - angle) * (cross > 0 ? -1 : 1)
        let startAngle = atan2(start.y - centre.y, start.x - centre.x)
        let pieces = max(1, Int((abs(sweep) / (.pi / 2)).rounded(.up)))
        let step = sweep / CGFloat(pieces)
        let k = 4 / 3 * tan(step / 4)
        var segments: [Segment] = [.line(to: start)]
        for piece in 0..<pieces {
            let a0 = startAngle + step * CGFloat(piece), a1 = a0 + step
            let p0 = CGPoint(x: centre.x + radius * cos(a0), y: centre.y + radius * sin(a0))
            let p1 = CGPoint(x: centre.x + radius * cos(a1), y: centre.y + radius * sin(a1))
            segments.append(.cubic(
                to: p1,
                control1: CGPoint(x: p0.x - k * radius * sin(a0), y: p0.y + k * radius * cos(a0)),
                control2: CGPoint(x: p1.x + k * radius * sin(a1), y: p1.y - k * radius * cos(a1))
            ))
        }
        return segments
    }

    // MARK: - Flattening

    /// How far a line cut from a curve may stray from it.
    private static let flatness: CGFloat = 0.05

    /// A subpath as points joined by lines, with no point repeating the one before it. `corners` says which points are
    /// where elements meet, which a stroke's join shapes; the rest are steps along a curve. The directions are the
    /// path's own as it leaves the first point and reaches the last, which the lines cut from a curve only approximate.
    private struct Polyline {
        var points: [CGPoint]
        var corners: [Bool]
        var isClosed: Bool
        var draws: Bool
        var startDirection = CGPoint.zero
        var endDirection = CGPoint.zero
    }

    private static func polylines(of subpaths: [Subpath]) -> [Polyline] {
        subpaths.map { subpath in
            var line = Polyline(points: [subpath.start], corners: [true], isClosed: subpath.isClosed, draws: subpath.draws)
            func add(_ p: CGPoint, corner: Bool) {
                if Self.isSamePoint(p, line.points[line.points.count - 1]) {
                    line.corners[line.corners.count - 1] = line.corners[line.corners.count - 1] || corner
                } else {
                    line.points.append(p)
                    line.corners.append(corner)
                }
            }
            // The first direction of `candidates` that isn't zero, which a segment with no length lacks.
            func direction(_ candidates: [(CGPoint, CGPoint)]) -> CGPoint? {
                candidates.lazy.map { CGPoint(x: $1.x - $0.x, y: $1.y - $0.y) }.first { !Self.isSamePoint($0, .zero) }
            }
            var started = false
            func follow(leaving start: CGPoint?, arriving end: CGPoint?) {
                guard let start, let end else {
                    return
                }
                if !started {
                    line.startDirection = start
                    started = true
                }
                line.endDirection = end
            }
            var current = subpath.start
            for segment in subpath.segments {
                switch segment {
                case let .line(to):
                    let along = direction([(current, to)])
                    follow(leaving: along, arriving: along)
                    add(to, corner: true)
                    current = to
                case let .cubic(to, c1, c2):
                    follow(leaving: direction([(current, c1), (current, c2), (current, to)]), arriving: direction([(c2, to), (c1, to), (current, to)]))
                    // Wang's formula: enough steps that none strays from the curve by more than the flatness.
                    let ddx = max(abs(current.x - 2 * c1.x + c2.x), abs(c1.x - 2 * c2.x + to.x))
                    let ddy = max(abs(current.y - 2 * c1.y + c2.y), abs(c1.y - 2 * c2.y + to.y))
                    let steps = min(1000, max(1, Int(sqrt(0.75 * hypot(ddx, ddy) / Self.flatness).rounded(.up))))
                    for step in 1..<steps {
                        add(Self.cubicPoint(current, c1, c2, to, at: CGFloat(step) / CGFloat(steps)), corner: false)
                    }
                    add(to, corner: true)
                    current = to
                }
            }
            if line.isClosed, line.points.count > 1, Self.isSamePoint(line.points[line.points.count - 1], line.points[0]) {
                line.points.removeLast()
                let lastIsCorner = line.corners.removeLast()
                line.corners[0] = line.corners[0] || lastIsCorner
            }
            return line
        }
    }

    /// Whether two points are close enough to count as one. Where neighbouring arcs meet, their ends can differ by
    /// rounding, and the tiny segment between them would point anywhere and give its joins spikes; CoreGraphics drops it.
    private static func isSamePoint(_ a: CGPoint, _ b: CGPoint) -> Bool {
        abs(a.x - b.x) < 1e-6 && abs(a.y - b.y) < 1e-6
    }

    // MARK: - Pieces of a stroke

    /// Whether `p` is within `half` of the segment from `a` to `b`, measured square to it: the body of a stroke, with
    /// no cap or join.
    /// `startEdge` and `endEdge`, when given, cut the ends square to those directions instead.
    private static func inBody(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint, half: CGFloat, startEdge: CGPoint? = nil, endEdge: CGPoint? = nil) -> Bool {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = hypot(dx, dy)
        guard length > 0 else {
            return false
        }
        let along = ((p.x - a.x) * dx + (p.y - a.y) * dy) / length
        let across = ((p.x - a.x) * dy - (p.y - a.y) * dx) / length
        let pastStart = startEdge.map { (p.x - a.x) * $0.x + (p.y - a.y) * $0.y >= 0 } ?? (along >= 0)
        let beforeEnd = endEdge.map { (p.x - b.x) * $0.x + (p.y - b.y) * $0.y <= 0 } ?? (along <= length)
        return pastStart && beforeEnd && abs(across) <= half
    }

    /// Whether `p` is in the join at `vertex`, the wedge on the outside of the turn that the bodies either side leave.
    private static func inJoin(_ p: CGPoint, before: CGPoint, vertex: CGPoint, after: CGPoint, half: CGFloat, join: CanvasLineJoin, miterLimit: CGFloat) -> Bool {
        let inLength = hypot(vertex.x - before.x, vertex.y - before.y), outLength = hypot(after.x - vertex.x, after.y - vertex.y)
        let d1 = CGPoint(x: (vertex.x - before.x) / inLength, y: (vertex.y - before.y) / inLength)
        let d2 = CGPoint(x: (after.x - vertex.x) / outLength, y: (after.y - vertex.y) / outLength)
        let cross = d1.x * d2.y - d1.y * d2.x
        let q = CGPoint(x: p.x - vertex.x, y: p.y - vertex.y)
        guard cross != 0 else {
            // Straight on adds nothing, and doubling back adds only a round join's half circle past the turn.
            return join == .round && d1.x * d2.x + d1.y * d2.y < 0 && q.x * d1.x + q.y * d1.y >= 0 && hypot(q.x, q.y) <= half
        }
        // The normals on the outside of the turn.
        let sign: CGFloat = cross > 0 ? 1 : -1
        let n1 = CGPoint(x: d1.y * sign, y: -d1.x * sign), n2 = CGPoint(x: d2.y * sign, y: -d2.x * sign)
        let a = CGPoint(x: vertex.x + n1.x * half, y: vertex.y + n1.y * half)
        let b = CGPoint(x: vertex.x + n2.x * half, y: vertex.y + n2.y * half)
        if join == .round {
            // The slice of a circle between the two normals.
            return hypot(q.x, q.y) <= half && (n1.x * q.y - n1.y * q.x) * sign >= 0 && (q.x * n2.y - q.y * n2.x) * sign >= 0
        }
        let dot = n1.x * n2.x + n1.y * n2.y
        // The miter's length over the line width is 1 / sin of half the angle between the segments.
        if join == .miter, dot > -1, sqrt(2 / (1 + dot)) <= miterLimit {
            let tip = CGPoint(x: vertex.x + (n1.x + n2.x) * half / (1 + dot), y: vertex.y + (n1.y + n2.y) * half / (1 + dot))
            return inConvexPolygon(p, [vertex, a, tip, b])
        }
        return inConvexPolygon(p, [vertex, a, b])
    }

    /// Whether `p` is inside or on the convex polygon with `corners` in order, either way round.
    private static func inConvexPolygon(_ p: CGPoint, _ corners: [CGPoint]) -> Bool {
        var sign: CGFloat = 0
        for (index, a) in corners.enumerated() {
            let b = corners[(index + 1) % corners.count]
            let side = (b.x - a.x) * (p.y - a.y) - (p.x - a.x) * (b.y - a.y)
            if side != 0 {
                if sign != 0, (side > 0) != (sign > 0) {
                    return false
                }
                sign = side
            }
        }
        return true
    }

    // MARK: - Cubics

    private static func cubicPoint(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p3: CGPoint, at t: CGFloat) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return CGPoint(x: a * p0.x + b * c1.x + c * c2.x + d * p3.x, y: a * p0.y + b * c1.y + c * c2.y + d * p3.y)
    }

    /// The times strictly between 0 and 1 where a cubic with these coordinates on one axis turns back.
    private static func extremes(_ p0: CGFloat, _ c1: CGFloat, _ c2: CGFloat, _ p3: CGFloat) -> [CGFloat] {
        // The derivative over 3 is a t² + b t + c.
        let a = -p0 + 3 * c1 - 3 * c2 + p3, b = 2 * (p0 - 2 * c1 + c2), c = c1 - p0
        var roots: [CGFloat] = []
        if abs(a) < 1e-12 {
            if abs(b) > 1e-12 {
                roots = [-c / b]
            }
        } else {
            let discriminant = b * b - 4 * a * c
            if discriminant >= 0 {
                let root = sqrt(discriminant)
                roots = [(-b + root) / (2 * a), (-b - root) / (2 * a)]
            }
        }
        return roots.filter { $0 > 0 && $0 < 1 }
    }
}
