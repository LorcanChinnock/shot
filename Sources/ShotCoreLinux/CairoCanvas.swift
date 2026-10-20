import CCairo
import CPango
import Foundation

/// Linux's `Canvas`: a Cairo image surface. Cairo has y down, so the canvas flips once when it's made, and callers see
/// y up from the bottom left, as on a `CGContext`. What Cairo lacks is drawn as CoreGraphics draws it:
///
/// - A shadow: what casts it is drawn into a layer of its own, unclipped, and the layer's alpha is blurred (`AlphaBlur`),
///   offset and tinted under it, all in device pixels.
/// - A mask clip: the masks clipped to so far are multiplied into one alpha surface over the clip's bounds, and each
///   drawing is drawn into a layer and composited through it.
/// - The alpha, blend mode, shadow and mask set when a transparency layer begins apply to the layer as a whole, and
///   inside it they start over, as in CoreGraphics.
///
/// Every `CanvasBlendMode` has a Cairo operator. A `.grey` canvas is RGB24, not A8, since an A8 surface keeps only
/// coverage and a mask is drawn by filling black as well as white; its images have the level in red, green and blue.
/// Display P3 is absent on Linux, so `.matching` draws in sRGB.
public final class CairoCanvas: Canvas {
    private let surface: Surface
    private let isGrey: Bool
    /// The context drawn into now: the canvas's own, or the innermost open layer's. A shaper's lines draw into it.
    public private(set) var context: OpaquePointer
    /// What `saveState` saved, innermost last, in the context drawn into now.
    private var states = [State()]
    /// The layers open now, innermost last.
    private var layers: [Layer] = []

    public init?(width: Int, height: Int, format: CanvasFormat) {
        let grey: Bool
        switch format {
        case .grey: grey = true
        case .sRGB, .matching: grey = false
        }
        guard width > 0, height > 0, let surface = Surface(format: grey ? CAIRO_FORMAT_RGB24 : CAIRO_FORMAT_ARGB32, width: width, height: height) else {
            return nil
        }
        self.surface = surface
        isGrey = grey
        context = cairo_create(surface.pointer)
        guard cairo_status(context) == CAIRO_STATUS_SUCCESS else {
            cairo_destroy(context)
            return nil
        }
        cairo_translate(context, 0, Double(height))
        cairo_scale(context, 1, -1)
        cairo_set_fill_rule(context, CAIRO_FILL_RULE_WINDING)
    }

    deinit {
        cairo_destroy(context)
        for layer in layers {
            cairo_destroy(layer.parent)
        }
    }

    public static var effects: any ImageEffects { PortableEffects() }
    public static var shaper: any TextShaper { PangoShaper() }

    // MARK: - State

    private struct State {
        var fill = RGBA(0, 0, 0)
        var stroke = RGBA(0, 0, 0)
        var alpha: CGFloat = 1
        var blend = CanvasBlendMode.normal
        var filter = CAIRO_FILTER_GOOD
        var shadow: Shadow?
        var mask: Mask?
    }

    /// A shadow in device pixels, so it looks the same however the canvas is scaled, as in CoreGraphics.
    private struct Shadow {
        var offset: CGSize
        var blur: CGFloat
        var color: RGBA
    }

    /// The product of the masks clipped to, as coverage over `origin` and the surface's size, in device pixels.
    private struct Mask {
        var surface: Surface
        var origin: CGPoint
    }

    private struct Layer {
        /// The context and states it was opened in.
        var parent: OpaquePointer
        var states: [State]
        var surface: Surface
        /// Where its surface's top left is, in device pixels.
        var origin: CGPoint
        /// What it's composited with.
        var state: State
    }

    private var state: State {
        get { states[states.count - 1] }
        set { states[states.count - 1] = newValue }
    }

    public func saveState() {
        cairo_save(context)
        states.append(state)
    }

    public func restoreState() {
        guard states.count > 1 else {
            return
        }
        cairo_restore(context)
        states.removeLast()
    }

    public func translateBy(x: CGFloat, y: CGFloat) { cairo_translate(context, x, y) }
    public func scaleBy(x: CGFloat, y: CGFloat) { cairo_scale(context, x, y) }

    public var pixelScale: CGFloat {
        var matrix = cairo_matrix_t()
        cairo_get_matrix(context, &matrix)
        return hypot(matrix.xx, matrix.yx)
    }

    public var clipBounds: CGRect {
        var x1 = 0.0, y1 = 0.0, x2 = 0.0, y2 = 0.0
        cairo_clip_extents(context, &x1, &y1, &x2, &y2)
        // CoreGraphics gives null for a clip that holds nothing.
        return x2 > x1 && y2 > y1 ? CGRect(x: x1, y: y1, width: x2 - x1, height: y2 - y1) : .null
    }

    public func clip(to rect: CGRect) {
        cairo_new_path(context)
        cairo_rectangle(context, rect.minX, rect.minY, rect.width, rect.height)
        cairo_clip(context)
    }

    public func clip(to path: CanvasPath) {
        add(path, to: context)
        cairo_clip(context)
    }

    public func setFillColor(_ color: RGBA) { state.fill = color }
    public func setStrokeColor(_ color: RGBA) { state.stroke = color }
    public func setLineWidth(_ width: CGFloat) { cairo_set_line_width(context, width) }

    public func setLineCap(_ cap: CanvasLineCap) {
        switch cap {
        case .butt: cairo_set_line_cap(context, CAIRO_LINE_CAP_BUTT)
        case .round: cairo_set_line_cap(context, CAIRO_LINE_CAP_ROUND)
        case .square: cairo_set_line_cap(context, CAIRO_LINE_CAP_SQUARE)
        }
    }

    public func setLineJoin(_ join: CanvasLineJoin) {
        switch join {
        case .miter: cairo_set_line_join(context, CAIRO_LINE_JOIN_MITER)
        case .round: cairo_set_line_join(context, CAIRO_LINE_JOIN_ROUND)
        case .bevel: cairo_set_line_join(context, CAIRO_LINE_JOIN_BEVEL)
        }
    }

    public func setBlendMode(_ mode: CanvasBlendMode) {
        state.blend = mode
        cairo_set_operator(context, Self.cairoOperator(for: mode))
    }

    private static func cairoOperator(for mode: CanvasBlendMode) -> cairo_operator_t {
        switch mode {
        case .normal: CAIRO_OPERATOR_OVER
        case .multiply: CAIRO_OPERATOR_MULTIPLY
        case .darken: CAIRO_OPERATOR_DARKEN
        case .sourceAtop: CAIRO_OPERATOR_ATOP
        }
    }

    public func setAlpha(_ alpha: CGFloat) { state.alpha = min(max(alpha, 0), 1) }

    public func setInterpolation(_ quality: CanvasInterpolation) {
        switch quality {
        case .low: state.filter = CAIRO_FILTER_FAST
        // Cairo's best filter sharpens an enlarged image past its own colours, which CoreGraphics' high quality doesn't.
        case .medium, .high: state.filter = CAIRO_FILTER_GOOD
        }
    }

    public func setShadow(offset: CGSize, blur: CGFloat, color: RGBA) {
        var dx = Double(offset.width), dy = Double(offset.height)
        cairo_user_to_device_distance(context, &dx, &dy)
        state.shadow = color.a > 0 ? Shadow(offset: CGSize(width: dx, height: dy), blur: max(blur, 0) * pixelScale, color: color) : nil
    }

    // MARK: - Layers

    public func beginTransparencyLayer() {
        let composite = state
        let shown = deviceClipBounds
        var area = shown
        if let shadow = composite.shadow {
            // What casts the visible shadow lies back along the offset, and its blur reaches in from further. Whole pixels, so
            // the layer lies on the canvas's grid and comes back unresampled, whatever the offset.
            let reach = CGFloat(AlphaBlur.reach(sigma: shadow.blur / 2) + 1)
            area = shown.union(shown.offsetBy(dx: -shadow.offset.width, dy: -shadow.offset.height)).insetBy(dx: -reach, dy: -reach).integral
        }
        let width = max(Int(area.width), 1), height = max(Int(area.height), 1)
        guard let layer = Surface(format: CAIRO_FORMAT_ARGB32, width: width, height: height) else {
            preconditionFailure("CairoCanvas couldn't make a \(width)×\(height) layer")
        }
        cairo_surface_set_device_offset(layer.pointer, -area.minX, -area.minY)
        let inner = cairo_create(layer.pointer)!
        var matrix = cairo_matrix_t()
        cairo_get_matrix(context, &matrix)
        cairo_set_matrix(inner, &matrix)
        cairo_set_line_width(inner, cairo_get_line_width(context))
        cairo_set_line_cap(inner, cairo_get_line_cap(context))
        cairo_set_line_join(inner, cairo_get_line_join(context))
        cairo_set_miter_limit(inner, cairo_get_miter_limit(context))
        cairo_set_fill_rule(inner, CAIRO_FILL_RULE_WINDING)
        layers.append(Layer(parent: context, states: states, surface: layer, origin: area.origin, state: composite))
        context = inner
        states = [State(fill: composite.fill, stroke: composite.stroke, filter: composite.filter)]
    }

    public func endTransparencyLayer() {
        guard let layer = layers.popLast() else {
            return
        }
        cairo_destroy(context)
        context = layer.parent
        states = layer.states
        cairo_surface_flush(layer.surface.pointer)
        cairo_surface_set_device_offset(layer.surface.pointer, 0, 0)
        composite(layer.surface, at: layer.origin, with: layer.state)
    }

    /// Draws `source`, its top left at `origin` in device pixels, with `state`'s shadow, alpha, blend mode and mask.
    private func composite(_ source: Surface, at origin: CGPoint, with state: State) {
        cairo_save(context)
        defer { cairo_restore(context) }
        cairo_identity_matrix(context)
        // A mask applies to the shadow and what casts it together.
        let masked = state.mask != nil
        if masked {
            cairo_push_group(context)
        }
        cairo_set_operator(context, masked ? CAIRO_OPERATOR_OVER : Self.cairoOperator(for: state.blend))
        if let shadow = state.shadow, let mask = source.blurredAlpha(sigma: shadow.blur / 2) {
            let color = shadow.color
            cairo_set_source_rgba(context, color.r, color.g, color.b, color.a * state.alpha)
            cairo_mask_surface(context, mask.pointer, origin.x + shadow.offset.width, origin.y + shadow.offset.height)
        }
        cairo_set_source_surface(context, source.pointer, origin.x, origin.y)
        cairo_paint_with_alpha(context, state.alpha)
        if let mask = state.mask {
            cairo_pop_group_to_source(context)
            cairo_set_operator(context, Self.cairoOperator(for: state.blend))
            cairo_mask_surface(context, mask.surface.pointer, mask.origin.x, mask.origin.y)
        }
    }

    /// The clip's bounds in device pixels, rounded out.
    private var deviceClipBounds: CGRect {
        cairo_save(context)
        defer { cairo_restore(context) }
        cairo_identity_matrix(context)
        var x1 = 0.0, y1 = 0.0, x2 = 0.0, y2 = 0.0
        cairo_clip_extents(context, &x1, &y1, &x2, &y2)
        return CGRect(x: x1, y: y1, width: max(x2 - x1, 0), height: max(y2 - y1, 0)).integral
    }

    /// Runs `draw` on the context drawn into, given the alpha to draw with: straight onto it, or into a layer when there's
    /// a shadow or mask for a layer to take.
    private func paint(_ draw: (_ context: OpaquePointer, _ alpha: CGFloat) -> Void) {
        guard state.shadow != nil || state.mask != nil else {
            draw(context, state.alpha)
            return
        }
        beginTransparencyLayer()
        draw(context, 1)
        endTransparencyLayer()
    }

    // MARK: - Drawing

    public func fill(_ rect: CGRect) {
        let color = state.fill
        paint { context, alpha in
            cairo_new_path(context)
            cairo_rectangle(context, rect.minX, rect.minY, rect.width, rect.height)
            cairo_set_source_rgba(context, color.r, color.g, color.b, color.a * alpha)
            cairo_fill(context)
        }
    }

    public func fill(_ path: CanvasPath) {
        let color = state.fill
        paint { context, alpha in
            add(path, to: context)
            cairo_set_source_rgba(context, color.r, color.g, color.b, color.a * alpha)
            cairo_fill(context)
        }
    }

    public func stroke(_ path: CanvasPath) {
        let color = state.stroke
        paint { context, alpha in
            add(path, to: context)
            cairo_set_source_rgba(context, color.r, color.g, color.b, color.a * alpha)
            cairo_stroke(context)
        }
    }

    private func add(_ path: CanvasPath, to context: OpaquePointer) {
        cairo_new_path(context)
        for primitive in path.primitives {
            switch primitive {
            case let .move(to): cairo_move_to(context, to.x, to.y)
            case let .line(to): cairo_line_to(context, to.x, to.y)
            case let .curve(to, c1, c2): cairo_curve_to(context, c1.x, c1.y, c2.x, c2.y, to.x, to.y)
            case .close: cairo_close_path(context)
            }
        }
    }

    /// Draws `line` with its baseline starting at `position`, upright on a canvas the renderer has turned to have y down,
    /// as `CGCanvas` draws a Core Text line: filled in its own colour, or outlined in the stroke colour and line width.
    public func draw(_ line: any ShapedLine, at position: CGPoint, outlined: Bool) {
        guard let line = line as? PangoLine else {
            preconditionFailure("CairoCanvas draws only the lines PangoShaper makes")
        }
        let color = outlined ? state.stroke : line.color
        paint { context, alpha in
            // A colour emoji keeps its own colours, so a translucent line is drawn whole and then faded.
            if alpha < 1 {
                cairo_push_group(context)
            }
            cairo_new_path(context)
            cairo_move_to(context, position.x, position.y)
            cairo_set_source_rgba(context, color.r, color.g, color.b, color.a)
            if outlined {
                pango_cairo_layout_line_path(context, line.layout.line)
                cairo_stroke(context)
            } else {
                pango_cairo_show_layout_line(context, line.layout.line)
            }
            if alpha < 1 {
                cairo_pop_group_to_source(context)
                cairo_paint_with_alpha(context, alpha)
            }
        }
    }

    public func draw(_ image: PlatformImage, in rect: CGRect) {
        guard rect.width > 0, rect.height > 0, let source = Surface(image.bitmap) else {
            return
        }
        let filter = state.filter
        paint { context, alpha in
            cairo_save(context)
            defer { cairo_restore(context) }
            Self.setSource(source, filling: rect, filter: filter, of: context)
            cairo_new_path(context)
            cairo_rectangle(context, rect.minX, rect.minY, rect.width, rect.height)
            cairo_clip(context)
            cairo_paint_with_alpha(context, alpha)
        }
    }

    /// Makes `source` the context's source, stretched over `rect` with its first row at the rect's max y, as
    /// `CGContext.draw` draws an image, and its edge pixels repeating past it, so the edges blend only with themselves.
    private static func setSource(_ source: Surface, filling rect: CGRect, filter: cairo_filter_t, of context: OpaquePointer) {
        let pattern = cairo_pattern_create_for_surface(source.pointer)!
        defer { cairo_pattern_destroy(pattern) }
        let sx = CGFloat(source.width) / rect.width, sy = CGFloat(source.height) / rect.height
        var matrix = cairo_matrix_t()
        cairo_matrix_init(&matrix, sx, 0, 0, -sy, -rect.minX * sx, rect.maxY * sy)
        cairo_pattern_set_matrix(pattern, &matrix)
        cairo_pattern_set_filter(pattern, filter)
        cairo_pattern_set_extend(pattern, CAIRO_EXTEND_PAD)
        cairo_set_source(context, pattern)
    }

    public func clip(to rect: CGRect, mask image: PlatformImage) {
        clip(to: rect)
        let area = deviceClipBounds
        guard let mask = Surface(format: CAIRO_FORMAT_A8, width: max(Int(area.width), 1), height: max(Int(area.height), 1)) else {
            preconditionFailure("CairoCanvas couldn't make a \(area.width)×\(area.height) mask")
        }
        let drawing = cairo_create(mask.pointer)!
        defer { cairo_destroy(drawing) }
        if let outer = state.mask {
            cairo_set_source_surface(drawing, outer.surface.pointer, outer.origin.x - area.minX, outer.origin.y - area.minY)
        } else {
            cairo_set_source_rgba(drawing, 0, 0, 0, 1)
        }
        cairo_set_operator(drawing, CAIRO_OPERATOR_SOURCE)
        cairo_paint(drawing)
        guard !area.isEmpty, let levels = Surface(levelsOf: image.bitmap) else {
            state.mask = Mask(surface: mask, origin: area.origin)
            return
        }
        // The new mask in the canvas's current coordinates, multiplied in; IN clears what's outside the rect.
        var matrix = cairo_matrix_t()
        cairo_get_matrix(context, &matrix)
        matrix.x0 -= area.minX
        matrix.y0 -= area.minY
        cairo_set_matrix(drawing, &matrix)
        Self.setSource(levels, filling: rect, filter: CAIRO_FILTER_GOOD, of: drawing)
        cairo_set_operator(drawing, CAIRO_OPERATOR_IN)
        cairo_rectangle(drawing, rect.minX, rect.minY, rect.width, rect.height)
        cairo_fill(drawing)
        cairo_surface_flush(mask.pointer)
        state.mask = Mask(surface: mask, origin: area.origin)
    }

    public func makeImage() -> PlatformImage? {
        makeBitmap().map(BitmapImage.init)
    }

    public func makeBitmap() -> Bitmap? {
        surface.bitmap(grey: isGrey)
    }
}

/// A Cairo image surface, destroyed with the last reference to it.
private final class Surface {
    let pointer: OpaquePointer
    let width: Int
    let height: Int

    init?(format: cairo_format_t, width: Int, height: Int) {
        let pointer = cairo_image_surface_create(format, Int32(width), Int32(height))!
        guard cairo_surface_status(pointer) == CAIRO_STATUS_SUCCESS else {
            cairo_surface_destroy(pointer)
            return nil
        }
        self.pointer = pointer
        self.width = width
        self.height = height
    }

    deinit {
        cairo_surface_destroy(pointer)
    }

    private var stride: Int { Int(cairo_image_surface_get_stride(pointer)) }

    /// Runs `body` on the pixels, each row `stride` bytes, and tells Cairo they may have changed.
    private func withPixels<T>(_ body: (_ pixels: UnsafeMutableRawPointer, _ stride: Int) -> T) -> T {
        cairo_surface_flush(pointer)
        defer { cairo_surface_mark_dirty(pointer) }
        return body(cairo_image_surface_get_data(pointer), stride)
    }

    /// `bitmap`'s pixels as ARGB32, which Cairo keeps premultiplied in native-endian words, as `Bitmap` keeps RGBA bytes.
    convenience init?(_ bitmap: Bitmap) {
        self.init(format: CAIRO_FORMAT_ARGB32, width: bitmap.width, height: bitmap.height)
        bitmap.pixels.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            withPixels { pixels, stride in
                for y in 0..<height {
                    for x in 0..<width {
                        let i = y * bitmap.bytesPerRow + x * 4
                        let alpha = UInt32(bytes[i + 3]) << 24, red = UInt32(bytes[i]) << 16, green = UInt32(bytes[i + 1]) << 8
                        let word: UInt32 = alpha | red | green | UInt32(bytes[i + 2])
                        pixels.storeBytes(of: word, toByteOffset: y * stride + x * 4, as: UInt32.self)
                    }
                }
            }
        }
    }

    /// `bitmap`'s grey levels as A8 coverage, for a mask.
    convenience init?(levelsOf bitmap: Bitmap) {
        self.init(format: CAIRO_FORMAT_A8, width: bitmap.width, height: bitmap.height)
        bitmap.pixels.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            withPixels { pixels, stride in
                for y in 0..<height {
                    for x in 0..<width {
                        let i = y * bitmap.bytesPerRow + x * 4
                        pixels.storeBytes(of: Self.level(bytes[i], bytes[i + 1], bytes[i + 2]), toByteOffset: y * stride + x, as: UInt8.self)
                    }
                }
            }
        }
    }

    /// The Rec. 709 luma of an sRGB colour, which for a grey is its level.
    private static func level(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> UInt8 {
        let red: Int = 54 * Int(r), green: Int = 183 * Int(g), blue: Int = 19 * Int(b)
        return UInt8((red + green + blue + 128) >> 8)
    }

    /// An ARGB32 surface's alpha as A8, blurred by `sigma`.
    func blurredAlpha(sigma: CGFloat) -> Surface? {
        guard let mask = Surface(format: CAIRO_FORMAT_A8, width: width, height: height) else {
            return nil
        }
        withPixels { source, sourceStride in
            mask.withPixels { levels, stride in
                for y in 0..<height {
                    for x in 0..<width {
                        let alpha = UInt8(source.load(fromByteOffset: y * sourceStride + x * 4, as: UInt32.self) >> 24)
                        levels.storeBytes(of: alpha, toByteOffset: y * stride + x, as: UInt8.self)
                    }
                }
                let buffer = UnsafeMutableBufferPointer(start: levels.assumingMemoryBound(to: UInt8.self), count: stride * height)
                AlphaBlur.blur(buffer, width: width, height: height, stride: stride, sigma: sigma)
            }
        }
        return mask
    }

    /// The pixels as a `Bitmap`: an ARGB32 surface's as they are, an RGB24 one's as opaque grey.
    func bitmap(grey: Bool) -> Bitmap? {
        var data = Data(count: width * height * 4)
        data.withUnsafeMutableBytes { (out: UnsafeMutableRawBufferPointer) in
            withPixels { pixels, stride in
                for y in 0..<height {
                    for x in 0..<width {
                        let word = pixels.load(fromByteOffset: y * stride + x * 4, as: UInt32.self)
                        let r = UInt8(truncatingIfNeeded: word >> 16), g = UInt8(truncatingIfNeeded: word >> 8), b = UInt8(truncatingIfNeeded: word)
                        let o = (y * width + x) * 4
                        if grey {
                            let level = Self.level(r, g, b)
                            (out[o], out[o + 1], out[o + 2], out[o + 3]) = (level, level, level, 255)
                        } else {
                            (out[o], out[o + 1], out[o + 2], out[o + 3]) = (r, g, b, UInt8(word >> 24))
                        }
                    }
                }
            }
        }
        return Bitmap(width: width, height: height, pixels: data)
    }
}
