import CoreGraphics
import Foundation

extension RGBA {
    /// The names of `presets`, in the same order.
    public static let presetNames = ["Red", "Orange", "Yellow", "Green", "Blue", "Black", "White"]

    /// The lowercase name of the preset nearest this colour, such as "red".
    public var nearestPresetName: String {
        func distance(_ other: RGBA) -> CGFloat {
            (r - other.r) * (r - other.r) + (g - other.g) * (g - other.g) + (b - other.b) * (b - other.b)
        }
        let nearest = Self.presets.indices.min { distance(Self.presets[$0]) < distance(Self.presets[$1]) } ?? 0
        return Self.presetNames[nearest].lowercased()
    }
}

extension CaptureMark {
    /// `annotations` as an agent reads them, in the pixels of a file saved from `canvas` (in image pixels) and scaled by
    /// `scale`, which is 0.5 for a Retina capture saved at half size. Hidden ones, and ones cropped out of the canvas,
    /// are left out, as they aren't in the file.
    public static func mapping(_ annotations: [Annotation], canvas: CGRect, scale: CGFloat = 1) -> [CaptureMark] {
        annotations.filter { !$0.isHidden && $0.paintedBounds.intersects(canvas) }.map { CaptureMark($0, origin: canvas.origin, scale: scale) }
    }

    init(_ annotation: Annotation, origin: CGPoint, scale: CGFloat) {
        func value(_ v: CGFloat) -> Double { (Double(v * scale) * 10).rounded() / 10 }
        func point(_ p: CGPoint) -> [Double] { [value(p.x - origin.x), value(p.y - origin.y)] }
        func box(_ r: CGRect) -> [Double] { [value(r.minX - origin.x), value(r.minY - origin.y), value(r.width), value(r.height)] }
        self.init(id: annotation.id.uuidString, type: "")
        // Enough to rebuild the mark in the editor, in the file's pixels like the rest.
        lineWidth = value(annotation.lineWidth)
        fill = annotation.fill?.hex
        bend = annotation.bend.map { [value($0.dx), value($0.dy)] }
        cornerRadius = annotation.cornerRadius.map(value)
        let redacted = "redacted, content hidden"
        var colored = true
        switch annotation.kind {
        case let .arrow(start, end), let .line(start, end):
            if case .arrow = annotation.kind { type = "arrow" } else { type = "line" }
            from = point(start)
            to = point(end)
        case let .shape(shape, area):
            type = shape.rawValue
            rect = box(area)
        case let .highlight(area):
            type = "highlight"
            rect = box(area)
        case let .blur(area, strength):
            type = "blur"
            rect = box(area)
            amount = strength.map(Double.init)
            note = redacted
            colored = false
        case let .pixelate(area, strength):
            type = "pixelate"
            rect = box(area)
            amount = strength.map(Double.init)
            note = redacted
            colored = false
        case let .spotlight(area, _):
            type = "spotlight"
            rect = box(area)
            note = "the area outside is dimmed"
            colored = false
        case let .text(string, _, size):
            type = "text"
            text = string
            rect = box(annotation.bounds)
            fontSize = value(size)
        case let .counter(value, middle):
            type = "counter"
            number = value
            center = point(middle)
        case let .note(string, _):
            type = "note"
            text = string
            rect = box(annotation.bounds)
        case let .freehand(stroke):
            type = "pen"
            rect = box(annotation.bounds)
            points = stroke.map(point)
        case let .marker(stroke):
            type = "marker"
            rect = box(annotation.bounds)
            points = stroke.map(point)
        case let .image(_, area):
            type = "image"
            rect = box(area)
            colored = false
        }
        if colored {
            color = annotation.color.nearestPresetName
            hex = annotation.color.hex
        }
    }
}

extension Annotation {
    /// `mark` as a live annotation in the pixels of the image it was drawn on: the inverse of `CaptureMark.mapping` for a
    /// file saved from `origin` at `scale`. What a mark leaves out takes the editor's defaults, with `lineWidth` as the
    /// line width. `nil` when the mark lacks what its type needs, or is a placed image, whose pixels a record doesn't hold.
    public init?(mark: CaptureMark, origin: CGPoint = .zero, scale: CGFloat = 1, lineWidth defaultLineWidth: CGFloat = EditorStyle.widths[1]) {
        guard scale > 0 else {
            return nil
        }
        func length(_ v: Double) -> CGFloat? { v.isFinite ? CGFloat(v) / scale : nil }
        func point(_ p: [Double]?) -> CGPoint? {
            guard let p, p.count == 2, let x = length(p[0]), let y = length(p[1]) else { return nil }
            return CGPoint(x: x + origin.x, y: y + origin.y)
        }
        func box(_ r: [Double]?) -> CGRect? {
            guard let r, r.count == 4, let x = length(r[0]), let y = length(r[1]), let w = length(r[2]), let h = length(r[3]), w >= 0, h >= 0 else { return nil }
            return CGRect(x: x + origin.x, y: y + origin.y, width: w, height: h)
        }
        let width = mark.lineWidth.flatMap(length).flatMap { $0 > 0 ? $0 : nil } ?? defaultLineWidth
        let kind: Kind
        switch mark.type {
        case "arrow", "line":
            guard let from = point(mark.from), let to = point(mark.to) else { return nil }
            kind = mark.type == "arrow" ? .arrow(from: from, to: to) : .line(from: from, to: to)
        case "highlight":
            guard let rect = box(mark.rect) else { return nil }
            kind = .highlight(rect)
        case "blur", "pixelate":
            guard let rect = box(mark.rect) else { return nil }
            let amount = mark.amount.flatMap { $0.isFinite && $0 > 0 ? CGFloat($0) : nil }
            kind = mark.type == "blur" ? .blur(rect, amount: amount) : .pixelate(rect, amount: amount)
        case "spotlight":
            guard let rect = box(mark.rect) else { return nil }
            kind = .spotlight(rect, style: SpotlightStyle())
        case "text":
            // A text's rect is its laid-out frame, which starts at its origin.
            guard let text = mark.text, let rect = box(mark.rect) else { return nil }
            kind = .text(text, origin: rect.origin, fontSize: mark.fontSize.flatMap(length).flatMap { $0 > 0 ? $0 : nil } ?? width * 6)
        case "counter":
            guard let center = point(mark.center) else { return nil }
            kind = .counter(mark.number ?? 1, center: center)
        case "note":
            guard let text = mark.text, let rect = box(mark.rect) else { return nil }
            kind = .note(text, rect: rect)
        case "pen", "marker":
            let points = (mark.points ?? []).compactMap(point)
            guard !points.isEmpty, points.count == mark.points?.count else { return nil }
            kind = mark.type == "pen" ? .freehand(points) : .marker(points)
        default:
            guard let shape = BoxShape(rawValue: mark.type), let rect = box(mark.rect) else { return nil }
            kind = .shape(shape, rect: rect)
        }
        let color = mark.hex.flatMap(RGBA.init(hex:))
            ?? mark.color.flatMap { name in RGBA.presetNames.firstIndex { $0.lowercased() == name.lowercased() }.map { RGBA.presets[$0] } }
            ?? (mark.type == "note" ? EditorStyle().noteColor : EditorStyle().color)
        self.init(id: mark.id.flatMap(UUID.init(uuidString:)) ?? UUID(), kind: kind, color: color, fill: mark.fill.flatMap(RGBA.init(hex:)), lineWidth: width)
        if let bend = mark.bend, bend.count == 2, let dx = length(bend[0]), let dy = length(bend[1]) {
            self.bend = CGVector(dx: dx, dy: dy)
        }
        cornerRadius = mark.cornerRadius.flatMap(length)
    }
}

extension RGBA {
    /// `#RGB`, `#RRGGBB` or `#RRGGBBAA`, as `HexColor` reads it.
    public init?(hex: String) {
        guard let c = HexColor.components(hex) else {
            return nil
        }
        self.init(c.red, c.green, c.blue, c.alpha)
    }
}

extension CaptureMark {
    /// Whether every one of `annotations`, saved from `canvas` at 1:1, comes back from its mark as it is, so the saved
    /// version can reopen with them live. Placed images, spotlights, styled marks, aligned text and hidden or cropped-out
    /// layers don't: a record doesn't hold all of them.
    public static func rebuildExactly(_ annotations: [Annotation], canvas: CGRect) -> Bool {
        annotations.allSatisfy { annotation in
            switch annotation.kind {
            case .image, .spotlight:
                return false
            default:
                break
            }
            guard !annotation.isHidden, annotation.paintedBounds.intersects(canvas), annotation.style.isEmpty, annotation.alignment == .left else {
                return false
            }
            let mark = CaptureMark(annotation, origin: canvas.origin, scale: 1)
            return Annotation(mark: mark, origin: canvas.origin).map { CaptureMark($0, origin: canvas.origin, scale: 1) } == mark
        }
    }
}

extension CaptureRecord {
    /// The marks as live annotations on `original`, and the part of it they were saved from, when this version can
    /// reopen that way: its writer said every layer comes back exactly, and the file is that part at 1:1.
    public var editableLayers: (annotations: [Annotation], canvas: CGRect)? {
        guard editable == true, original != nil, let canvas, canvas.count == 4, canvas.allSatisfy(\.isFinite),
              abs(Double(size.width) - canvas[2]) <= 1, abs(Double(size.height) - canvas[3]) <= 1
        else {
            return nil
        }
        let rect = CGRect(x: canvas[0], y: canvas[1], width: canvas[2], height: canvas[3])
        let layers = annotations.compactMap { Annotation(mark: $0, origin: rect.origin) }
        return layers.count == annotations.count ? (layers, rect) : nil
    }
}
