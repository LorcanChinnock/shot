import CoreGraphics
import Foundation

/// All geometry is in image pixels with a top-left origin.
public struct Annotation: Identifiable, Equatable, Sendable, Codable {
    public private(set) var id: UUID
    public var kind: Kind
    public var color: RGBA
    /// The inside of a shape, or the box behind text, as captions have; `nil` leaves it unfilled.
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
    /// Where a note's text sits in it. Stored only when it isn't top, so annotations saved before it still decode.
    public var verticalAlignment: VerticalTextAlign {
        get { textVerticalAlign ?? .top }
        set { textVerticalAlign = newValue == .top ? nil : newValue }
    }
    private var textVerticalAlign: VerticalTextAlign?
    /// Whether the layers panel hides it. Stored only when set, so annotations saved before it still decode.
    public var isHidden: Bool {
        get { hidden ?? false }
        set { hidden = newValue ? true : nil }
    }
    private var hidden: Bool?
    /// Whether the layers panel locks it against moving, resizing and picking on the canvas.
    public var isLocked: Bool {
        get { locked ?? false }
        set { locked = newValue ? true : nil }
    }
    private var locked: Bool?
    /// What the user renamed it to in the layers panel or the timeline, which `layerName` shows in place of the one it
    /// makes up; `nil` until renamed. Set trimmed and cut to `maxNameLength`, and an empty name clears it. Stored only when
    /// set, so annotations saved before it still decode.
    public var name: String? {
        get { customName }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            customName = trimmed.isEmpty ? nil : String(trimmed.prefix(Self.maxNameLength))
        }
    }
    private var customName: String?
    public static let maxNameLength = 64
    /// The corner radius of a shape, spotlight, placed image or text box; `nil` is square, or for a text box, the default.
    public var cornerRadius: CGFloat? {
        get { kind.isImage ? imageRadius : boxRadius }
        set {
            if kind.isImage { imageRadius = newValue } else { boxRadius = newValue }
        }
    }
    /// A placed image's radius. Older versions also saved a rounded box's radius under this key.
    private var imageRadius: CGFloat?
    /// A shape's or spotlight's radius. It has its own key because older versions saved a radius, 12 by default, on every
    /// shape, rectangles that were square included.
    private var boxRadius: CGFloat?
    /// What a placed image's own crop trims off it; `nil` for a whole image and for anything else. Its rect is the size of
    /// the part left. Stored only when set, so annotations saved before it still decode.
    public var imageCrop: ImageCrop? {
        get { crop }
        set { crop = kind.isImage && newValue?.isEmpty == false ? newValue : nil }
    }
    private var crop: ImageCrop?

    private enum CodingKeys: String, CodingKey {
        case id, kind, color, fill, lineWidth, bend, textAlign, textVerticalAlign, hidden, locked, objectStyle, boxRadius, crop
        case imageRadius = "cornerRadius"
        case customName = "name"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(Kind.self, forKey: .kind)
        color = try container.decode(RGBA.self, forKey: .color)
        fill = try container.decodeIfPresent(RGBA.self, forKey: .fill)
        lineWidth = try container.decode(CGFloat.self, forKey: .lineWidth)
        bend = try container.decodeIfPresent(CGVector.self, forKey: .bend)
        textAlign = try container.decodeIfPresent(TextAlign.self, forKey: .textAlign)
        textVerticalAlign = try container.decodeIfPresent(VerticalTextAlign.self, forKey: .textVerticalAlign)
        hidden = try container.decodeIfPresent(Bool.self, forKey: .hidden)
        locked = try container.decodeIfPresent(Bool.self, forKey: .locked)
        objectStyle = try container.decodeIfPresent(ObjectStyle.self, forKey: .objectStyle)
        boxRadius = try container.decodeIfPresent(CGFloat.self, forKey: .boxRadius)
        imageRadius = try container.decodeIfPresent(CGFloat.self, forKey: .imageRadius)
        name = try container.decodeIfPresent(String.self, forKey: .customName)
        crop = kind.isImage ? try container.decodeIfPresent(ImageCrop.self, forKey: .crop) : nil
        // A rounded rectangle from before every shape could be rounded keeps its radius, or the fifth of its shorter side
        // that it had when it had none.
        if !kind.isImage {
            if boxRadius == nil, let legacy = try? container.decode(LegacyRoundedBox.self, forKey: .kind) {
                boxRadius = imageRadius ?? min(legacy.rect.width, legacy.rect.height) / 5
            }
            imageRadius = nil
        }
    }

    /// The box of a shape or spotlight saved as `rounded`, read from the saved form of `Kind`; fails for any other.
    private struct LegacyRoundedBox: Decodable {
        let rect: CGRect

        private enum Case: String, CodingKey {
            case shape, spotlight
        }
        private enum Fields: String, CodingKey {
            case first = "_0", rect, style
        }
        private struct Style: Decodable {
            let shape: String
        }
        private struct NotRounded: Error {}

        init(from decoder: Decoder) throws {
            let outer = try decoder.container(keyedBy: Case.self)
            if outer.contains(.shape) {
                let fields = try outer.nestedContainer(keyedBy: Fields.self, forKey: .shape)
                guard try fields.decode(String.self, forKey: .first) == "rounded" else { throw NotRounded() }
                rect = try fields.decode(CGRect.self, forKey: .rect)
            } else {
                let fields = try outer.nestedContainer(keyedBy: Fields.self, forKey: .spotlight)
                guard try fields.decode(Style.self, forKey: .style).shape == "rounded" else { throw NotRounded() }
                rect = try fields.decode(CGRect.self, forKey: .first)
            }
        }
    }
    /// The shadow and border of a placed image, mark or text; see `styleKind`. Stored only when set, so annotations saved
    /// before it still decode.
    public var style: ObjectStyle {
        get { objectStyle ?? ObjectStyle() }
        set { objectStyle = newValue.isEmpty ? nil : newValue }
    }
    private var objectStyle: ObjectStyle?

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

        fileprivate var isImage: Bool {
            if case .image = self { true } else { false }
        }
    }

    public init(id: UUID = UUID(), kind: Kind, color: RGBA, fill: RGBA? = nil, lineWidth: CGFloat) {
        self.id = id
        self.kind = kind
        self.color = color
        self.fill = fill
        self.lineWidth = lineWidth
    }

    /// The same annotation with a new id.
    public func withNewID() -> Annotation {
        var copy = self
        copy.id = UUID()
        return copy
    }

    /// The radius an older version's `rounded` rectangle had with none set, which an agent's `rounded` mark takes, in points.
    public static let defaultCornerRadius: CGFloat = 12

    /// The outline and box of a shape or spotlight with corners to round, and the radius they're drawn with; `nil` for
    /// anything else, an ellipse included.
    public var cornerBox: (shape: BoxShape, rect: CGRect, radius: CGFloat)? {
        let shape: BoxShape, rect: CGRect
        switch kind {
        case let .shape(boxShape, box): (shape, rect) = (boxShape, box)
        case let .spotlight(box, style): (shape, rect) = (style.shape, box)
        default: return nil
        }
        return shape.hasCorners ? (shape, rect, shape.clampedRadius(cornerRadius, in: rect)) : nil
    }

    /// True for a shape with corners to round, whose radius a copied style carries.
    public var roundsShape: Bool {
        if case .shape = kind { cornerBox != nil } else { false }
    }

    /// True for what the Style popover and a pasted style can set a corner radius on: a placed image or a shape with corners.
    public var takesCornerRadius: Bool {
        styleKind?.takesCorners == true || roundsShape
    }

    public var supportsFill: Bool {
        switch kind {
        case .shape: true
        case .arrow, .line, .highlight, .pixelate, .blur, .spotlight, .text, .counter, .note, .freehand, .marker, .image: false
        }
    }

    /// True for the kinds whose width sets the size of their text.
    public var sizesText: Bool {
        switch kind {
        case .text, .note, .counter: true
        case .arrow, .line, .shape, .highlight, .pixelate, .blur, .spotlight, .freehand, .marker, .image: false
        }
    }

    /// True for the kinds whose lines can be aligned.
    public var alignsText: Bool {
        switch kind {
        case .text, .note: true
        case .arrow, .line, .shape, .highlight, .pixelate, .blur, .spotlight, .counter, .freehand, .marker, .image: false
        }
    }

    /// How a pixelate or blur hides what's under it; `nil` for anything else.
    public var redaction: Redaction? {
        switch kind {
        case .blur: .blur
        case .pixelate: .pixelate
        case .arrow, .line, .shape, .highlight, .spotlight, .text, .counter, .note, .freehand, .marker, .image: nil
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
    public var takesColorAndWidth: Bool {
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
        return NoteLayout(string: string, rect: rect, fontSize: noteFontSize, color: color, verticalAlignment: verticalAlignment)
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

    /// `bounds` plus the stroke and arrowhead that the renderer paints past it, and the shadow and border of its style.
    public var paintedBounds: CGRect {
        guard styleKind != nil else {
            return plainPaintedBounds()
        }
        return style.paintedRect(around: plainPaintedBounds())
    }

    /// Room around text with a fill, as a share of its font size, on each side and above and below.
    static let textBoxPadding = (horizontal: 0.4, vertical: 0.2)

    /// The box drawn in `fill` behind text that has one, as captions do: the text's frame with room around it, so the
    /// text reads over any picture. `nil` for text without a fill, and for every other kind.
    public var textBox: CGRect? {
        guard case let .text(_, _, fontSize) = kind, fill != nil else {
            return nil
        }
        return bounds.insetBy(dx: -fontSize * Self.textBoxPadding.horizontal, dy: -fontSize * Self.textBoxPadding.vertical)
    }

    /// The text box's corner radius: the annotation's own, or a fifth of the font size.
    public var textBoxCornerRadius: CGFloat {
        guard case let .text(_, _, fontSize) = kind else {
            return 0
        }
        return cornerRadius ?? fontSize * 0.2
    }

    /// `bounds` plus the stroke and arrowhead that the renderer paints past it, without its style.
    private func plainPaintedBounds() -> CGRect {
        let bounds = bounds
        switch kind {
        case .arrow:
            let head = max(12, lineWidth * 4) * 0.45
            let outset = max(head, lineWidth / 2)
            return bounds.insetBy(dx: -outset, dy: -outset)
        case .line, .shape:
            return bounds.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
        case .text:
            return textBox ?? bounds
        case .highlight, .pixelate, .blur, .spotlight, .counter, .image:
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
        case .text:
            return (textBox ?? bounds).insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case .highlight, .pixelate, .blur, .spotlight, .note, .image:
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
        movePositions { CGPoint(x: $0.x + delta.dx, y: $0.y + delta.dy) }
    }

    /// Moves every point, and the origin of every rect, through `move`, which only moves them, never scales.
    public mutating func movePositions(_ move: (CGPoint) -> CGPoint) {
        func moved(_ rect: CGRect) -> CGRect { CGRect(origin: move(rect.origin), size: rect.size) }
        switch kind {
        case let .arrow(from, to): kind = .arrow(from: move(from), to: move(to))
        case let .line(from, to): kind = .line(from: move(from), to: move(to))
        case let .shape(shape, rect): kind = .shape(shape, rect: moved(rect))
        case let .highlight(rect): kind = .highlight(moved(rect))
        case let .pixelate(rect, amount): kind = .pixelate(moved(rect), amount: amount)
        case let .blur(rect, amount): kind = .blur(moved(rect), amount: amount)
        case let .spotlight(rect, style): kind = .spotlight(moved(rect), style: style)
        case let .text(string, origin, size): kind = .text(string, origin: move(origin), fontSize: size)
        case let .counter(number, center): kind = .counter(number, center: move(center))
        case let .note(string, rect): kind = .note(string, rect: moved(rect))
        case let .freehand(points): kind = .freehand(points.map(move))
        case let .marker(points): kind = .marker(points.map(move))
        case let .image(image, rect): kind = .image(image, rect: moved(rect))
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
        case .arrow, .line, .shape, .highlight, .pixelate, .blur, .spotlight, .counter, .freehand, .marker, .image: nil
        }
    }

    /// Replaces the text of a text annotation or note; other kinds are left alone.
    public mutating func setText(_ string: String) {
        switch kind {
        case let .text(_, origin, fontSize): kind = .text(string, origin: origin, fontSize: fontSize)
        case let .note(_, rect): kind = .note(string, rect: rect)
        case .arrow, .line, .shape, .highlight, .pixelate, .blur, .spotlight, .counter, .freehand, .marker, .image: break
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

    /// The corner-radius handles of a shape or spotlight with corners, one inside each corner it rounds, on the line from
    /// the corner to the centre; a star has one in each point. They sit `2 * tolerance` in from the corner, clear of
    /// its resize handle, and move further in as the radius grows. A box too small to keep them clear of the resize
    /// handles has none.
    public func radiusHandles(tolerance: CGFloat) -> [(handle: AnnotationHandle, point: CGPoint)] {
        guard let (shape, rect, radius) = cornerBox, min(rect.width, rect.height) >= tolerance * 10 else {
            return []
        }
        let inset = Self.radiusHandleInset(radius: radius, tolerance: tolerance)
        return shape.vertices(in: rect).rounded.sorted().compactMap { index in
            Self.radiusAxis(of: index, shape: shape, in: rect).map { corner, inward in
                (.radius(index), CGPoint(x: corner.x + inward.dx * inset, y: corner.y + inward.dy * inset))
            }
        }
    }

    /// How far a radius handle sits in from its corner, in steps of its `radiusAxis`. Half the radius keeps the four apart
    /// even on a circle.
    private static func radiusHandleInset(radius: CGFloat, tolerance: CGFloat) -> CGFloat {
        tolerance * 2 + radius / 2
    }

    /// Corner `index` of `shape` in `rect` and the step its radius handle takes along its line, which is as long as
    /// the square root of 2: one point in on each axis for a rectangle, along the line to the centre for anything else.
    /// `nil` when the corner is the centre.
    private static func radiusAxis(of index: Int, shape: BoxShape, in rect: CGRect) -> (corner: CGPoint, inward: CGVector)? {
        let points = shape.vertices(in: rect).points
        guard points.indices.contains(index) else {
            return nil
        }
        let corner = points[index]
        if shape == .rectangle {
            let handle = AnnotationHandle.corners[index]
            return (corner, CGVector(dx: -CGFloat(handle.dx), dy: -CGFloat(handle.dy)))
        }
        let toCentre = CGVector(dx: rect.midX - corner.x, dy: rect.midY - corner.y)
        let length = hypot(toCentre.dx, toCentre.dy)
        let step = 2.0.squareRoot() / length
        return length > 0 ? (corner, CGVector(dx: toCentre.dx * step, dy: toCentre.dy * step)) : nil
    }

    /// The handle nearest `point`, if one is within `tolerance` of it on both axes and nearer than the
    /// shape's centre, so a shape smaller than the handles can still be grabbed by its middle and moved.
    /// A line's or arrow's middle handle sits at its centre, so it's offered only on one long enough to move by its stroke.
    public func handle(at point: CGPoint, tolerance: CGFloat) -> AnnotationHandle? {
        func distance(_ p: CGPoint) -> CGFloat { hypot(point.x - p.x, point.y - p.y) }
        let bounds = bounds
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
    /// A radius handle sets one radius for every corner from how far along its line `point` is; pass the
    /// `tolerance` its handles were placed with. A handle the kind doesn't have changes nothing.
    ///
    /// `constrain` (Shift) and `fromCenter` (Option) work as they do when drawing:
    /// - A box corner keeps the proportions it started with; an edge keeps them too, growing the other axis around its centre.
    ///   A note keeps its own text-fitting rules and ignores both.
    /// - A line or arrow end snaps to 45° steps around the other end.
    /// - An image corner, which keeps its proportions by default, resizes freely with `constrain`.
    /// - With `fromCenter`, the opposite side mirrors the drag, so the shape grows around its centre (a line or arrow's
    ///   ends move symmetrically around its midpoint, and an edge mirrors only on its own axis).
    public mutating func resize(_ handle: AnnotationHandle, to point: CGPoint, tolerance: CGFloat = 0, constrain: Bool = false, fromCenter: Bool = false) {
        if case let .radius(index) = handle {
            if let (shape, rect, _) = cornerBox, let (corner, inward) = Self.radiusAxis(of: index, shape: shape, in: rect) {
                let inset = ((point.x - corner.x) * inward.dx + (point.y - corner.y) * inward.dy) / 2
                cornerRadius = shape.clampedRadius(max(0, (inset - tolerance * 2) * 2), in: rect)
            }
            return
        }
        /// `rect`'s corners with the handle's sides moved to `point`; past the opposite side, `max` is less than `min`.
        func corners(_ rect: CGRect) -> (min: CGPoint, max: CGPoint) {
            Self.boxCorners(of: rect, handle: handle, to: point, constrain: constrain, fromCenter: fromCenter)
        }
        /// The ends of a line or arrow with the one `handle` names moved to `point`.
        func ends(_ from: CGPoint, _ to: CGPoint) -> (from: CGPoint, to: CGPoint) {
            let middle = CGPoint(x: (from.x + to.x) / 2, y: (from.y + to.y) / 2)
            let fixed = handle == .start ? to : from
            let anchor = fromCenter ? middle : fixed
            let moved = constrain ? Geometry.snapped(from: anchor, to: point) : point
            let other = fromCenter ? CGPoint(x: 2 * middle.x - moved.x, y: 2 * middle.y - moved.y) : fixed
            return handle == .start ? (moved, other) : (other, moved)
        }
        func box(_ rect: CGRect) -> CGRect {
            let (min, max) = corners(rect)
            return Geometry.normalized(from: min, to: max)
        }
        switch (kind, handle) {
        case let (.arrow(from, to), .start), let (.arrow(from, to), .end):
            let moved = ends(from, to)
            kind = .arrow(from: moved.from, to: moved.to)
        case let (.line(from, to), .start), let (.line(from, to), .end):
            let moved = ends(from, to)
            kind = .line(from: moved.from, to: moved.to)
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
            kind = .image(image, rect: Self.resizedImageRect(rect, handle: handle, to: point, free: constrain, fromCenter: fromCenter))
        }
    }

    /// `rect`'s corners with `handle`'s sides moved to `point`, in the order `resize` needs them: past the opposite side,
    /// `max` is less than `min`. See `resize` for `constrain` and `fromCenter`.
    private static func boxCorners(of rect: CGRect, handle: AnnotationHandle, to point: CGPoint, constrain: Bool, fromCenter: Bool) -> (min: CGPoint, max: CGPoint) {
        let sideX = CGFloat(handle.dx), sideY = CGFloat(handle.dy)
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        var point = point
        // A corner scales both axes by the same factor, whichever the pointer has dragged further, and follows the pointer
        // across the anchor so the box can still flip.
        if constrain, sideX != 0, sideY != 0, rect.width > 0, rect.height > 0 {
            let anchor = fromCenter ? centre : handle.opposite.point(in: rect)
            let half: CGFloat = fromCenter ? 0.5 : 1
            let dx = point.x - anchor.x, dy = point.y - anchor.y
            let factor = max(abs(dx) / (rect.width * half), abs(dy) / (rect.height * half))
            point = CGPoint(
                x: anchor.x + (dx == 0 ? sideX : dx < 0 ? -1 : 1) * rect.width * half * factor,
                y: anchor.y + (dy == 0 ? sideY : dy < 0 ? -1 : 1) * rect.height * half * factor
            )
        }
        func axis(_ side: CGFloat, to value: CGFloat, low: CGFloat, high: CGFloat) -> (low: CGFloat, high: CGFloat) {
            switch side {
            case -1: (value, fromCenter ? low + high - value : high)
            case 1: (fromCenter ? low + high - value : low, value)
            default: (low, high)
            }
        }
        var (minX, maxX) = axis(sideX, to: point.x, low: rect.minX, high: rect.maxX)
        var (minY, maxY) = axis(sideY, to: point.y, low: rect.minY, high: rect.maxY)
        // An edge keeps the proportions by growing the other axis around its centre.
        if constrain, (sideX == 0) != (sideY == 0), rect.width > 0, rect.height > 0 {
            if sideX != 0 {
                let height = abs(maxX - minX) * rect.height / rect.width
                (minY, maxY) = (centre.y - height / 2, centre.y + height / 2)
            } else {
                let width = abs(maxY - minY) * rect.width / rect.height
                (minX, maxX) = (centre.x - width / 2, centre.x + width / 2)
            }
        }
        return (CGPoint(x: minX, y: minY), CGPoint(x: maxX, y: maxY))
    }

    /// The opposite corner stays put and the image grows or shrinks by whichever axis was dragged further, down to
    /// `AnnotationImage.minSide` on its shorter side. With `free`, each axis follows the pointer on its own, down to
    /// `minSide` on each. With `fromCenter`, the centre stays put instead. An edge handle changes nothing.
    private static func resizedImageRect(_ rect: CGRect, handle: AnnotationHandle, to point: CGPoint, free: Bool, fromCenter: Bool) -> CGRect {
        guard handle.dx != 0, handle.dy != 0, rect.width > 0, rect.height > 0 else {
            return rect
        }
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let anchor = fromCenter ? centre : handle.opposite.point(in: rect)
        // How far the pointer is from the anchor, along the handle's own diagonal; a centre anchor counts for half a side.
        let reachX = (point.x - anchor.x) * CGFloat(handle.dx), reachY = (point.y - anchor.y) * CGFloat(handle.dy)
        let share: CGFloat = fromCenter ? 2 : 1
        let width: CGFloat, height: CGFloat
        if free {
            width = max(reachX * share, AnnotationImage.minSide)
            height = max(reachY * share, AnnotationImage.minSide)
        } else {
            let factor = max(reachX * share / rect.width, reachY * share / rect.height, AnnotationImage.minSide / min(rect.width, rect.height))
            width = rect.width * factor
            height = rect.height * factor
        }
        if fromCenter {
            return CGRect(x: centre.x - width / 2, y: centre.y - height / 2, width: width, height: height)
        }
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

    /// The distance from `p` to the nearest point on the segment from `a` to `b`.
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
        indices.reversed().first { !self[$0].isHidden && !self[$0].isLocked && self[$0].hitTest(point, tolerance: tolerance) }
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

/// A point on a selected annotation that drags to resize it.
public enum AnnotationHandle: Hashable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    /// A line or arrow's ends.
    case start, end
    /// A line or arrow's middle, which drags to bend it.
    case mid
    /// A shape's corner radius, from the handle inside its corner `index`, counting as `BoxShape.vertices` does.
    case radius(Int)

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

extension Annotation {
    /// What the layers panel and the timeline call it: the name it was given, else the first words of a text or note,
    /// else its kind.
    public var layerName: String {
        name ?? automaticName
    }

    /// Renames it as the layers panel's name field does: an empty name goes back to the automatic one, and the name it
    /// already shows leaves it as it is, so committing an untouched field doesn't fix an automatic name in place.
    public mutating func rename(to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != layerName else {
            return
        }
        name = trimmed
    }

    private var automaticName: String {
        switch kind {
        case let .text(string, _, _): Self.firstWords(of: string) ?? kindTitle
        case let .note(string, _): Self.firstWords(of: string) ?? kindTitle
        case let .counter(number, _): String(localized: "Step \(number)")
        case .arrow, .line, .shape, .highlight, .pixelate, .blur, .spotlight, .freehand, .marker, .image: kindTitle
        }
    }

    /// What kind of annotation it is, whatever it's named.
    public var kindTitle: String {
        switch kind {
        case .arrow: String(localized: "Arrow")
        case .line: String(localized: "Line")
        case let .shape(shape, _): shape.title
        case .highlight: String(localized: "Highlight")
        case .pixelate: String(localized: "Pixelate")
        case .blur: String(localized: "Blur")
        case .spotlight: String(localized: "Spotlight")
        case .text: String(localized: "Text")
        case .note: String(localized: "Note")
        case .counter: String(localized: "Step")
        case .freehand: String(localized: "Pen")
        case .marker: String(localized: "Highlighter")
        case .image: String(localized: "Image")
        }
    }

    /// What VoiceOver says after its name: its kind, unless the name is just that.
    public var accessibilityKind: String {
        layerName == kindTitle ? String(localized: "annotation") : kindTitle.localizedLowercase
    }


    private static func firstWords(of string: String, limit: Int = 24) -> String? {
        let words = string.split(whereSeparator: \.isWhitespace)
        guard let first = words.first else {
            return nil
        }
        var name = String(first.prefix(limit))
        for word in words.dropFirst() {
            guard name.count + 1 + word.count <= limit else {
                return name + "…"
            }
            name += " " + word
        }
        return name
    }
}
