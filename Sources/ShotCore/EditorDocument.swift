import CoreGraphics
import CoreText
import Foundation
import os

public struct EditorDocument: @unchecked Sendable {
    public var base: CGImage
    public var annotations: [Annotation]
    /// Everything the document holds, in image pixels: the image with its shadow and border, and padding that reaches
    /// past it for annotations. It always contains the image, and it's what the frame crop can be adjusted within.
    public var contentRect: CGRect
    /// The part of `contentRect` the export keeps, or `nil` to keep all of it. It can lie partly in the padding. What it
    /// leaves out, image and annotations, is hidden but kept, so the crop can be adjusted outward again.
    public var frameCrop: CGRect?
    /// Whether the frame crop is left out of the export, which shows all of `contentRect`.
    public var isFrameCropHidden = false
    /// Fills the canvas behind the image; `nil` is transparent.
    public var background: RGBA?
    /// How far the image's corners are rounded, in image pixels.
    public var captureCornerRadius: CGFloat = 0
    /// The image's shadow and border.
    public var captureStyle = ObjectStyle()
    /// Whether the image is a window capture that includes the macOS window shadow, so it takes no shadow of its own.
    public var hasWindowShadow = false

    /// `canvasRect` is the region the document shows: a part of the image becomes the frame crop, and one that holds the
    /// whole image is its padding.
    public init(base: CGImage, annotations: [Annotation] = [], canvasRect: CGRect? = nil, background: RGBA? = nil) {
        self.base = base
        self.annotations = annotations
        let full = CGRect(x: 0, y: 0, width: base.width, height: base.height)
        if let canvasRect, !canvasRect.contains(full), !canvasRect.isEmpty {
            contentRect = canvasRect.union(full)
            frameCrop = canvasRect
        } else {
            contentRect = canvasRect ?? full
        }
        self.background = background
    }

    public var fullRect: CGRect { CGRect(x: 0, y: 0, width: base.width, height: base.height) }
    /// The frame crop while it's in effect.
    public var visibleCrop: CGRect? { isFrameCropHidden ? nil : frameCrop }
    /// The part of the image the export shows: all of it, or what the crop leaves. Empty when the crop is wholly in the padding.
    public var captureRect: CGRect {
        guard let crop = visibleCrop else {
            return fullRect
        }
        let shown = fullRect.intersection(crop)
        return shown.isNull ? .zero : shown
    }

    /// The exported region in image pixels. It can be smaller than the image (a crop) or reach past it (padding). A
    /// cropped one is the crop plus what the screenshot's shadow and border need around the part still showing.
    public var canvasRect: CGRect {
        guard let crop = visibleCrop else {
            return contentRect
        }
        let shown = captureRect
        guard !shown.isEmpty else {
            return crop
        }
        return crop.union(captureStyle.paintedRect(around: shown)).integral
    }
    public var exportSize: CGSize { canvasRect.size }
    /// Whether the canvas reaches past the image on any side.
    public var hasPadding: Bool { !fullRect.contains(canvasRect) }

    /// JPEG has no alpha, so transparent padding would export as black.
    public static func defaultBackground(for format: ImageFormat) -> RGBA? {
        format == .jpeg ? RGBA(1, 1, 1) : nil
    }

    /// Sets the frame crop to `rect` on whole pixels, which may lie in the padding, within `contentRect`. A crop that
    /// leaves nothing of `contentRect` out is no crop. It's in effect from now on, even if it was hidden.
    public mutating func crop(to rect: CGRect) {
        let kept = rect.integral.intersection(contentRect)
        guard !kept.isNull, kept.width >= 1, kept.height >= 1 else {
            return
        }
        frameCrop = kept == contentRect ? nil : kept
        isFrameCropHidden = false
    }

    /// Removes the frame crop.
    public mutating func resetCrop() {
        frameCrop = nil
        isFrameCropHidden = false
    }

    /// Keeps the frame crop within `contentRect` once that has changed, and drops it if nothing is left or it holds all of it.
    private mutating func clampCrop() {
        guard let crop = frameCrop else {
            return
        }
        let kept = crop.intersection(contentRect)
        if kept.isNull || kept.width < 1 || kept.height < 1 || kept == contentRect {
            resetCrop()
        } else {
            frameCrop = kept
        }
    }

    /// Grows `contentRect` to hold `annotation` plus `margin` on each side its shape reaches past.
    /// A spotlight only dims the image, so it never grows it.
    public mutating func grow(toFit annotation: Annotation, margin: CGFloat) {
        if case .spotlight = annotation.kind {
            return
        }
        let shape = annotation.bounds
        let painted = annotation.paintedBounds.insetBy(dx: -margin, dy: -margin)
        var minX = contentRect.minX, minY = contentRect.minY, maxX = contentRect.maxX, maxY = contentRect.maxY
        if shape.minX < minX { minX = painted.minX }
        if shape.minY < minY { minY = painted.minY }
        if shape.maxX > maxX { maxX = painted.maxX }
        if shape.maxY > maxY { maxY = painted.maxY }
        contentRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).integral
    }

    /// Pulls padding back in to what the annotations and the image's shadow and border still need, so moving or removing
    /// one retracts the content. Only edges at or beyond the image shrink, and never past the image.
    public mutating func shrinkPadding(margin: CGFloat) {
        let image = fullRect
        guard contentRect.minX < image.minX || contentRect.minY < image.minY || contentRect.maxX > image.maxX || contentRect.maxY > image.maxY else {
            return
        }
        let shapes = annotations.filter { annotation in
            if case .spotlight = annotation.kind { return false }
            return true
        }.map { (annotation: $0, bounds: $0.bounds) }
        let capture = capturePaintedBounds
        func edge(_ current: CGFloat, image imageEdge: CGFloat, reaches: ((CGRect) -> Bool), painted paintedEdge: ((CGRect) -> CGFloat), outward: CGFloat) -> CGFloat {
            guard (current - imageEdge) * outward > 0 else {
                return current
            }
            let needed = shapes.filter { reaches($0.bounds) }
                .map { paintedEdge($0.annotation.paintedBounds.insetBy(dx: -margin, dy: -margin)) }
                .reduce(paintedEdge(capture)) { outward > 0 ? max($0, $1) : min($0, $1) }
            return outward > 0 ? min(current, needed) : max(current, needed)
        }
        let minX = edge(contentRect.minX, image: image.minX, reaches: { $0.minX < image.minX }, painted: { $0.minX }, outward: -1)
        let minY = edge(contentRect.minY, image: image.minY, reaches: { $0.minY < image.minY }, painted: { $0.minY }, outward: -1)
        let maxX = edge(contentRect.maxX, image: image.maxX, reaches: { $0.maxX > image.maxX }, painted: { $0.maxX }, outward: 1)
        let maxY = edge(contentRect.maxY, image: image.maxY, reaches: { $0.maxY > image.maxY }, painted: { $0.maxY }, outward: 1)
        contentRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY).integral
        clampCrop()
    }

    /// Sizes the content to the image with its shadow and border, and every annotation but spotlights, with `margin`
    /// around the annotations. A frame crop stays, within it.
    public mutating func fitToContent(margin: CGFloat) {
        contentRect = annotations.reduce(capturePaintedBounds) { canvas, annotation in
            if case .spotlight = annotation.kind {
                return canvas
            }
            return canvas.union(annotation.paintedBounds.insetBy(dx: -margin, dy: -margin))
        }.integral
        clampCrop()
    }

    /// The part of the image, and of what's drawn under the lowest spotlight, that the spotlights dim: all of it
    /// outside every hard-edged spotlight, never the rest of the padding. `softSpotlights` fade it further.
    /// `nil` when there are no spotlights. One with no area, such as a straight drag, dims nothing.
    public var spotlightDimPath: CGPath? {
        var lit: CGPath?
        var hasSpotlight = false
        var isAboveDim = false
        let below = CGMutablePath()
        for annotation in annotations where !annotation.isHidden {
            guard case let .spotlight(rect, style) = annotation.kind else {
                if !isAboveDim, !annotation.paintedBounds.isNull {
                    below.addRect(annotation.paintedBounds)
                }
                continue
            }
            isAboveDim = true
            guard !rect.isEmpty else {
                continue
            }
            hasSpotlight = true
            guard style.softEdge == 0 else {
                continue
            }
            let shape = style.shape.path(in: rect, cornerRadius: annotation.cornerRadius)
            lit = lit?.union(shape) ?? shape
        }
        guard hasSpotlight else {
            return nil
        }
        let radius = clampedCaptureCornerRadius
        let image = CGPath(roundedRect: captureRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let dimmable = below.isEmpty ? image : below.union(image)
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

    /// Removes the padding but what the image's shadow and border need. A frame crop stays, within what's left.
    public mutating func trimToImage() {
        contentRect = capturePaintedBounds.integral
        clampCrop()
    }

    public var snapshot: EditorSnapshot {
        EditorSnapshot(
            annotations: annotations, contentRect: contentRect, frameCrop: frameCrop, isFrameCropHidden: isFrameCropHidden,
            background: background, captureCornerRadius: captureCornerRadius, captureStyle: captureStyle
        )
    }

    public mutating func restore(_ snapshot: EditorSnapshot) {
        annotations = snapshot.annotations
        contentRect = snapshot.contentRect
        frameCrop = snapshot.frameCrop
        isFrameCropHidden = snapshot.isFrameCropHidden
        background = snapshot.background
        captureCornerRadius = snapshot.captureCornerRadius
        captureStyle = snapshot.captureStyle
    }
}

public struct EditorSnapshot: Equatable, Sendable {
    public var annotations: [Annotation]
    public var contentRect: CGRect
    public var frameCrop: CGRect?
    public var isFrameCropHidden: Bool
    public var background: RGBA?
    public var captureCornerRadius: CGFloat
    public var captureStyle: ObjectStyle
}

/// The last cropped screenshot, so drawing it again returns the same image.
private let lastCapturePicture = OSAllocatedUnfairLock<(base: CGImage, rect: CGRect, picture: CGImage)?>(initialState: nil)

/// The last screenshot asked whether it has see-through pixels, and the answer, so asking again on every edit doesn't
/// read it again.
private let lastCaptureTransparency = OSAllocatedUnfairLock<(image: CGImage, transparent: Bool)?>(initialState: nil)

extension EditorDocument {
    /// Drops the screenshot `hasTransparency(of: .capture)` kept.
    static func forgetCaptureTransparency() {
        lastCaptureTransparency.withLock { $0 = nil }
        lastCapturePicture.withLock { $0 = nil }
    }

    /// The capture's corner radius, within what the image can take.
    public var clampedCaptureCornerRadius: CGFloat {
        BoxShape.cornerRadius(captureCornerRadius, in: captureRect)
    }

    /// The image plus how far its shadow and border paint past it.
    public var capturePaintedBounds: CGRect {
        captureStyle.paintedRect(around: fullRect)
    }

    /// The image as the export draws it: all of it, or the part the frame crop leaves, which the style goes around.
    /// The crop is kept while it's the same screenshot and part, so redrawing doesn't make the shadow's caches start again.
    var capturePicture: CGImage {
        let shown = captureRect
        guard shown != fullRect, !shown.isEmpty else {
            return base
        }
        let base = base
        if let known = lastCapturePicture.withLock({ $0.flatMap { $0.base === base && $0.rect == shown ? $0.picture : nil } }) {
            return known
        }
        guard let picture = base.cropping(to: shown) else {
            return base
        }
        lastCapturePicture.withLock { $0 = (base, shown, picture) }
        return picture
    }

    /// What `target`'s style is on; `nil` for an annotation that isn't there or can't be styled.
    public func styleKind(of target: StyleTarget) -> StyleKind? {
        switch target {
        case .capture: .capture
        case let .annotation(id): annotations.first { $0.id == id }?.styleKind
        }
    }

    /// Whether `target` has see-through pixels, which an outline needs. The screenshot's answer is kept while it's the
    /// same screenshot.
    public func hasTransparency(of target: StyleTarget) -> Bool {
        switch target {
        case .capture:
            let base = base
            if let known = lastCaptureTransparency.withLock({ $0.flatMap { $0.image === base ? $0.transparent : nil } }) {
                return known
            }
            let transparent = base.hasTransparentPixels
            lastCaptureTransparency.withLock { $0 = (base, transparent) }
            return transparent
        case let .annotation(id):
            return annotations.first { $0.id == id }?.hasTransparency ?? false
        }
    }

    /// The style of `target`; empty for an annotation that isn't there.
    public func style(of target: StyleTarget) -> ObjectStyle {
        switch target {
        case .capture: captureStyle
        case let .annotation(id): annotations.first { $0.id == id }?.style ?? ObjectStyle()
        }
    }

    /// The corner radius of `target`, as set; 0 for an annotation that isn't there.
    public func cornerRadius(of target: StyleTarget) -> CGFloat {
        switch target {
        case .capture: captureCornerRadius
        case let .annotation(id): annotations.first { $0.id == id }?.cornerRadius ?? 0
        }
    }

    /// Restyles `target`, growing the canvas to hold its shadow and border and pulling back padding they no longer need.
    /// A border the target can't have is dropped. A window captured with the macOS shadow takes no style: its image
    /// includes the shadow's see-through margin, which a border or corners would go round. A locked annotation, or one
    /// that can't be styled, is left alone.
    public mutating func setStyle(_ style: ObjectStyle, of target: StyleTarget, margin: CGFloat) {
        guard let kind = styleKind(of: target) else {
            return
        }
        let style = style.restricted(to: kind, transparent: style.border?.kind == .outline && hasTransparency(of: target))
        switch target {
        case .capture:
            captureStyle = hasWindowShadow ? ObjectStyle() : style
            growToFitCapture()
        case let .annotation(id):
            guard let index = annotations.firstIndex(where: { $0.id == id }), !annotations[index].isLocked else {
                return
            }
            annotations[index].style = style
            grow(toFit: annotations[index], margin: margin)
        }
        shrinkPadding(margin: margin)
    }

    /// Sets the corner radius of `target`. A locked annotation, one without corners to round, and a window captured with
    /// the macOS shadow are left alone.
    public mutating func setCornerRadius(_ radius: CGFloat, of target: StyleTarget) {
        let radius = max(0, radius)
        switch target {
        case .capture:
            captureCornerRadius = hasWindowShadow ? 0 : radius
        case let .annotation(id):
            guard let index = annotations.firstIndex(where: { $0.id == id }), annotations[index].styleKind?.takesCorners == true, !annotations[index].isLocked else {
                return
            }
            annotations[index].cornerRadius = radius == 0 ? nil : radius
        }
    }

    /// The style of `target` to paste on others, in points of a document of `scale` pixels per point; `nil` for an
    /// annotation that isn't there or can't be styled.
    public func copyStyle(of target: StyleTarget, scale: CGFloat) -> CopiedStyle? {
        guard let kind = styleKind(of: target) else {
            return nil
        }
        return CopiedStyle(style: style(of: target).scaled(by: 1 / scale), cornerRadius: cornerRadius(of: target) / scale, source: kind, fromShape: isShapeWithCorners(target))
    }

    /// Pastes `copied` on each of `targets`, on a document of `scale` pixels per point: the fields both it and the target
    /// have. Every kind has a shadow; the border goes only on a target that can have that border, and S, M and L stay S,
    /// M and L; the corners go only between things with corners. Locked annotations are left alone.
    public mutating func pasteStyle(_ copied: CopiedStyle, to targets: [StyleTarget], scale: CGFloat, margin: CGFloat) {
        for target in targets {
            guard let kind = styleKind(of: target) else {
                continue
            }
            let transparent = copied.style.border?.kind == .outline && hasTransparency(of: target)
            setStyle(copied.pasted(on: style(of: target), of: kind, transparent: transparent, scale: scale), of: target, margin: margin)
            if let radius = copied.pastedCornerRadius(on: kind, ontoShape: isShapeWithCorners(target), scale: scale) {
                if case let .annotation(id) = target, let index = annotations.firstIndex(where: { $0.id == id }), annotations[index].roundsShape, !annotations[index].isLocked {
                    annotations[index].cornerRadius = radius == 0 ? nil : radius
                } else {
                    setCornerRadius(radius, of: target)
                }
            }
        }
    }

    private func isShapeWithCorners(_ target: StyleTarget) -> Bool {
        if case let .annotation(id) = target { annotations.first { $0.id == id }?.roundsShape == true } else { false }
    }

    /// What Apply Style to All Images restyles: the screenshot and every placed image.
    public var imageStyleTargets: [StyleTarget] {
        [.capture] + annotations.filter { $0.styleKind == .image }.map { .annotation($0.id) }
    }

    /// Grows the content just enough to show the capture's shadow and border.
    public mutating func growToFitCapture() {
        contentRect = contentRect.union(capturePaintedBounds).integral
    }
}

public extension EditorDocument {
    /// Whether this screenshot, in a document of `scale` pixels per point, has `newCaptureStyle`, the style Use this
    /// style for new captures saved; false when that's off.
    func captureHas(_ newCaptureStyle: CopiedStyle?, scale: CGFloat) -> Bool {
        guard let newCaptureStyle, let style = copyStyle(of: .capture, scale: scale) else {
            return false
        }
        return style.isSameStyle(as: newCaptureStyle)
    }
}

extension EditorDocument {
    /// Removes the annotations in `ids` that aren't locked, and the padding only they needed. Returns the ids removed.
    @discardableResult
    public mutating func deleteLayers(_ ids: Set<UUID>, margin: CGFloat) -> Set<UUID> {
        let removable = Set(annotations.filter { ids.contains($0.id) && !$0.isLocked }.map(\.id))
        guard !removable.isEmpty else {
            return []
        }
        annotations.removeAll { removable.contains($0.id) }
        shrinkPadding(margin: margin)
        return removable
    }
}

extension EditorDocument {
    /// Adds a copy of `annotation`, `step` pixels down and right of it, and returns the copy's id.
    /// A copy that would land off the canvas is centred on it instead, a spot already holding a copy
    /// steps on again so repeated pastes cascade, and a counter takes the next number.
    /// The canvas grows if the copy reaches past its edge.
    @discardableResult
    public mutating func paste(_ annotation: Annotation, step: CGFloat, margin: CGFloat) -> UUID {
        var copy = annotation.withNewID()
        copy.isHidden = false
        copy.isLocked = false
        if case let .counter(_, center) = copy.kind {
            copy.kind = .counter(annotations.nextCounterNumber, center: center)
        }
        let offset = CGVector(dx: step, dy: step)
        copy.offset(by: offset)
        if !copy.bounds.intersects(canvasRect) {
            copy.offset(by: CGVector(dx: canvasRect.midX - copy.bounds.midX, dy: canvasRect.midY - copy.bounds.midY))
        }
        if step > 0 {
            while annotations.contains(where: { $0.bounds == copy.bounds }) {
                copy.offset(by: offset)
            }
        }
        annotations.append(copy)
        grow(toFit: copy, margin: margin)
        return copy.id
    }

    /// Moves the annotation with `id` by `delta`, growing the canvas if it now reaches past the edge and shrinking it if it no longer does.
    public mutating func move(_ id: UUID, by delta: CGVector, margin: CGFloat) {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else {
            return
        }
        annotations[index].offset(by: delta)
        grow(toFit: annotations[index], margin: margin)
        shrinkPadding(margin: margin)
    }
}

extension EditorDocument {
    /// The size, in canvas pixels, to place an image at whose pixels are `scale` per point on a document
    /// whose are `documentScale` per point. An image of lower density is scaled up to show at the same
    /// size in points; one of the same or higher density keeps one image pixel per canvas pixel, since
    /// shrinking it would throw pixels away.
    public static func placementSize(of image: CGImage, scale: CGFloat, documentScale: CGFloat) -> CGSize {
        let factor = max(1, documentScale / max(scale, 1))
        return CGSize(width: CGFloat(image.width) * factor, height: CGFloat(image.height) * factor)
    }

    /// Where an image goes when no drop chose a spot: `gap` to the right of the canvas, level with its top,
    /// so screenshots line up side by side. Past a frame crop it would be hidden, so with one it's centred on the canvas.
    public func rectBesideCanvas(_ size: CGSize, gap: CGFloat) -> CGRect {
        let canvas = canvasRect
        let origin: CGPoint
        if visibleCrop == nil {
            origin = CGPoint(x: canvas.maxX + gap, y: canvas.minY)
        } else {
            origin = CGPoint(x: canvas.midX - size.width / 2, y: canvas.midY - size.height / 2)
        }
        return CGRect(origin: CGPoint(x: origin.x.rounded(), y: origin.y.rounded()), size: size)
    }

    /// Places `image` on whole pixels, centred on `point` or beside the canvas when there's none, grows the
    /// canvas to hold it, and returns its annotation's id. See `placementSize` for the size it's given.
    @discardableResult
    public mutating func addImage(_ image: CGImage, scale: CGFloat, documentScale: CGFloat, centeredAt point: CGPoint?, margin: CGFloat) -> UUID {
        let size = Self.placementSize(of: image, scale: scale, documentScale: documentScale)
        let rect: CGRect
        if let point {
            rect = CGRect(origin: CGPoint(x: (point.x - size.width / 2).rounded(), y: (point.y - size.height / 2).rounded()), size: size)
        } else {
            rect = rectBesideCanvas(size, gap: margin)
        }
        let annotation = Annotation(kind: .image(AnnotationImage(image), rect: rect), color: RGBA(0, 0, 0), lineWidth: 0)
        annotations.append(annotation)
        grow(toFit: annotation, margin: margin)
        return annotation.id
    }
}
