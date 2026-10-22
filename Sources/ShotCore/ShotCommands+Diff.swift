import CoreGraphics
import Foundation

extension ShotCommands {
    /// `shot diff`: reads both images into bytes at `b`'s size, finds the changes with `ImageDiff`, and
    /// writes a dimmed copy of `b` with the changed pixels lit and boxed, as a new file beside `b`.
    static func diff(_ options: ShotCommand.DiffOptions) throws(ShotCommandError) -> JSONValue {
        let a = url(options.a), b = url(options.b)
        try requireInput(a)
        try requireInput(b)
        guard let before = ImageCodec.image(at: a) else {
            throw .data("\(a.lastPathComponent) isn't an image Shot can read")
        }
        guard let after = ImageCodec.image(at: b) else {
            throw .data("\(b.lastPathComponent) isn't an image Shot can read")
        }
        let target: (url: URL, exact: Bool)
        if options.output != nil {
            target = try destination(for: b, output: options.output, extensions: ["png"], default: "png", command: "diff")
        } else {
            let candidate = b.deletingLastPathComponent().appendingPathComponent(b.deletingPathExtension().lastPathComponent + " diff.png")
            target = (FileManager.default.fileExists(atPath: candidate.path) ? VersionNaming.nextVersionURL(of: candidate) : candidate, false)
        }

        let width = after.width, height = after.height
        guard let old = pixels(of: before, width: width, height: height),
              let new = pixels(of: after, width: width, height: height)
        else {
            throw .internal("couldn't read the images' pixels")
        }
        let mask = ImageDiff.changes(old, new, width: width, height: height, bytesPerRow: width * 4, threshold: options.threshold)
        let changed = mask.reduce(0) { $0 + Int($1) }
        let regions = ImageDiff.regions(in: mask, width: width, height: height)
        let scale = ImageCodec.scale(ofFileAt: b)
        guard let image = highlight(after, mask: mask, regions: regions, lineWidth: 2 * max(scale, 1)),
              let data = ImageCodec.data(from: image, scale: scale, format: .png)
        else {
            throw .internal("couldn't draw the diff")
        }
        let temporary = temporaryURL(beside: target.url, pathExtension: "png")
        defer { try? FileManager.default.removeItem(at: temporary) }
        do {
            try data.write(to: temporary, options: .withoutOverwriting)
        } catch {
            throw .cantCreate("couldn't write in \(temporary.deletingLastPathComponent().path): \(error.localizedDescription)")
        }

        var object = try written(place(temporary, at: target))
        let listed = ImageDiff.largest(regions)
        object["a"] = .string(a.path)
        object["b"] = .string(b.path)
        object["threshold"] = .number(options.threshold)
        object["changedPixels"] = .number(Double(changed))
        // A share small enough to round to 0 still says something changed through changedPixels and regions.
        object["changed"] = .number((Double(changed) / Double(max(width * height, 1)) * 10000).rounded() / 10000)
        object["regions"] = .array(listed.map { .array($0.rect.map { .number(Double($0)) }) })
        if listed.count < regions.count {
            object["moreRegions"] = .number(Double(regions.count - listed.count))
        }
        if before.width != width || before.height != height {
            object["aSize"] = .object(["width": .number(Double(before.width)), "height": .number(Double(before.height))])
            object["note"] = .string("a is \(before.width)×\(before.height) and b is \(width)×\(height), so a was scaled to b's size to compare them")
        }
        return .object(object)
    }

    /// `image` drawn at `width` by `height`, read as 8-bit premultiplied sRGB RGBA, top row
    /// first, so both images are read alike whatever their colour space.
    package static func pixels(of image: CGImage, width: Int, height: Int) -> [UInt8]? {
        guard let canvas = CGContext.bitmap(width: width, height: height, format: .sRGB) else {
            return nil
        }
        canvas.interpolationQuality = .high
        canvas.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return canvas.makeBitmap().map { [UInt8]($0.pixels) }
    }

    /// `image` dimmed, with the pixels `mask` marks shown undimmed under a red tint, and each region boxed in red.
    static func highlight(_ image: CGImage, mask: [UInt8], regions: [ImageDiff.Region], lineWidth: CGFloat) -> CGImage? {
        let width = image.width, height = image.height
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        guard let canvas = CGContext.bitmap(width: width, height: height, format: .sRGB) else {
            return nil
        }
        let red = RGBA.presets[0]
        canvas.draw(image, in: bounds)
        canvas.setFillColor(RGBA(0, 0, 0, 0.6).cgColor)
        canvas.fill(bounds)
        canvas.saveGState()
        canvas.clip(to: changedPixels(mask, width: width, height: height))
        canvas.draw(image, in: bounds)
        canvas.setFillColor(RGBA(red.r, red.g, red.b, 0.45).cgColor)
        canvas.fill(bounds)
        canvas.restoreGState()
        canvas.setStrokeColor(red.cgColor)
        canvas.setLineWidth(lineWidth)
        for region in regions {
            // Top-left origin to the canvas's bottom-left, just outside the changed pixels so the box doesn't cover them.
            let rect = CGRect(x: region.x, y: height - region.y - region.height, width: region.width, height: region.height)
            canvas.stroke(CanvasPath(rect: rect.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2)))
        }
        return canvas.makeImage()
    }

    /// The pixels `mask` marks, top row first, as whole-pixel rects in a bottom-left-origin canvas, a run of them to a rect.
    static func changedPixels(_ mask: [UInt8], width: Int, height: Int) -> CanvasPath {
        var path = CanvasPath()
        for y in 0..<height {
            var x = 0
            while x < width {
                guard mask[y * width + x] != 0 else {
                    x += 1
                    continue
                }
                let start = x
                while x < width, mask[y * width + x] != 0 {
                    x += 1
                }
                path.addRect(CGRect(x: start, y: height - y - 1, width: x - start, height: 1))
            }
        }
        return path
    }
}
