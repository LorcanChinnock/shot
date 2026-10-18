#if canImport(CoreGraphics)
import CoreGraphics
import Foundation

extension ShotCommands {
    /// `shot diff`: reads both images into bytes at `b`'s size, finds the changes with ShotModel's `ImageDiff`, and
    /// writes a dimmed copy of `b` with the changed pixels lit and boxed, as a new file beside `b`.
    static func diff(_ options: ShotCommand.DiffOptions, codec: any ImageCoding) throws(ShotCommandError) -> JSONValue {
        let a = url(options.a), b = url(options.b)
        try requireInput(a)
        try requireInput(b)
        guard let before = codec.image(at: a) else {
            throw .data("\(a.lastPathComponent) isn't an image Shot can read")
        }
        guard let after = codec.image(at: b) else {
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
        guard let old = pixels(of: before, width: width, height: height), let new = pixels(of: after, width: width, height: height) else {
            throw .internal("couldn't read the images' pixels")
        }
        let mask = ImageDiff.changes(old, new, width: width, height: height, bytesPerRow: width * 4, threshold: options.threshold)
        let changed = mask.reduce(0) { $0 + Int($1) }
        let regions = ImageDiff.regions(in: mask, width: width, height: height)
        let scale = codec.scale(ofFileAt: b)
        guard let image = highlight(after, mask: mask, regions: regions, lineWidth: 2 * max(scale, 1)),
              let data = codec.data(from: image, scale: scale, format: .png)
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

        var object = try written(place(temporary, at: target), codec: codec)
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

    /// `image` drawn at `width` by `height` as 8-bit premultiplied sRGB RGBA, top row first, so both images are read
    /// alike whatever their colour space.
    static func pixels(of image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else {
                return false
            }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? bytes : nil
    }

    /// `image` dimmed, with the pixels `mask` marks shown undimmed under a red tint, and each region boxed in red.
    static func highlight(_ image: CGImage, mask: [UInt8], regions: [ImageDiff.Region], lineWidth: CGFloat) -> CGImage? {
        let width = image.width, height = image.height
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let alpha = Data(mask.map { $0 == 0 ? 0 : 255 })
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let provider = CGDataProvider(data: alpha as CFData),
              let changed = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        else {
            return nil
        }
        let red = RGBA.presets[0]
        context.draw(image, in: bounds)
        context.setFillColor(CGColor(gray: 0, alpha: 0.6))
        context.fill(bounds)
        context.saveGState()
        context.clip(to: bounds, mask: changed)
        context.draw(image, in: bounds)
        context.setFillColor(RGBA(red.r, red.g, red.b, 0.45).cgColor)
        context.fill(bounds)
        context.restoreGState()
        context.setStrokeColor(red.cgColor)
        context.setLineWidth(lineWidth)
        for region in regions {
            // Top-left origin to the context's bottom-left, just outside the changed pixels so the box doesn't cover them.
            let rect = CGRect(x: region.x, y: height - region.y - region.height, width: region.width, height: region.height)
            context.stroke(rect.insetBy(dx: -lineWidth / 2, dy: -lineWidth / 2))
        }
        return context.makeImage()
    }
}
#endif
