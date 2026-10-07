import CoreGraphics
import CoreText
import Foundation

public struct RGBA: Equatable, Hashable, Sendable, Codable {
    public var r, g, b, a: CGFloat

    public init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    public var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }

    public static let presets: [RGBA] = [
        RGBA(1, 0.23, 0.19), RGBA(1, 0.58, 0), RGBA(1, 0.8, 0),
        RGBA(0.2, 0.78, 0.35), RGBA(0, 0.48, 1), RGBA(0, 0, 0),
    ]

    /// A sticky note's paper: the colour mixed most of the way to white.
    public var noteFill: RGBA {
        RGBA(r + (1 - r) * 0.6, g + (1 - g) * 0.6, b + (1 - b) * 0.6, a)
    }

    /// WCAG relative luminance of the sRGB colour.
    public var relativeLuminance: CGFloat {
        func linear(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
    }

    /// Near-black or white, whichever reads better on this colour.
    public var contrastingInk: RGBA {
        let ink = RGBA(0.07, 0.07, 0.10), white = RGBA(1, 1, 1)
        let l = relativeLuminance
        return (l + 0.05) / (ink.relativeLuminance + 0.05) >= (white.relativeLuminance + 0.05) / (l + 0.05) ? ink : white
    }
}

/// All geometry is in image pixels with a top-left origin.
public struct Annotation: Identifiable, Equatable, Sendable, Codable {
    public let id: UUID
    public var kind: Kind
    public var color: RGBA
    /// The inside of a shape; `nil` leaves it unfilled.
    public var fill: RGBA?
    public var lineWidth: CGFloat
    /// How far an arrow's or line's curve passes from the middle of its chord; `nil` leaves it straight.
    public var bend: CGVector?
    /// How a text annotation's or note's lines line up. Stored only when it isn't left, so annotations saved before it still decode.
    public var alignment: TextAlign {
        get { textAlign ?? .left }
        set { textAlign = newValue == .left ? nil : newValue }
    }
    private var textAlign: TextAlign?
    /// A rounded rectangle's or rounded spotlight's corner radius; `nil` keeps the look from before it could be set.
    public var cornerRadius: CGFloat?

    public enum Kind: Equatable, Sendable, Codable {
        case arrow(from: CGPoint, to: CGPoint)
        case line(from: CGPoint, to: CGPoint)
        case shape(BoxShape, rect: CGRect)
        /// A yellow box, from before the highlighter drew strokes. Kept so older projects still open.
        case highlight(CGRect)
        /// `amount` is the block size, as a fraction of the image's longer side; `nil` sizes it from the rect, as before the amount existed.
        case pixelate(CGRect, amount: CGFloat? = nil)
        /// A Gaussian blur, strong enough that the text under it can't be read back. `amount` is its radius,
        /// as a fraction of the image's longer side; `nil` sizes it from the rect, as before the amount existed.
        case blur(CGRect, amount: CGFloat? = nil)
        /// Dims or blurs the image outside its shape. Every spotlight shares one dim, so together they light up several areas.
        case spotlight(CGRect, style: SpotlightStyle)
        case text(String, origin: CGPoint, fontSize: CGFloat)
        case counter(Int, center: CGPoint)
        /// A sticky note. `rect` sets the wrap width; the note grows taller than it to fit the text.
        case note(String, rect: CGRect)
        /// A pen stroke through the points, drawn smoothed with round caps.
        case freehand([CGPoint])
        /// A highlighter stroke through the points: smoothed like a pen's, but wide, flat-ended and multiplied into what's under it.
        case marker([CGPoint])
        /// Another image placed on the canvas, stretched to `rect`. Its colour and width are unused.
        case image(AnnotationImage, rect: CGRect)

        /// A blur or pixelate, as `redaction` says.
        public static func redaction(_ redaction: Redaction, rect: CGRect, amount: CGFloat?) -> Kind {
            redaction == .blur ? .blur(rect, amount: amount) : .pixelate(rect, amount: amount)
        }
    }

    public init(id: UUID = UUID(), kind: Kind, color: RGBA, fill: RGBA? = nil, lineWidth: CGFloat) {
        self.id = id
        self.kind = kind
        self.color = color
        self.fill = fill
        self.lineWidth = lineWidth
    }

    /// The radius a new rounded rectangle's corners start with, in points, so resizing it doesn't change them.
    public static let defaultCornerRadius: CGFloat = 12

    /// True for the kinds that can be rounded rectangles: shapes and spotlights.
    public var canRound: Bool {
        switch kind {
        case .shape, .spotlight: true
        default: false
        }
    }

    /// The box of a rounded rectangle or rounded spotlight and the radius its corners are drawn with; `nil` for anything else.
    public var roundedBox: (rect: CGRect, radius: CGFloat)? {
        let rect: CGRect
        switch kind {
        case let .shape(.rounded, box): rect = box
        case let .spotlight(box, style) where style.shape == .rounded: rect = box
        default: return nil
        }
        return (rect, BoxShape.cornerRadius(cornerRadius, in: rect))
    }

    public var supportsFill: Bool {
        switch kind {
        case .shape: true
        default: false
        }
    }

    /// True for the kinds whose width sets the size of their text.
    public var sizesText: Bool {
        switch kind {
        case .text, .note, .counter: true
        default: false
        }
    }

    /// True for the kinds whose lines can be aligned.
    public var alignsText: Bool {
        switch kind {
        case .text, .note: true
        default: false
        }
    }

    /// How a pixelate or blur hides what's under it; `nil` for anything else.
    public var redaction: Redaction? {
        switch kind {
        case .blur: .blur
        case .pixelate: .pixelate
        default: nil
        }
    }

    /// How strongly a pixelate or blur hides what's under it, as a fraction of `imageLength`, the longer side of the image
    /// it's drawn on; `nil` for anything else. One made before the amount existed gets the amount nearest the size it was
    /// drawn at then, which was set by its rect.
    public func redactionAmount(imageLength: CGFloat) -> CGFloat? {
        switch kind {
        case let .pixelate(rect, amount): amount ?? Redaction.clamped(max(8, rect.width / 20) / imageLength)
        case let .blur(rect, amount): amount ?? Redaction.clamped(max(12, min(rect.width, rect.height) / 4) / imageLength)
        default: nil
        }
    }

    /// Turns a pixelate into a blur or back, keeping its amount; other kinds are left alone.
    public mutating func setRedaction(_ redaction: Redaction) {
        switch kind {
        case let .blur(rect, amount), let .pixelate(rect, amount): kind = .redaction(redaction, rect: rect, amount: amount)
        default: break
        }
    }

    /// Sets how strongly a pixelate or blur hides what's under it, kept within `Redaction.amounts`; other kinds are left alone.
    public mutating func setRedactionAmount(_ amount: CGFloat) {
        let clamped = Redaction.clamped(amount)
        switch kind {
        case let .blur(rect, _): kind = .blur(rect, amount: clamped)
        case let .pixelate(rect, _): kind = .pixelate(rect, amount: clamped)
        default: break
        }
    }

    /// True for the kinds drawn in their colour and sized by their width.
    public var isStyled: Bool {
        switch kind {
        case .arrow, .line, .shape, .text, .counter, .note, .freehand, .marker: true
        case .highlight, .pixelate, .blur, .spotlight, .image: false
        }
    }

    public var counterRadius: CGFloat { lineWidth * 3 + 10 }
    public var noteFontSize: CGFloat { lineWidth * 3 + 8 }
    /// About one line of body text tall at the middle width.
    public var markerWidth: CGFloat { lineWidth * 4.5 }

    /// The laid-out note, or `nil` if this isn't one.
    public var noteLayout: NoteLayout? {
        guard case let .note(string, rect) = kind else {
            return nil
        }
        return NoteLayout(string: string, rect: rect, fontSize: noteFontSize, color: color)
    }

    /// The quadratic curve an arrow or line follows: its ends and the control point that gives it its bend.
    /// `nil` for anything but a bent arrow or line.
    public var curve: (from: CGPoint, to: CGPoint, control: CGPoint)? {
        guard let bend else {
            return nil
        }
        switch kind {
        case let .arrow(from, to), let .line(from, to):
            return (from, to, CGPoint(x: (from.x + to.x) / 2 + 2 * bend.dx, y: (from.y + to.y) / 2 + 2 * bend.dy))
        default:
            return nil
        }
    }

    public var bounds: CGRect {
        if let curve {
            let path = CGMutablePath()
            path.move(to: curve.from)
            path.addQuadCurve(to: curve.to, control: curve.control)
            return path.boundingBoxOfPath
        }
        switch kind {
        case let .arrow(from, to), let .line(from, to):
            return CGRect(x: min(from.x, to.x), y: min(from.y, to.y), width: abs(to.x - from.x), height: abs(to.y - from.y))
        case let .shape(_, rect), let .highlight(rect), let .pixelate(rect, _), let .blur(rect, _), let .spotlight(rect, _), let .image(_, rect):
            return rect
        case let .text(string, origin, fontSize):
            return CGRect(origin: origin, size: TextLayout(string: string, fontSize: fontSize, color: color).size)
        case let .counter(_, center):
            return CGRect(x: center.x - counterRadius, y: center.y - counterRadius, width: counterRadius * 2, height: counterRadius * 2)
        case .note:
            return noteLayout?.frame ?? .null
        case let .freehand(points), let .marker(points):
            return Freehand.bounds(of: points)
        }
    }

    /// `bounds` plus the stroke and arrowhead that the renderer paints past it.
    public var paintedBounds: CGRect {
        switch kind {
        case .arrow:
            let head = max(12, lineWidth * 4) * 0.45
            let outset = max(head, lineWidth / 2)
            return bounds.insetBy(dx: -outset, dy: -outset)
        case .line, .shape:
            return bounds.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
        case .highlight, .pixelate, .blur, .spotlight, .text, .counter, .image:
            return bounds
        case .note:
            guard let layout = noteLayout else {
                return bounds
            }
            let shadow = layout.frame.offsetBy(dx: 0, dy: layout.shadowOffset).insetBy(dx: -layout.shadowBlur, dy: -layout.shadowBlur)
            return layout.frame.union(shadow)
        case let .freehand(points):
            // The smoothed curve can swing a little past the points it runs through.
            return bounds.union(Freehand.path(through: points).boundingBoxOfPath).insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
        case let .marker(points):
            return bounds.union(Freehand.path(through: points).boundingBoxOfPath).insetBy(dx: -markerWidth / 2, dy: -markerWidth / 2)
        }
    }

    public func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        let slop = tolerance + lineWidth / 2
        switch kind {
        case .arrow where curve != nil, .line where curve != nil:
            let points = Self.flattened(curve!)
            return zip(points, points.dropFirst()).contains { Self.distance(from: point, toSegment: $0, $1) <= slop }
        case let .arrow(from, to), let .line(from, to):
            return Self.distance(from: point, toSegment: from, to) <= slop
        case let .shape(shape, rect):
            let path = shape.path(in: rect, cornerRadius: cornerRadius)
            let outline = path.copy(strokingWithWidth: slop * 2, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
            return outline.contains(point) || (fill != nil && path.contains(point))
        case .highlight, .pixelate, .blur, .spotlight, .text, .note, .image:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case let .counter(_, center):
            return hypot(point.x - center.x, point.y - center.y) <= counterRadius + tolerance
        case let .freehand(points):
            return Freehand.path(through: points).copy(strokingWithWidth: slop * 2, lineCap: .round, lineJoin: .round, miterLimit: 10).contains(point)
        case let .marker(points):
            return Freehand.path(through: points).copy(strokingWithWidth: tolerance * 2 + markerWidth, lineCap: .butt, lineJoin: .round, miterLimit: 10).contains(point)
        }
    }

    public mutating func offset(by delta: CGVector) {
        func move(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + delta.dx, y: p.y + delta.dy) }
        switch kind {
        case let .arrow(from, to): kind = .arrow(from: move(from), to: move(to))
        case let .line(from, to): kind = .line(from: move(from), to: move(to))
        case let .shape(shape, rect): kind = .shape(shape, rect: rect.offsetBy(dx: delta.dx, dy: delta.dy))
        case let .highlight(rect): kind = .highlight(rect.offsetBy(dx: delta.dx, dy: delta.dy))
        case let .pixelate(rect, amount): kind = .pixelate(rect.offsetBy(dx: delta.dx, dy: delta.dy), amount: amount)
        case let .blur(rect, amount): kind = .blur(rect.offsetBy(dx: delta.dx, dy: delta.dy), amount: amount)
        case let .spotlight(rect, style): kind = .spotlight(rect.offsetBy(dx: delta.dx, dy: delta.dy), style: style)
        case let .text(string, origin, size): kind = .text(string, origin: move(origin), fontSize: size)
        case let .counter(number, center): kind = .counter(number, center: move(center))
        case let .note(string, rect): kind = .note(string, rect: rect.offsetBy(dx: delta.dx, dy: delta.dy))
        case let .freehand(points): kind = .freehand(points.map(move))
        case let .marker(points): kind = .marker(points.map(move))
        case let .image(image, rect): kind = .image(image, rect: rect.offsetBy(dx: delta.dx, dy: delta.dy))
        }
    }

    /// Sets a spotlight's effect and strength, keeping its shape and edge; other kinds are left alone.
    public mutating func setSpotlightLook(effect: SpotlightStyle.Effect, strength: Double) {
        restyleSpotlight {
            $0.effect = effect
            $0.strength = strength
        }
    }

    /// Changes a spotlight's style; other kinds are left alone.
    public mutating func restyleSpotlight(_ change: (inout SpotlightStyle) -> Void) {
        if case let .spotlight(rect, style) = kind {
            var restyled = style
            change(&restyled)
            kind = .spotlight(rect, style: restyled)
        }
    }

    /// The text of a text annotation or note; `nil` for other kinds.
    public var text: String? {
        switch kind {
        case let .text(string, _, _), let .note(string, _): string
        default: nil
        }
    }

    /// Replaces the text of a text annotation or note; other kinds are left alone.
    public mutating func setText(_ string: String) {
        switch kind {
        case let .text(_, origin, fontSize): kind = .text(string, origin: origin, fontSize: fontSize)
        case let .note(_, rect): kind = .note(string, rect: rect)
        default: break
        }
    }

    /// Sets the stroke width. Text scales its font with it; every other size already derives from it.
    public mutating func setLineWidth(_ width: CGFloat) {
        if case let .text(string, origin, fontSize) = kind, lineWidth > 0 {
            kind = .text(string, origin: origin, fontSize: fontSize * width / lineWidth)
        }
        lineWidth = width
    }

    /// The resize handles and where they sit: a line's two ends, or the corners and edge midpoints of a box
    /// (a pen stroke's is its bounds). An image has only the corners, since it keeps its shape.
    /// Text and counters have none.
    public var handles: [(handle: AnnotationHandle, point: CGPoint)] {
        switch kind {
        case let .arrow(from, to), let .line(from, to):
            let middle = curve.map { Self.curvePoint($0, at: 0.5) } ?? CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
            return [(.start, from), (.end, to), (.mid, middle)]
        case .shape, .highlight, .pixelate, .blur, .spotlight, .note, .freehand, .marker:
            let frame = bounds
            return AnnotationHandle.box.map { ($0, $0.point(in: frame)) }
        case let .image(_, rect):
            return AnnotationHandle.corners.map { ($0, $0.point(in: rect)) }
        case .text, .counter:
            return []
        }
    }

    /// A rounded rectangle's corner-radius handles, one inside each corner on its diagonal. They sit `2 * tolerance` in
    /// from the corner, clear of its resize handle, and move further in as the radius grows. A box too small to keep
    /// them clear of the resize handles has none.
    public func radiusHandles(tolerance: CGFloat) -> [(handle: AnnotationHandle, point: CGPoint)] {
        guard let (rect, radius) = roundedBox, min(rect.width, rect.height) >= tolerance * 10 else {
            return []
        }
        let inset = Self.radiusHandleInset(radius: radius, tolerance: tolerance)
        return AnnotationHandle.corners.map { corner in
            let point = corner.point(in: rect)
            return (.radius(corner), CGPoint(x: point.x - CGFloat(corner.dx) * inset, y: point.y - CGFloat(corner.dy) * inset))
        }
    }

    /// How far a radius handle sits in from its corner on each axis. Half the radius keeps the four apart even on a circle.
    private static func radiusHandleInset(radius: CGFloat, tolerance: CGFloat) -> CGFloat {
        tolerance * 2 + radius / 2
    }

    /// The handle nearest `point`, if one is within `tolerance` of it on both axes and nearer than the
    /// shape's centre, so a shape smaller than the handles can still be grabbed by its middle and moved.
    /// A line's or arrow's middle handle sits at its centre, so it's offered only on one long enough to move by its stroke.
    public func handle(at point: CGPoint, tolerance: CGFloat) -> AnnotationHandle? {
        func distance(_ p: CGPoint) -> CGFloat { hypot(point.x - p.x, point.y - p.y) }
        let centre = distance(CGPoint(x: bounds.midX, y: bounds.midY))
        let bendable = hypot(bounds.width, bounds.height) > tolerance * 4
        return (handles + radiusHandles(tolerance: tolerance))
            .filter { abs(point.x - $0.point.x) <= tolerance && abs(point.y - $0.point.y) <= tolerance && ($0.handle == .mid ? bendable : distance($0.point) < centre) }
            .min { distance($0.point) < distance($1.point) }?
            .handle
    }

    /// Drags `handle` to `point`. Call it on the annotation as it was when the drag began: a box dragged
    /// past its opposite side flips, so its handles swap sides. A pen stroke scales its points within its
    /// bounds, and mirrors when flipped. An image keeps its aspect ratio and never flips.
    /// A radius handle sets one radius for all four corners from how far along its diagonal `point` is; pass the
    /// `tolerance` its handles were placed with. A handle the kind doesn't have changes nothing.
    public mutating func resize(_ handle: AnnotationHandle, to point: CGPoint, tolerance: CGFloat = 0) {
        if case let .radius(corner) = handle {
            if let (rect, _) = roundedBox {
                let cornerPoint = corner.point(in: rect)
                let inset = ((cornerPoint.x - point.x) * CGFloat(corner.dx) + (cornerPoint.y - point.y) * CGFloat(corner.dy)) / 2
                cornerRadius = BoxShape.cornerRadius(max(0, (inset - tolerance * 2) * 2), in: rect)
            }
            return
        }
        /// `rect`'s corners with the handle's sides moved to `point`; past the opposite side, `max` is less than `min`.
        func corners(_ rect: CGRect) -> (min: CGPoint, max: CGPoint) {
            var minX = rect.minX, minY = rect.minY, maxX = rect.maxX, maxY = rect.maxY
            switch handle.dx {
            case -1: minX = point.x
            case 1: maxX = point.x
            default: break
            }
            switch handle.dy {
            case -1: minY = point.y
            case 1: maxY = point.y
            default: break
            }
            return (CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: maxY))
        }
        func box(_ rect: CGRect) -> CGRect {
            let (min, max) = corners(rect)
            return Geometry.normalized(from: min, to: max)
        }
        switch (kind, handle) {
        case let (.arrow(_, to), .start): kind = .arrow(from: point, to: to)
        case let (.arrow(from, _), .end): kind = .arrow(from: from, to: point)
        case let (.line(_, to), .start): kind = .line(from: point, to: to)
        case let (.line(from, _), .end): kind = .line(from: from, to: point)
        case (.arrow(let from, let to), .mid), (.line(let from, let to), .mid):
            let drag = CGVector(dx: point.x - (from.x + to.x) / 2, dy: point.y - (from.y + to.y) / 2)
            bend = hypot(drag.dx, drag.dy) < Self.minBend ? nil : drag
        case (.arrow, _), (.line, _), (_, .start), (_, .end), (.text, _), (.counter, _): break
        case let (.shape(shape, rect), _): kind = .shape(shape, rect: box(rect))
        case let (.highlight(rect), _): kind = .highlight(box(rect))
        case let (.pixelate(rect, amount), _): kind = .pixelate(box(rect), amount: amount)
        case let (.blur(rect, amount), _): kind = .blur(box(rect), amount: amount)
        case let (.spotlight(rect, style), _): kind = .spotlight(box(rect), style: style)
        case let (.note(string, rect), _): resizeNote(string, rect: rect, handle: handle, to: point)
        case let (.freehand(points), _):
            let rect = bounds
            let (min, max) = corners(rect)
            kind = .freehand(Freehand.scaled(points, from: rect, min: min, max: max))
        case let (.marker(points), _):
            let rect = bounds
            let (min, max) = corners(rect)
            kind = .marker(Freehand.scaled(points, from: rect, min: min, max: max))
        case let (.image(image, rect), _):
            kind = .image(image, rect: Self.resizedImageRect(rect, handle: handle, to: point))
        }
    }

    /// The opposite corner stays put and the image grows or shrinks by whichever axis was dragged further,
    /// down to `AnnotationImage.minSide` on its shorter side. An edge handle changes nothing.
    private static func resizedImageRect(_ rect: CGRect, handle: AnnotationHandle, to point: CGPoint) -> CGRect {
        guard handle.dx != 0, handle.dy != 0, rect.width > 0, rect.height > 0 else {
            return rect
        }
        let anchor = handle.opposite.point(in: rect)
        let factor = max(
            (point.x - anchor.x) * CGFloat(handle.dx) / rect.width,
            (point.y - anchor.y) * CGFloat(handle.dy) / rect.height,
            AnnotationImage.minSide / min(rect.width, rect.height)
        )
        let width = rect.width * factor, height = rect.height * factor
        return CGRect(x: handle.dx < 0 ? anchor.x - width : anchor.x, y: handle.dy < 0 ? anchor.y - height : anchor.y, width: width, height: height)
    }

    /// The opposite side stays put, and the note never flips, gets narrower than its minimum or shorter than its text.
    private mutating func resizeNote(_ string: String, rect: CGRect, handle: AnnotationHandle, to point: CGPoint) {
        guard let layout = noteLayout else {
            return
        }
        let frame = layout.frame
        let minWidth = NoteLayout.minWidth(fontSize: layout.fontSize)
        let minX: CGFloat, width: CGFloat
        switch handle.dx {
        case -1:
            minX = min(point.x, frame.maxX - minWidth)
            width = frame.maxX - minX
        case 1:
            minX = frame.minX
            width = max(point.x - frame.minX, minWidth)
        default:
            minX = frame.minX
            width = frame.width
        }
        let resized: CGRect
        switch handle.dy {
        case -1:
            let textHeight = NoteLayout(string: string, rect: CGRect(x: minX, y: 0, width: width, height: 0), fontSize: layout.fontSize, color: color).frame.height
            let minY = min(point.y, frame.maxY - textHeight)
            resized = CGRect(x: minX, y: minY, width: width, height: frame.maxY - minY)
        case 1:
            resized = CGRect(x: minX, y: frame.minY, width: width, height: max(0, point.y - frame.minY))
        default:
            // The stored height, not the frame's, so the note still grows and shrinks with its text.
            resized = CGRect(x: minX, y: rect.minY, width: width, height: rect.height)
        }
        kind = .note(string, rect: resized)
    }

    /// A drag this close to the chord straightens the arrow or line.
    static let minBend: CGFloat = 3

    static func curvePoint(_ curve: (from: CGPoint, to: CGPoint, control: CGPoint), at t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * curve.from.x + 2 * u * t * curve.control.x + t * t * curve.to.x,
            y: u * u * curve.from.y + 2 * u * t * curve.control.y + t * t * curve.to.y
        )
    }

    private static func flattened(_ curve: (from: CGPoint, to: CGPoint, control: CGPoint)) -> [CGPoint] {
        (0...24).map { curvePoint(curve, at: CGFloat($0) / 24) }
    }

    static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else {
            return hypot(p.x - a.x, p.y - a.y)
        }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}

extension Array where Element == Annotation {
    /// Index of the topmost (last drawn) annotation under `point`.
    public func topmostIndex(at point: CGPoint, tolerance: CGFloat) -> Int? {
        indices.reversed().first { self[$0].hitTest(point, tolerance: tolerance) }
    }

    /// The lowest spotlight's style, whose effect and strength they all share. `nil` when there are none.
    public var spotlightStyle: SpotlightStyle? {
        lazy.compactMap { annotation -> SpotlightStyle? in
            if case let .spotlight(_, style) = annotation.kind { style } else { nil }
        }.first
    }

    public var nextCounterNumber: Int {
        compactMap { annotation -> Int? in
            if case let .counter(number, _) = annotation.kind {
                return number
            }
            return nil
        }.max().map { $0 + 1 } ?? 1
    }
}

public struct EditorDocument: @unchecked Sendable {
    public var base: CGImage
    public var annotations: [Annotation]
    /// The exported region in image pixels. It can be smaller than the image (a crop) or reach past it (padding).
    public var canvasRect: CGRect
    /// Fills the canvas behind the image; `nil` is transparent.
    public var background: RGBA?

    public init(base: CGImage, annotations: [Annotation] = [], canvasRect: CGRect? = nil, background: RGBA? = nil) {
        self.base = base
        self.annotations = annotations
        self.canvasRect = canvasRect ?? CGRect(x: 0, y: 0, width: base.width, height: base.height)
        self.background = background
    }

    public var fullRect: CGRect { CGRect(x: 0, y: 0, width: base.width, height: base.height) }
    public var exportSize: CGSize { canvasRect.size }
    /// Whether the canvas reaches past the image on any side.
    public var hasPadding: Bool { !fullRect.contains(canvasRect) }

    /// JPEG has no alpha, so transparent padding would export as black.
    public static func defaultBackground(for format: ImageFormat) -> RGBA? {
        format == .jpeg ? RGBA(1, 1, 1) : nil
    }

    /// Crops to `rect`, which may lie in the padding, within the current canvas.
    public mutating func crop(to rect: CGRect) {
        canvasRect = rect.integral.intersection(canvasRect)
    }

    /// Grows the canvas to hold `annotation` plus `margin` on each side its shape reaches past.
    /// Only edges at or beyond the image grow; a crop edge inside the image stays, so cropped pixels never come back.
    /// A spotlight only dims the image, so it never grows the canvas.
    public mutating func grow(toFit annotation: Annotation, margin: CGFloat) {
        if case .spotlight = annotation.kind {
            return
        }
        let shape = annotation.bounds
        let painted = annotation.paintedBounds.insetBy(dx: -margin, dy: -margin)
        let image = fullRect
        var minX = canvasRect.minX, minY = canvasRect.minY, maxX = canvasRect.maxX, maxY = canvasRect.maxY
        if shape.minX < minX, minX <= image.minX { minX = painted.minX }
        if shape.minY < minY, minY <= image.minY { minY = painted.minY }
        if shape.maxX > maxX, maxX >= image.maxX { maxX = painted.maxX }
        if shape.maxY > maxY, maxY >= image.maxY { maxY = painted.maxY }
        canvasRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).integral
    }

    /// Pulls padding back in to what the annotations still need, so moving or removing one retracts the canvas.
    /// Only edges at or beyond the image shrink, and never past the image; a crop edge inside the image stays.
    public mutating func shrinkPadding(margin: CGFloat) {
        let image = fullRect
        let painted = annotations.filter { annotation in
            if case .spotlight = annotation.kind { return false }
            return true
        }.map { ($0.bounds, $0.paintedBounds.insetBy(dx: -margin, dy: -margin)) }
        func edge(_ current: CGFloat, image imageEdge: CGFloat, reaches: ((CGRect) -> Bool), painted paintedEdge: ((CGRect) -> CGFloat), outward: CGFloat) -> CGFloat {
            guard (current - imageEdge) * outward >= 0 else {
                return current
            }
            let needed = painted.filter { reaches($0.0) }.map { paintedEdge($0.1) }.reduce(imageEdge) { outward > 0 ? max($0, $1) : min($0, $1) }
            return outward > 0 ? min(current, needed) : max(current, needed)
        }
        let minX = edge(canvasRect.minX, image: image.minX, reaches: { $0.minX < image.minX }, painted: { $0.minX }, outward: -1)
        let minY = edge(canvasRect.minY, image: image.minY, reaches: { $0.minY < image.minY }, painted: { $0.minY }, outward: -1)
        let maxX = edge(canvasRect.maxX, image: image.maxX, reaches: { $0.maxX > image.maxX }, painted: { $0.maxX }, outward: 1)
        let maxY = edge(canvasRect.maxY, image: image.maxY, reaches: { $0.maxY > image.maxY }, painted: { $0.maxY }, outward: 1)
        canvasRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).integral
    }

    /// Sizes the canvas to the image and every annotation but spotlights, with `margin` around the annotations.
    public mutating func fitToContent(margin: CGFloat) {
        canvasRect = annotations.reduce(fullRect) { canvas, annotation in
            if case .spotlight = annotation.kind {
                return canvas
            }
            return canvas.union(annotation.paintedBounds.insetBy(dx: -margin, dy: -margin))
        }.integral
    }

    /// The part of the image and the images placed on it that the spotlights dim: all of it outside
    /// every hard-edged spotlight, never the rest of the padding. `softSpotlights` fade it further.
    /// `nil` when there are no spotlights. One with no area, such as a straight drag, dims nothing.
    public var spotlightDimPath: CGPath? {
        var lit: CGPath?
        var hasSpotlight = false
        let images = CGMutablePath()
        for annotation in annotations {
            switch annotation.kind {
            case let .spotlight(rect, style) where !rect.isEmpty:
                hasSpotlight = true
                guard style.softEdge == 0 else {
                    continue
                }
                let shape = style.shape.path(in: rect, cornerRadius: annotation.cornerRadius)
                lit = lit?.union(shape) ?? shape
            case let .image(_, rect): images.addRect(rect)
            default: break
            }
        }
        guard hasSpotlight else {
            return nil
        }
        let dimmable = images.isEmpty ? CGPath(rect: fullRect, transform: nil) : images.union(CGPath(rect: fullRect, transform: nil))
        return lit.map { dimmable.subtracting($0) } ?? dimmable
    }

    /// The spotlights with a soft edge, which fade the dim rather than cut it out of `spotlightDimPath`.
    public var softSpotlights: [(rect: CGRect, style: SpotlightStyle, cornerRadius: CGFloat?)] {
        annotations.compactMap { annotation in
            guard case let .spotlight(rect, style) = annotation.kind, !rect.isEmpty, style.softEdge > 0 else {
                return nil
            }
            return (rect, style, annotation.cornerRadius)
        }
    }

    /// The effect and strength every spotlight's shared dim is drawn with: the lowest spotlight's. `nil` when there are none.
    public var spotlightStyle: SpotlightStyle? { annotations.spotlightStyle }

    /// Gives every spotlight `effect` and `strength`, since they share one dim. Their shapes stay.
    public mutating func setSpotlights(effect: SpotlightStyle.Effect, strength: Double) {
        for index in annotations.indices {
            annotations[index].setSpotlightLook(effect: effect, strength: strength)
        }
    }

    /// Removes the padding; a crop inside the image stays.
    public mutating func trimToImage() {
        let trimmed = canvasRect.intersection(fullRect)
        canvasRect = trimmed.isEmpty ? fullRect : trimmed
    }

    public var snapshot: EditorSnapshot { EditorSnapshot(annotations: annotations, canvasRect: canvasRect, background: background) }

    public mutating func restore(_ snapshot: EditorSnapshot) {
        annotations = snapshot.annotations
        canvasRect = snapshot.canvasRect
        background = snapshot.background
    }
}

public struct EditorSnapshot: Equatable, Sendable {
    public var annotations: [Annotation]
    public var canvasRect: CGRect
    public var background: RGBA?
}

public struct UndoStack<State> {
    private var past: [State] = []
    private var future: [State] = []

    public init() {}

    public var canUndo: Bool { !past.isEmpty }
    public var canRedo: Bool { !future.isEmpty }

    /// Call with the state *before* a change.
    public mutating func record(_ state: State) {
        past.append(state)
        future.removeAll()
    }

    public mutating func undo(from current: State) -> State? {
        guard let previous = past.popLast() else {
            return nil
        }
        future.append(current)
        return previous
    }

    public mutating func redo(from current: State) -> State? {
        guard let next = future.popLast() else {
            return nil
        }
        past.append(current)
        return next
    }
}

public struct TextLayout {
    public let lines: [CTLine]
    public let lineHeight: CGFloat
    public let ascent: CGFloat
    public let size: CGSize

    public init(string: String, fontSize: CGFloat, color: RGBA) {
        let font = CTFontCreateUIFontForLanguage(.system, fontSize, nil) ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let bold = CTFontCreateCopyWithSymbolicTraits(font, fontSize, nil, .traitBold, .traitBold) ?? font
        let attributes = [kCTFontAttributeName: bold, kCTForegroundColorAttributeName: color.cgColor] as CFDictionary
        let parts = string.isEmpty ? [" "] : string.components(separatedBy: "\n")
        lines = parts.map { CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, $0 as CFString, attributes)) }
        ascent = CTFontGetAscent(bold)
        lineHeight = (ascent + CTFontGetDescent(bold) + CTFontGetLeading(bold)).rounded(.up)
        let width = lines.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) }.max() ?? 0
        size = CGSize(width: width.rounded(.up), height: lineHeight * CGFloat(lines.count))
    }
}

/// A point on a selected annotation that drags to resize it.
public enum AnnotationHandle: Hashable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    /// A line or arrow's ends.
    case start, end
    /// A line or arrow's middle, which drags to bend it.
    case mid
    /// A rounded rectangle's corner radius, from the handle inside `corner`.
    indirect case radius(AnnotationHandle)

    /// The handles on a box, corners first.
    public static let box: [AnnotationHandle] = [.topLeft, .topRight, .bottomRight, .bottomLeft, .top, .right, .bottom, .left]
    public static let corners: [AnnotationHandle] = Array(box.prefix(4))

    /// The handle on the other side of a box: the far corner, or the facing edge.
    var opposite: AnnotationHandle {
        switch self {
        case .topLeft: .bottomRight
        case .top: .bottom
        case .topRight: .bottomLeft
        case .right: .left
        case .bottomRight: .topLeft
        case .bottom: .top
        case .bottomLeft: .topRight
        case .left: .right
        case .start: .end
        case .end: .start
        case .mid, .radius: self
        }
    }

    /// The side of a box the handle moves across: -1 the left, 1 the right, 0 neither.
    var dx: Int {
        switch self {
        case .topLeft, .left, .bottomLeft: -1
        case .topRight, .right, .bottomRight: 1
        default: 0
        }
    }

    /// The side of a box the handle moves up or down: -1 the top, 1 the bottom, 0 neither.
    var dy: Int {
        switch self {
        case .topLeft, .top, .topRight: -1
        case .bottomLeft, .bottom, .bottomRight: 1
        default: 0
        }
    }

    /// Where a box handle sits on `rect`.
    public func point(in rect: CGRect) -> CGPoint {
        CGPoint(x: [rect.minX, rect.midX, rect.maxX][dx + 1], y: [rect.minY, rect.midY, rect.maxY][dy + 1])
    }
}

/// A sticky note's text wrapped to its width, with the paper around it. Image pixels, top-left origin.
public struct NoteLayout {
    public let fontSize: CGFloat
    public let padding: CGFloat
    public let cornerRadius: CGFloat
    public let shadowOffset: CGFloat
    public let shadowBlur: CGFloat
    public let fill: RGBA
    public let ink: RGBA
    public let lines: [CTLine]
    public let lineHeight: CGFloat
    public let ascent: CGFloat
    /// The paper: the rect's origin and width (at least `minWidth`), and at least tall enough for the text.
    public let frame: CGRect

    public var textRect: CGRect { frame.insetBy(dx: padding, dy: padding) }

    public static func padding(fontSize: CGFloat) -> CGFloat { fontSize * 0.6 }
    public static func minWidth(fontSize: CGFloat) -> CGFloat { fontSize * 3 + padding(fontSize: fontSize) * 2 }
    public static func defaultWidth(fontSize: CGFloat) -> CGFloat { fontSize * 10 }

    /// The note rect for a press at `start` released at `end`: a click places a default-width note, a drag sets its size.
    public static func placementRect(from start: CGPoint, to end: CGPoint, fontSize: CGFloat) -> CGRect {
        guard abs(end.x - start.x) >= 4 || abs(end.y - start.y) >= 4 else {
            return CGRect(origin: start, size: CGSize(width: defaultWidth(fontSize: fontSize), height: 0))
        }
        let rect = Geometry.normalized(from: start, to: end)
        return CGRect(x: rect.minX, y: rect.minY, width: max(rect.width, minWidth(fontSize: fontSize)), height: rect.height)
    }

    public init(string: String, rect: CGRect, fontSize: CGFloat, color: RGBA) {
        self.fontSize = fontSize
        padding = Self.padding(fontSize: fontSize)
        cornerRadius = fontSize * 0.35
        shadowOffset = fontSize * 0.15
        shadowBlur = fontSize * 0.5
        fill = color.noteFill
        ink = fill.contrastingInk

        let width = max(rect.width, Self.minWidth(fontSize: fontSize))
        let wrapWidth = Double(width - padding * 2)
        let font = CTFontCreateUIFontForLanguage(.system, fontSize, nil) ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attributes = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: ink.cgColor] as CFDictionary
        var lines: [CTLine] = []
        for paragraph in string.components(separatedBy: "\n") {
            let text = CFAttributedStringCreate(nil, paragraph as CFString, attributes)!
            let length = CFAttributedStringGetLength(text)
            guard length > 0 else {
                lines.append(CTLineCreateWithAttributedString(text))
                continue
            }
            let typesetter = CTTypesetterCreateWithAttributedString(text)
            var start = 0
            while start < length {
                var count = CTTypesetterSuggestLineBreak(typesetter, start, wrapWidth)
                var line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
                // A word wider than the note has no word break to use, so break it between characters.
                if CTLineGetTypographicBounds(line, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(line) > wrapWidth {
                    count = max(1, CTTypesetterSuggestClusterBreak(typesetter, start, wrapWidth))
                    line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
                }
                lines.append(line)
                start += max(1, count)
            }
        }
        self.lines = lines
        ascent = CTFontGetAscent(font)
        lineHeight = (ascent + CTFontGetDescent(font) + CTFontGetLeading(font)).rounded(.up)
        let textHeight = lineHeight * CGFloat(lines.count) + padding * 2
        frame = CGRect(x: rect.minX, y: rect.minY, width: width, height: max(rect.height, textHeight))
    }
}
