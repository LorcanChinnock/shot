#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation

/// An image to place with an `ImageEdit`, read from its file.
public struct PlacedImageFile: Sendable {
    public var image: PlatformImage
    /// Its pixels per point.
    public var scale: CGFloat

    public init(image: PlatformImage, scale: CGFloat) {
        self.image = image
        self.scale = scale
    }
}

extension EditorDocument {
    /// Makes `edit`'s changes as the image editor does, on a document of `scale` pixels per point whose saved file starts
    /// at the canvas's corner, so the edit's pixels are that file's. In order: the layers in `remove` go, then `drawn`
    /// and the marks go on top, then the images in `placed`, one for each of `edit.place`. Then the style, padding and
    /// background change, and the crop, given as `cropField` in messages, is applied last, within what the canvas shows.
    /// `name` is the file's, for messages. Scale and format are the saving's, not the document's.
    public mutating func apply(
        _ edit: ImageEdit, drawn: [Annotation] = [], placed: [PlacedImageFile] = [], scale: CGFloat, name: String, cropField: String = "crop", shaper: any TextShaper
    ) throws(ShotCommandError) {
        let margin = 16 * scale
        let shift = CGVector(dx: canvasRect.minX, dy: canvasRect.minY)

        var removing = Set<UUID>()
        for (index, text) in edit.remove.enumerated() {
            guard let id = UUID(uuidString: text), let layer = annotations.first(where: { $0.id == id }) else {
                throw .data("remove[\(index)]: \(name) has no layer \(text); its record lists each layer's id")
            }
            guard !layer.isLocked else {
                throw .data("remove[\(index)]: the layer \(text) is locked")
            }
            removing.insert(id)
        }
        deleteLayers(removing, margin: margin, shaper: shaper)

        var added = drawn
        for (index, mark) in edit.marks.enumerated() {
            // Widths an agent leaves out look as they would drawn in the editor at the capture's scale.
            guard let annotation = Annotation(mark: mark, lineWidth: EditorStyle.widths[1] * scale) else {
                throw .data("marks[\(index)] (\(mark.type)) can't be drawn")
            }
            added.append(annotation)
        }
        annotations += added.map { annotation in
            var moved = annotation
            moved.offset(by: shift)
            return moved
        }

        guard placed.count == edit.place.count else {
            throw .internal("expected \(edit.place.count) images to place, got \(placed.count)")
        }
        for (placement, file) in zip(edit.place, placed) {
            var size = Self.placementSize(of: file.image, scale: file.scale, documentScale: scale)
            if let width = placement.width {
                size = CGSize(width: CGFloat(width), height: (CGFloat(width) * CGFloat(file.image.height) / CGFloat(max(file.image.width, 1))).rounded())
            }
            let rect = placement.at.map { CGRect(x: CGFloat($0[0]) + shift.dx, y: CGFloat($0[1]) + shift.dy, width: size.width, height: size.height).integral }
                ?? rectBesideCanvas(size, gap: margin)
            let annotation = Annotation(kind: .image(AnnotationImage(file.image), rect: rect), color: RGBA(0, 0, 0), lineWidth: 0)
            annotations.append(annotation)
            grow(toFit: annotation, margin: margin, shaper: shaper)
        }

        if let style = edit.style {
            try applyStyle(style, scale: scale, margin: margin, name: name, shaper: shaper)
        }

        if let pad = edit.pad {
            let (top, right, bottom, left) = (CGFloat(pad[0]), CGFloat(pad[1]), CGFloat(pad[2]), CGFloat(pad[3]))
            let padded = CGRect(x: -left, y: -top, width: fullRect.width + left + right, height: fullRect.height + top + bottom)
            contentRect = contentRect.union(padded).integral
        }

        if let text = edit.background {
            background = text.lowercased() == "none" ? nil : RGBA(named: text)
        }

        if let crop = edit.crop {
            // Clamped to what the canvas shows before it, in the file's pixels: the file itself, plus any padding added.
            let canvas = canvasRect
            let origin = CGPoint(x: canvas.minX - shift.dx, y: canvas.minY - shift.dy)
            let relative = [crop[0] - Double(origin.x), crop[1] - Double(origin.y), crop[2], crop[3]]
            guard let region = CropRegion.clamped(relative, width: Int(canvas.width), height: Int(canvas.height)) else {
                throw .data("\(cropField) (\(CropRegion.text(crop))) is off the \(Int(canvas.width))×\(Int(canvas.height)) \(edit.pad == nil ? "image" : "canvas")")
            }
            self.crop(to: CGRect(x: CGFloat(region[0]) + canvas.minX, y: CGFloat(region[1]) + canvas.minY, width: CGFloat(region[2]), height: CGFloat(region[3])))
        }
    }

    private mutating func applyStyle(_ style: ImageEdit.Style, scale: CGFloat, margin: CGFloat, name: String, shaper: any TextShaper) throws(ShotCommandError) {
        var next = captureStyle
        if let shadow = style.shadow {
            next.shadow = ShadowPreset(rawValue: shadow)?.shadow(scale: scale)
        }
        if let border = style.border {
            switch border.type {
            case "hairline":
                next.border = .hairline
            case "solid", "outline":
                let kind: Border.Kind = border.type == "solid" ? .solid : .outline
                guard kind == .solid || hasTransparency(of: .capture) else {
                    throw .data("style.border: \(name) has no see-through pixels to outline; use solid or hairline")
                }
                next.border = Border(kind: kind, lineWidth: border.width.map { CGFloat($0) } ?? Border.widths(kind, on: .capture)[1] * scale, color: border.color.flatMap(RGBA.init(named:)))
            default:
                next.border = nil
            }
        }
        let corners = style.corners.map { CGFloat($0) }
        if hasWindowShadow, !next.isEmpty || (corners ?? 0) > 0 {
            throw .data("style: \(name) is a window captured with the macOS shadow, which takes no shadow, border or corners of its own")
        }
        setStyle(next, of: .capture, margin: margin, shaper: shaper)
        if let corners {
            setCornerRadius(corners, of: .capture)
        }
    }
}

extension RGBA {
    /// A palette name, such as "red", in any case, or a hex colour.
    public init?(named text: String) {
        if let index = RGBA.presetNames.firstIndex(where: { $0.lowercased() == text.lowercased() }) {
            self = RGBA.presets[index]
        } else {
            self.init(hex: text)
        }
    }
}
