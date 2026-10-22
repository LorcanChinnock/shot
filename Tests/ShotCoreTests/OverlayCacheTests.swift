import CoreImage
import Testing
@testable import ShotCore

private let canvas = CGRect(x: 0, y: 0, width: 20, height: 20)

private func box(_ x: CGFloat = 1) -> Annotation {
    Annotation(kind: .shape(.rectangle, rect: CGRect(x: x, y: 1, width: 4, height: 4)), color: RGBA.presets[0], lineWidth: 1)
}

private func solid(_ color: CIColor) -> CIImage {
    CIImage(color: color).cropped(to: canvas)
}

/// The red of the pixel in the middle of `image`, from 0 to 255.
private func middleRed(of image: CIImage) -> UInt8 {
    var bytes = [UInt8](repeating: 0, count: 4)
    CIContext().render(image, toBitmap: &bytes, rowBytes: 4, bounds: CGRect(x: 10, y: 10, width: 1, height: 1), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
    return bytes[0]
}

struct OverlayCacheTests {
    @Test func theSameAnnotationsOnTheSameCanvasAreDrawnOnce() {
        let cache = OverlayCache()
        var draws = 0
        let draw = { () -> CIImage? in
            draws += 1
            return solid(.red)
        }
        let annotations = [box()]
        let first = cache.overlay(for: annotations, canvas: canvas.size, draw: draw)
        let second = cache.overlay(for: annotations, canvas: canvas.size, draw: draw)
        #expect(draws == 1)
        #expect(first === second)
        _ = cache.overlay(for: annotations, canvas: CGSize(width: 40, height: 40), draw: draw)
        #expect(draws == 2)
    }

    @Test func theLeastRecentlyUsedOverlayIsDroppedFirst() {
        let cache = OverlayCache(capacity: 2)
        let a = [box(1)], b = [box(2)], c = [box(3)]
        var drawn: [CGFloat] = []
        func get(_ annotations: [Annotation]) {
            _ = cache.overlay(for: annotations, canvas: canvas.size) {
                drawn.append(annotations[0].bounds.minX)
                return solid(.red)
            }
        }
        get(a)
        get(b)
        get(a)
        get(c)
        get(a)
        get(b)
        #expect(drawn == [a, b, c, b].map { $0[0].bounds.minX })
    }

    @Test func plainAnnotationsUseTheCachedOverlay() {
        let cache = OverlayCache()
        let annotations = [box()]
        _ = cache.overlay(for: annotations, canvas: canvas.size) { solid(.red) }
        let result = AnnotationFrame.apply(annotations, to: solid(.blue), canvas: canvas, context: CIContext(), cache: cache)
        #expect(middleRed(of: result) == 255)
    }

    @Test func annotationsThatNeedThePictureAreNotCached() {
        let cache = OverlayCache()
        let blur = [Annotation(kind: .blur(CGRect(x: 1, y: 1, width: 4, height: 4)), color: RGBA.presets[0], lineWidth: 1)]
        _ = cache.overlay(for: blur, canvas: canvas.size) { solid(.red) }
        let result = AnnotationFrame.apply(blur, to: solid(.blue), canvas: canvas, context: CIContext(), cache: cache)
        #expect(middleRed(of: result) == 0)
    }
}
