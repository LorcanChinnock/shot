import CoreGraphics
import CoreText
import Foundation

public struct RGBA: Equatable, Hashable, Sendable {
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
public struct Annotation: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var kind: Kind
    public var color: RGBA
    public var lineWidth: CGFloat

    public enum Kind: Equatable, Sendable {
        case arrow(from: CGPoint, to: CGPoint)
        case line(from: CGPoint, to: CGPoint)
        case rect(CGRect)
        case ellipse(CGRect)
        case highlight(CGRect)
        case pixelate(CGRect)
        case text(String, origin: CGPoint, fontSize: CGFloat)
        case counter(Int, center: CGPoint)
        /// A sticky note. `rect` sets the wrap width; the note grows taller than it to fit the text.
        case note(String, rect: CGRect)
    }

    public init(id: UUID = UUID(), kind: Kind, color: RGBA, lineWidth: CGFloat) {
        self.id = id
        self.kind = kind
        self.color = color
        self.lineWidth = lineWidth
    }

    public var counterRadius: CGFloat { lineWidth * 3 + 10 }
    public var noteFontSize: CGFloat { lineWidth * 3 + 8 }

    /// The laid-out note, or `nil` if this isn't one.
    public var noteLayout: NoteLayout? {
        guard case let .note(string, rect) = kind else {
            return nil
        }
        return NoteLayout(string: string, rect: rect, fontSize: noteFontSize, color: color)
    }

    public var bounds: CGRect {
        switch kind {
        case let .arrow(from, to), let .line(from, to):
            return CGRect(x: min(from.x, to.x), y: min(from.y, to.y), width: abs(to.x - from.x), height: abs(to.y - from.y))
        case let .rect(rect), let .ellipse(rect), let .highlight(rect), let .pixelate(rect):
            return rect
        case let .text(string, origin, fontSize):
            return CGRect(origin: origin, size: TextLayout(string: string, fontSize: fontSize, color: color).size)
        case let .counter(_, center):
            return CGRect(x: center.x - counterRadius, y: center.y - counterRadius, width: counterRadius * 2, height: counterRadius * 2)
        case .note:
            return noteLayout?.frame ?? .null
        }
    }

    /// `bounds` plus the stroke and arrowhead that the renderer paints past it.
    public var paintedBounds: CGRect {
        switch kind {
        case .arrow:
            let head = max(12, lineWidth * 4) * 0.45
            let outset = max(head, lineWidth / 2)
            return bounds.insetBy(dx: -outset, dy: -outset)
        case .line, .rect, .ellipse:
            return bounds.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)
        case .highlight, .pixelate, .text, .counter:
            return bounds
        case .note:
            guard let layout = noteLayout else {
                return bounds
            }
            let shadow = layout.frame.offsetBy(dx: 0, dy: layout.shadowOffset).insetBy(dx: -layout.shadowBlur, dy: -layout.shadowBlur)
            return layout.frame.union(shadow)
        }
    }

    public func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        let slop = tolerance + lineWidth / 2
        switch kind {
        case let .arrow(from, to), let .line(from, to):
            return Self.distance(from: point, toSegment: from, to) <= slop
        case let .rect(rect):
            return rect.insetBy(dx: -slop, dy: -slop).contains(point) && !rect.insetBy(dx: slop, dy: slop).contains(point)
        case let .ellipse(rect):
            guard rect.width > 0, rect.height > 0 else {
                return false
            }
            let dx = (point.x - rect.midX) / (rect.width / 2)
            let dy = (point.y - rect.midY) / (rect.height / 2)
            let normalized = sqrt(dx * dx + dy * dy)
            return abs(normalized - 1) * min(rect.width, rect.height) / 2 <= slop
        case .highlight, .pixelate, .text, .note:
            return bounds.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        case let .counter(_, center):
            return hypot(point.x - center.x, point.y - center.y) <= counterRadius + tolerance
        }
    }

    public mutating func offset(by delta: CGVector) {
        func move(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + delta.dx, y: p.y + delta.dy) }
        switch kind {
        case let .arrow(from, to): kind = .arrow(from: move(from), to: move(to))
        case let .line(from, to): kind = .line(from: move(from), to: move(to))
        case let .rect(rect): kind = .rect(rect.offsetBy(dx: delta.dx, dy: delta.dy))
        case let .ellipse(rect): kind = .ellipse(rect.offsetBy(dx: delta.dx, dy: delta.dy))
        case let .highlight(rect): kind = .highlight(rect.offsetBy(dx: delta.dx, dy: delta.dy))
        case let .pixelate(rect): kind = .pixelate(rect.offsetBy(dx: delta.dx, dy: delta.dy))
        case let .text(string, origin, size): kind = .text(string, origin: move(origin), fontSize: size)
        case let .counter(number, center): kind = .counter(number, center: move(center))
        case let .note(string, rect): kind = .note(string, rect: rect.offsetBy(dx: delta.dx, dy: delta.dy))
        }
    }

    /// Replaces a note's text; other kinds are left alone.
    public mutating func setNoteText(_ string: String) {
        if case let .note(_, rect) = kind {
            kind = .note(string, rect: rect)
        }
    }

    /// The note's resize handle within `tolerance` of `point`, if any.
    public func noteHandle(at point: CGPoint, tolerance: CGFloat) -> NoteHandle? {
        guard case .note = kind else {
            return nil
        }
        let frame = bounds
        return NoteHandle.allCases.first { handle in
            let corner = handle.point(in: frame)
            return abs(point.x - corner.x) <= tolerance && abs(point.y - corner.y) <= tolerance
        }
    }

    /// Drags a note's corner `handle` to `point`. The opposite corner stays put, and the note
    /// never gets narrower than its minimum or shorter than its text.
    public mutating func resizeNote(_ handle: NoteHandle, to point: CGPoint) {
        guard case let .note(string, _) = kind, let layout = noteLayout else {
            return
        }
        let frame = layout.frame
        let minWidth = NoteLayout.minWidth(fontSize: layout.fontSize)
        let minX: CGFloat, width: CGFloat
        if handle.isLeft {
            minX = min(point.x, frame.maxX - minWidth)
            width = frame.maxX - minX
        } else {
            minX = frame.minX
            width = max(point.x - frame.minX, minWidth)
        }
        let rect: CGRect
        if handle.isTop {
            let textHeight = NoteLayout(string: string, rect: CGRect(x: minX, y: 0, width: width, height: 0), fontSize: layout.fontSize, color: color).frame.height
            let minY = min(point.y, frame.maxY - textHeight)
            rect = CGRect(x: minX, y: minY, width: width, height: frame.maxY - minY)
        } else {
            rect = CGRect(x: minX, y: frame.minY, width: width, height: max(0, point.y - frame.minY))
        }
        kind = .note(string, rect: rect)
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
    public mutating func grow(toFit annotation: Annotation, margin: CGFloat) {
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

    /// Sizes the canvas to the image and every annotation, with `margin` around the annotations.
    public mutating func fitToContent(margin: CGFloat) {
        canvasRect = annotations.reduce(fullRect) { $0.union($1.paintedBounds.insetBy(dx: -margin, dy: -margin)) }.integral
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

public enum NoteHandle: CaseIterable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight

    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    var isTop: Bool { self == .topLeft || self == .topRight }

    public func point(in rect: CGRect) -> CGPoint {
        CGPoint(x: isLeft ? rect.minX : rect.maxX, y: isTop ? rect.minY : rect.maxY)
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
