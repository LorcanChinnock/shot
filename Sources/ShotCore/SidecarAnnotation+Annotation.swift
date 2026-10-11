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

extension SidecarAnnotation {
    /// `annotations` as an agent reads them, in the pixels of a file saved from `canvas` (in image pixels) and scaled by
    /// `scale`, which is 0.5 for a Retina capture saved at half size. Hidden ones, and ones cropped out of the canvas,
    /// are left out, as they aren't in the file.
    public static func mapping(_ annotations: [Annotation], canvas: CGRect, scale: CGFloat = 1) -> [SidecarAnnotation] {
        annotations.filter { !$0.isHidden && $0.paintedBounds.intersects(canvas) }.map { SidecarAnnotation($0, origin: canvas.origin, scale: scale) }
    }

    init(_ annotation: Annotation, origin: CGPoint, scale: CGFloat) {
        func value(_ v: CGFloat) -> Double { (Double(v * scale) * 10).rounded() / 10 }
        func point(_ p: CGPoint) -> [Double] { [value(p.x - origin.x), value(p.y - origin.y)] }
        func box(_ r: CGRect) -> [Double] { [value(r.minX - origin.x), value(r.minY - origin.y), value(r.width), value(r.height)] }
        self.init(id: annotation.id.uuidString, type: "")
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
        case let .blur(area, _):
            type = "blur"
            rect = box(area)
            note = redacted
            colored = false
        case let .pixelate(area, _):
            type = "pixelate"
            rect = box(area)
            note = redacted
            colored = false
        case let .spotlight(area, _):
            type = "spotlight"
            rect = box(area)
            note = "the area outside is dimmed"
            colored = false
        case let .text(string, _, _):
            type = "text"
            text = string
            rect = box(annotation.bounds)
        case let .counter(value, middle):
            type = "counter"
            number = value
            center = point(middle)
        case let .note(string, _):
            type = "note"
            text = string
            rect = box(annotation.bounds)
        case .freehand:
            type = "pen"
            rect = box(annotation.bounds)
        case .marker:
            type = "marker"
            rect = box(annotation.bounds)
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
