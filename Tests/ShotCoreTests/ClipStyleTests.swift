import CoreImage
import Foundation
import Testing
@testable import ShotCore

private let float = ShadowPreset.float.shadow(scale: 1)
private let context = CIContext(options: [.workingColorSpace: NSNull(), .outputColorSpace: NSNull()])

/// A square clip of 100 pixels on a square `canvas`, scaled by `scale`, with `style` and `cornerRadius`.
private func square(scale: Double, offset: CGSize = .zero, opacity: Double = 1, style: ObjectStyle = ObjectStyle(), cornerRadius: CGFloat = 0) -> Clip {
    var clip = Clip(source: URL(fileURLWithPath: "/clip.mp4"), sourceDuration: 1, size: CGSize(width: 100, height: 100), transform: ClipTransform(offset: offset, scale: scale, opacity: opacity))
    clip.style = style
    clip.cornerRadius = cornerRadius
    return clip
}

/// `clip`'s picture, red unless `color` says otherwise, placed on a grey canvas of `side` pixels as the compositor places
/// it, with its style.
private func composite(_ clip: Clip, side: CGFloat, lift: Double = 1, color: CIColor = .red, shadows: ClipShadowCache = ClipShadowCache()) -> CIImage {
    let canvas = CGSize(width: side, height: side)
    let placement = LayerGeometry.imageTransform(orientation: .identity, geometry: LayerGeometry.transform(for: clip, canvas: canvas), sourceHeight: 100, canvasHeight: side)
    let frame = CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100))
    let grey = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: CGRect(origin: .zero, size: canvas))
    return ClipStyler.composite(frame.transformed(by: placement), of: clip, frame: frame, placement: placement, fit: side / 100, lift: lift, over: grey, shadows: shadows, context: context)
}

/// The red and green of the pixel at (`x`, `y`) from the top left of an image of `side` pixels.
private func pixel(_ image: CIImage, x: CGFloat, y: CGFloat, side: CGFloat) -> (r: Int, g: Int) {
    var bytes = [UInt8](repeating: 0, count: 4)
    context.render(image, toBitmap: &bytes, rowBytes: 4, bounds: CGRect(x: x, y: side - y - 1, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
    return (Int(bytes[0]), Int(bytes[1]))
}

@Test func aProjectSavedBeforeClipStylesDecodesUnchangedAndAStyledOneRoundTrips() throws {
    let plain = Project(source: URL(fileURLWithPath: "/recording.mp4"), duration: 4, canvasSize: CGSize(width: 1920, height: 1080), hasAudio: true)
    let saved = try JSONEncoder().encode(plain)
    let json = try #require(String(data: saved, encoding: .utf8))
    #expect(!json.contains("objectStyle") && !json.contains("radius"), "a plain clip stores nothing new")
    #expect(try JSONDecoder().decode(Project.self, from: saved) == plain)

    var styled = plain
    styled.tracks[0].clips[0].style = ObjectStyle(shadow: float, border: Border(kind: .solid, lineWidth: 6, color: RGBA(1, 0, 0)))
    styled.tracks[0].clips[0].cornerRadius = 24
    let decoded = try JSONDecoder().decode(Project.self, from: JSONEncoder().encode(styled))
    #expect(decoded == styled)
    #expect(decoded.main.clips[0].style.shadow == float)
    #expect(decoded.main.clips[0].cornerRadius == 24)
}

@Test func aStyledRecordingIsDrawnRatherThanTrimmed() throws {
    let plain = Project(source: URL(fileURLWithPath: "/recording.mp4"), duration: 4, canvasSize: CGSize(width: 1920, height: 1080), hasAudio: true)
    #expect(plain.trimEdit != nil)
    let id = plain.main.clips[0].id
    #expect(try #require(plain.setting(cornerRadius: 20, of: id)).trimEdit == nil)
    #expect(try #require(plain.setting(style: ObjectStyle(shadow: float), of: id)).trimEdit == nil)
}

@Test func aClipTakesOnlyTheBordersAPictureCanHave() throws {
    let plain = Project(source: URL(fileURLWithPath: "/recording.mp4"), duration: 4, canvasSize: CGSize(width: 1920, height: 1080), hasAudio: false)
    let id = plain.main.clips[0].id
    let outlined = try #require(plain.setting(style: ObjectStyle(shadow: float, border: Border(kind: .outline, lineWidth: 8)), of: id))
    #expect(outlined.main.clips[0].style == ObjectStyle(shadow: float))
}

@Test func theCompositorRoundsAClipsCornersToShowWhatIsUnderThem() {
    // At half scale the 200 pixel clip sits from 50 to 150, its 40 pixel radius halved with it.
    let image = composite(square(scale: 0.5, cornerRadius: 40), side: 200)
    #expect(pixel(image, x: 51, y: 51, side: 200).r < 160, "the corner shows the grey under it")
    #expect(pixel(image, x: 148, y: 148, side: 200).r < 160)
    #expect(pixel(image, x: 100, y: 100, side: 200).r > 240, "the middle is the clip")
    #expect(pixel(image, x: 51, y: 100, side: 200).r > 240, "the middle of an edge is the clip")
}

@Test func aClipsShadowFallsBelowItAndNotAbove() {
    // The clip sits from 100 to 300.
    let image = composite(square(scale: 0.5, style: ObjectStyle(shadow: float)), side: 400)
    let above = pixel(image, x: 200, y: 88, side: 400), below = pixel(image, x: 200, y: 312, side: 400)
    #expect(abs(above.r - 128) <= 4, "nothing above, got \(above)")
    #expect(below.r < above.r - 8, "darker below, got \(below)")
    #expect(below.r == below.g, "a grey shadow, not the clip's red")
}

@Test func aClipsShadowGrowsAndShrinksWithIt() {
    // A quarter of 800 pixels ends at 500 and a half at 600, so each is sampled the same distance below its edge.
    let small = pixel(composite(square(scale: 0.25, style: ObjectStyle(shadow: float)), side: 800), x: 400, y: 524, side: 800)
    let large = pixel(composite(square(scale: 0.5, style: ObjectStyle(shadow: float)), side: 800), x: 400, y: 624, side: 800)
    #expect(large.r < small.r - 4, "the larger clip's shadow reaches further, got \(large) and \(small)")
}

@Test func aClipsShadowIsBlurredOnceAndReusedFromFrameToFrame() {
    let shadows = ClipShadowCache()
    let style = ObjectStyle(shadow: ShadowPreset.soft.shadow(scale: 1))
    _ = composite(square(scale: 0.5, style: style), side: 400, shadows: shadows)
    #expect(shadows.count == 3, "one mask per layer")
    // Moving, fading or scaling a little only moves, fades or scales the masks.
    _ = composite(square(scale: 0.5, offset: CGSize(width: 40, height: -30), opacity: 0.6, style: style), side: 400, shadows: shadows)
    _ = composite(square(scale: 0.51, style: style), side: 400, shadows: shadows)
    #expect(shadows.count == 3)
    _ = composite(square(scale: 1, style: style), side: 400, shadows: shadows)
    #expect(shadows.count == 6, "a new scale blurs again")
}

@Test func popAndSlideInLiftAShadowWhileTheyPlay() {
    let canvas = CGSize(width: 1920, height: 1080)
    let pop = ClipAnimation().applying(.pop, length: 3, base: PropertyValues(), canvas: canvas)
    #expect(pop.lift(at: 0) == 1)
    #expect(pop.lift(at: 0.225) > 1.9, "highest halfway in")
    #expect(pop.lift(at: 0.45) == 1, "settled once it lands")
    #expect(pop.lift(at: 2) == 1)
    #expect(ClipAnimation().applying(.slideIn, length: 3, base: PropertyValues(), canvas: canvas).lift(at: 0.25) > 1.9)
    #expect(ClipAnimation().applying(.fadeIn, length: 3, base: PropertyValues(), canvas: canvas).lift(at: 0.25) == 1, "a fade doesn't move")

    var slow = ClipAnimation()
    slow.set(.position, at: 0, to: PropertyValues())
    slow.set(.position, at: 2, to: PropertyValues(position: CGSize(width: 400, height: 0)))
    #expect(slow.lift(at: 1) == 1, "a long move isn't an entrance")
}

@Test func anAnnotationClipsShadowGrowsWithItsScaleAndLiftsAsItPopsIn() throws {
    let box = Annotation(kind: .shape(.rectangle, rect: CGRect(x: 100, y: 100, width: 200, height: 100)), color: RGBA(1, 0, 0), lineWidth: 4)
    var styled = box
    styled.style = ObjectStyle(shadow: float, border: nil)
    let clip = AnnotationClip(annotation: styled, start: 0, duration: 3, transform: ClipTransform(scale: 2))
    #expect(clip.rendered(atTimeline: 1).annotation.style.shadow?.elevation == float.elevation * 2)

    var popped = clip
    popped.animation = ClipAnimation().applying(.pop, length: 3, base: clip.propertyValues, canvas: CGSize(width: 1920, height: 1080))
    let rising = try #require(popped.rendered(atTimeline: 0.225).annotation.style.shadow)
    let scale = popped.values(atTimeline: 0.225).scale
    #expect(rising.elevation > float.elevation * scale * 1.9)
}

@Test func aClipsHairlineAndGlowTakeTheirColourFromTheFramesEdge() {
    // On a white frame the hairline is the dark rim, so it darkens the grey just outside the clip, from 50 to 150.
    let light = pixel(composite(square(scale: 0.5, style: ObjectStyle(border: .hairline)), side: 200, color: .white), x: 49, y: 100, side: 200)
    let dark = pixel(composite(square(scale: 0.5, style: ObjectStyle(border: .hairline)), side: 200, color: .black), x: 49, y: 100, side: 200)
    #expect(light.r < 128, "dark rim on a light frame, got \(light)")
    #expect(dark.r > 128, "light rim on a dark frame, got \(dark)")
    // A glow around a red frame is red.
    let glow = pixel(composite(square(scale: 0.5, style: ObjectStyle(shadow: ShadowPreset.glow.shadow(scale: 1))), side: 200), x: 100, y: 46, side: 200)
    #expect(glow.r > 140 && glow.g < 120, "a red glow, got \(glow)")
}

@Test func theEdgeColourIsTheAverageNearTheEdgeNotTheMiddle() throws {
    // A white frame with a black middle, inside its outer eighth.
    let middle = CIImage(color: .black).cropped(to: CGRect(x: 20, y: 20, width: 60, height: 60))
    let frame = middle.composited(over: CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: 100, height: 100)))
    let edge = try #require(ClipStyler.edgeColor(of: frame, context: context))
    #expect(edge.r > 0.95 && edge.g > 0.95 && edge.b > 0.95)
}
