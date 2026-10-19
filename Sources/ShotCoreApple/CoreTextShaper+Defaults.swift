import CoreGraphics
import Foundation

// ShotCore's calls that lay out or measure text take a `TextShaper`. On a Mac it's always Core Text, so these give the
// app, ShotCLI and the tests each call as it was, without one. Calls that also draw get theirs from the canvas type.

extension TextLayout {
    public init(string: String, fontSize: CGFloat, color: RGBA) {
        self.init(string: string, fontSize: fontSize, color: color, shaper: CoreTextShaper())
    }
}

extension NoteLayout {
    public init(string: String, rect: CGRect, fontSize: CGFloat, color: RGBA) {
        self.init(string: string, rect: rect, fontSize: fontSize, color: color, shaper: CoreTextShaper())
    }
}

extension Annotation {
    /// The laid-out note, or `nil` if this isn't one.
    public var noteLayout: NoteLayout? { noteLayout(shaper: CoreTextShaper()) }

    public var bounds: CGRect { bounds(shaper: CoreTextShaper()) }

    /// `bounds` plus the stroke and arrowhead that the renderer paints past it, and the shadow and border of its style.
    public var paintedBounds: CGRect { paintedBounds(shaper: CoreTextShaper()) }

    public func hitTest(_ point: CGPoint, tolerance: CGFloat) -> Bool {
        hitTest(point, tolerance: tolerance, shaper: CoreTextShaper())
    }

    public var handles: [(handle: AnnotationHandle, point: CGPoint)] { handles(shaper: CoreTextShaper()) }

    public func handle(at point: CGPoint, tolerance: CGFloat) -> AnnotationHandle? {
        handle(at: point, tolerance: tolerance, shaper: CoreTextShaper())
    }

    /// The annotation scaled by `factor` about the centre of its bounds.
    public func scaled(by factor: Double) -> Annotation {
        scaled(by: factor, shaper: CoreTextShaper())
    }

    public mutating func resize(_ handle: AnnotationHandle, to point: CGPoint, tolerance: CGFloat = 0, constrain: Bool = false, fromCenter: Bool = false) {
        resize(handle, to: point, tolerance: tolerance, constrain: constrain, fromCenter: fromCenter, shaper: CoreTextShaper())
    }
}

extension AnnotationClip {
    /// What to draw at timeline `time`: the annotation with its keyframes applied, and the turn and fade to give the result.
    public func rendered(atTimeline time: Double) -> (annotation: Annotation, rotation: Double, opacity: Double) {
        rendered(atTimeline: time, shaper: CoreTextShaper())
    }
}

extension [Annotation] {
    public func topmostIndex(at point: CGPoint, tolerance: CGFloat) -> Int? {
        topmostIndex(at: point, tolerance: tolerance, shaper: CoreTextShaper())
    }
}

extension EditorDocument {
    public mutating func grow(toFit annotation: Annotation, margin: CGFloat) {
        grow(toFit: annotation, margin: margin, shaper: CoreTextShaper())
    }

    public mutating func shrinkPadding(margin: CGFloat) {
        shrinkPadding(margin: margin, shaper: CoreTextShaper())
    }

    public mutating func fitToContent(margin: CGFloat) {
        fitToContent(margin: margin, shaper: CoreTextShaper())
    }

    public var spotlightDimPath: CGPath? { spotlightDimPath(shaper: CoreTextShaper()) }

    public mutating func setStyle(_ style: ObjectStyle, of target: StyleTarget, margin: CGFloat) {
        setStyle(style, of: target, margin: margin, shaper: CoreTextShaper())
    }

    public mutating func pasteStyle(_ copied: CopiedStyle, to targets: [StyleTarget], scale: CGFloat, margin: CGFloat) {
        pasteStyle(copied, to: targets, scale: scale, margin: margin, shaper: CoreTextShaper())
    }

    public mutating func cropImage(_ id: UUID, to visible: CGRect, margin: CGFloat) {
        cropImage(id, to: visible, margin: margin, shaper: CoreTextShaper())
    }

    public mutating func resetImageCrop(_ id: UUID, margin: CGFloat) {
        resetImageCrop(id, margin: margin, shaper: CoreTextShaper())
    }

    @discardableResult
    public mutating func deleteLayers(_ ids: Set<UUID>, margin: CGFloat) -> Set<UUID> {
        deleteLayers(ids, margin: margin, shaper: CoreTextShaper())
    }

    @discardableResult
    public mutating func paste(_ annotation: Annotation, step: CGFloat, margin: CGFloat) -> UUID {
        paste(annotation, step: step, margin: margin, shaper: CoreTextShaper())
    }

    public mutating func move(_ id: UUID, by delta: CGVector, margin: CGFloat) {
        move(id, by: delta, margin: margin, shaper: CoreTextShaper())
    }

    @discardableResult
    public mutating func addImage(_ image: CGImage, scale: CGFloat, documentScale: CGFloat, centeredAt point: CGPoint?, margin: CGFloat) -> UUID {
        addImage(image, scale: scale, documentScale: documentScale, centeredAt: point, margin: margin, shaper: CoreTextShaper())
    }

    public mutating func apply(
        _ edit: ImageEdit, drawn: [Annotation] = [], placed: [PlacedImageFile] = [], scale: CGFloat, name: String, cropField: String = "crop"
    ) throws(ShotCommandError) {
        try apply(edit, drawn: drawn, placed: placed, scale: scale, name: name, cropField: cropField, shaper: CoreTextShaper())
    }
}

extension CaptureMark {
    public static func mapping(_ annotations: [Annotation], canvas: CGRect, scale: CGFloat = 1) -> [CaptureMark] {
        mapping(annotations, canvas: canvas, scale: scale, shaper: CoreTextShaper())
    }

    public static func rebuildExactly(_ annotations: [Annotation], canvas: CGRect) -> Bool {
        rebuildExactly(annotations, canvas: canvas, shaper: CoreTextShaper())
    }
}

extension Project {
    public func reframed(to rect: CGRect, scale k: CGFloat = 1) -> Project? {
        reframed(to: rect, scale: k, shaper: CoreTextShaper())
    }

    public func applying(_ edit: VideoEdit, appended: [ImportedMedia] = []) throws(ShotCommandError) -> Project {
        try applying(edit, appended: appended, shaper: CoreTextShaper())
    }
}
