import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ShotCore

/// A black and white checkerboard of 4-pixel squares, which any blur or pixelation visibly changes.
private func checkerboard(width: Int = 200, height: Int = 120) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    for y in stride(from: 0, to: height, by: 4) {
        for x in stride(from: (y / 4) % 2 * 4, to: width, by: 8) {
            ctx.fill(CGRect(x: x, y: y, width: 4, height: 4))
        }
    }
    return ctx.makeImage()!
}

private func writeImage(_ name: String, in folder: URL, image: CGImage = checkerboard(), record: CaptureRecord? = nil) throws -> URL {
    let url = folder.appendingPathComponent(name)
    try #require(ImageCodec.data(from: image, scale: 1, format: ImageFormat(fileExtension: url.pathExtension), record: record)).write(to: url)
    return url
}

private func path(_ result: JSONValue) throws -> URL {
    URL(fileURLWithPath: try #require(result["path"]?.string))
}

/// The error `command` throws, or nil if it doesn't.
private func failure(_ command: ShotCommand) async -> ShotCommandError? {
    do {
        _ = try await ShotCommands.run(command)
        return nil
    } catch {
        return error
    }
}

@Test func infoDescribesAnImageAndTheRecordInIt() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let record = CaptureRecord(kind: "image", created: Date(timeIntervalSince1970: 1_791_640_992), size: .init(width: 200, height: 120), scale: 1, source: .init(mode: "area", app: "Notes"))
    let marked = try writeImage("marked.png", in: folder, record: record)
    let plain = try writeImage("plain.jpg", in: folder)

    let info = try await ShotCommands.run(.info(path: marked.path))
    #expect(info["kind"] == .string("image"))
    #expect(info["size"] == .object(["width": .number(200), "height": .number(120)]))
    #expect(info["scale"] == .number(1))
    #expect(info["record"]?["source"]?["app"] == .string("Notes"))
    #expect(info["record"]?["schema"] == .string("shot.capture/2"))
    let bare = try await ShotCommands.run(.info(path: plain.path))
    #expect(bare["record"] == nil)
    #expect((bare["bytes"]?.number ?? 0) > 0)
}

@Test func infoSaysWhenThereIsNothingToDescribe() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let text = folder.appendingPathComponent("notes.txt")
    try Data("hello".utf8).write(to: text)
    #expect(await failure(.info(path: folder.appendingPathComponent("missing.png").path))?.exitCode == 66)
    #expect(await failure(.info(path: text.path)) == .data("notes.txt isn't an image or video Shot can read"))
    #expect(await failure(.info(path: folder.path))?.exitCode == 65)
}

@Test func textReadsEachLineAndWordWithItsBox() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let image = try writeImage("dialog.png", in: folder, image: textImage(width: 600, height: 200, [("Save changes", 40, 60)]))
    let result = try await ShotCommands.run(.text(path: image.path))
    #expect(result["path"] == .string(image.path))
    #expect(result["size"] == .object(["width": .number(600), "height": .number(200)]))
    #expect(result["text"] == .string("Save changes"))
    guard case let .array(lines)? = result["lines"], let line = lines.first,
          case let .array(words)? = line["words"], case let .array(box)? = line["box"] else {
        Issue.record("no line with words and a box: \(result)")
        return
    }
    #expect(words.map { $0["text"] } == [.string("Save"), .string("changes")])
    #expect(box.count == 4)
    #expect((box[1].number ?? 0) >= 40 && (box[1].number ?? 0) <= 70)
    #expect(await failure(.text(path: folder.appendingPathComponent("missing.png").path))?.exitCode == 66)
}

@Test(arguments: [ShotCommand.RedactStyle.blur, .pixelate])
func redactHidesOnlyTheRectAndLeavesTheInputAlone(style: ShotCommand.RedactStyle) async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let input = try writeImage("shot.png", in: folder)
    let before = try Data(contentsOf: input)

    let result = try await ShotCommands.run(.redact(.init(input: input.path, rects: [[40, 40, 80, 40]], style: style)))
    let output = try path(result)
    #expect(output.lastPathComponent == "shot (2).png")
    #expect(try Data(contentsOf: input) == before)
    #expect(result["size"] == .object(["width": .number(200), "height": .number(120)]))
    let image = try #require(ImageCodec.image(at: output))
    let original = checkerboard()
    // Inside, neighbouring squares no longer alternate black and white; outside, they still do.
    let inside = try [pixel(image, 78, 58)[0], pixel(image, 82, 58)[0]]
    #expect(abs(inside[0] - inside[1]) < 0.5)
    #expect(try pixel(image, 10, 10) == pixel(original, 10, 10))
    #expect(try pixel(image, 14, 10) == pixel(original, 14, 10))
    let record = try #require(ImageCodec.record(ofFileAt: output))
    #expect(record.original == "shot.png")
    #expect(record.editable == true)
    #expect(record.annotations.map(\.type) == [style.rawValue])
    #expect(record.annotations.first?.rect == [40, 40, 80, 40])
}

@Test func blurAndPixelateLookDifferent() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let input = try writeImage("shot.png", in: folder)
    let blurred = try path(try await ShotCommands.run(.redact(.init(input: input.path, rects: [[0, 0, 200, 120]], style: .blur))))
    let pixelated = try path(try await ShotCommands.run(.redact(.init(input: input.path, rects: [[0, 0, 200, 120]], style: .pixelate))))
    #expect(try Data(contentsOf: blurred) != Data(contentsOf: pixelated))
}

@Test func aRectOffTheImageIsADataError() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let input = try writeImage("shot.png", in: folder)
    #expect(await failure(.redact(.init(input: input.path, rects: [[10, 10, 5, 5], [500, 500, 10, 10]]))) == .data("rect 2 (500,500,10,10) is off the 200×120 image"))
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["shot.png"])
}

@Test func annotateDrawsTheMarksAndRecordsThemToReopen() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let white = try #require(CGContext(data: nil, width: 200, height: 120, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    white.setFillColor(CGColor(gray: 1, alpha: 1))
    white.fill(CGRect(x: 0, y: 0, width: 200, height: 120))
    let input = try writeImage("shot.png", in: folder, image: try #require(white.makeImage()))
    let marksFile = folder.appendingPathComponent("marks.json")
    try Data(#"{"annotations":[{"type":"rectangle","rect":[20,20,60,40],"color":"red","lineWidth":4},{"type":"counter","center":[150,60],"number":2}]}"#.utf8).write(to: marksFile)

    let output = try path(try await ShotCommands.run(.annotate(.init(input: input.path, marks: .file(marksFile.path)))))
    let image = try #require(ImageCodec.image(at: output))
    let edge = try pixel(image, 20, 40)
    #expect(edge[0] > 0.85 && edge[1] < 0.45)
    #expect(try pixel(image, 50, 40)[1] > 0.95)
    let record = try #require(ImageCodec.record(ofFileAt: output))
    #expect(record.editable == true)
    let layers = try #require(record.editableLayers)
    #expect(layers.annotations.map(\.kind) == [.shape(.rectangle, rect: CGRect(x: 20, y: 20, width: 60, height: 40)), .counter(2, center: CGPoint(x: 150, y: 60))])

    let inline = try path(try await ShotCommands.run(.annotate(.init(input: input.path, marks: .marks([CaptureMark(type: "arrow", from: [10, 10], to: [100, 100])])))))
    #expect(inline.lastPathComponent == "shot (3).png")
}

@Test func annotateRefusesMarksItCantDraw() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let input = try writeImage("shot.png", in: folder)
    let bad = folder.appendingPathComponent("bad.json")
    try Data(#"[{"type":"arrow","from":[1,1]}]"#.utf8).write(to: bad)
    #expect(await failure(.annotate(.init(input: input.path, marks: .file(bad.path))))?.exitCode == 65)
    #expect(await failure(.annotate(.init(input: input.path, marks: .file(folder.appendingPathComponent("none.json").path))))?.exitCode == 66)
}

@Test func outputGoesWhereAskedButNeverOverAFile() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let input = try writeImage("shot.png", in: folder)
    let redact = { (output: String?) in ShotCommand.redact(.init(input: input.path, output: output, rects: [[0, 0, 10, 10]])) }
    let asked = folder.appendingPathComponent("out.jpg")
    #expect(try await path(ShotCommands.run(redact(asked.path))) == asked)
    #expect(ImageCodec.record(ofFileAt: asked) != nil)
    #expect(await failure(redact(asked.path)) == .cantCreate("\(asked.path) already exists, and shot never overwrites"))
    #expect(await failure(redact(folder.appendingPathComponent("nope/out.png").path))?.exitCode == 73)
    #expect(await failure(redact(folder.appendingPathComponent("out.tiff").path)) == .usage(nil, "-o \(folder.appendingPathComponent("out.tiff").path) must end in .png, .jpg, .jpeg"))
}

@Test func aNameTakenWhileWorkingMovesOnToTheNextVersion() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let taken = folder.appendingPathComponent("shot (2).png")
    try Data("someone else's".utf8).write(to: taken)
    let temporary = ShotCommands.temporaryURL(beside: taken, pathExtension: "png")
    try Data("mine".utf8).write(to: temporary)
    // As if the name was free when picked and taken before the move.
    let placed = try ShotCommands.place(temporary, at: (taken, false))
    #expect(placed.lastPathComponent == "shot (3).png")
    #expect(try Data(contentsOf: taken) == Data("someone else's".utf8))
    #expect(try Data(contentsOf: placed) == Data("mine".utf8))

    try Data("again".utf8).write(to: temporary)
    #expect(throws: ShotCommandError.cantCreate("\(taken.path) already exists, and shot never overwrites")) { try ShotCommands.place(temporary, at: (taken, true)) }
    #expect(try Data(contentsOf: taken) == Data("someone else's".utf8))
}

@Test func anImageThatIsntPNGOrJPEGComesOutAsPNG() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let tiff = folder.appendingPathComponent("scan.tiff")
    let destination = try #require(CGImageDestinationCreateWithURL(tiff as CFURL, "public.tiff" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, checkerboard(), nil)
    #expect(CGImageDestinationFinalize(destination))
    let output = try path(try await ShotCommands.run(.redact(.init(input: tiff.path, rects: [[0, 0, 10, 10]]))))
    #expect(output.lastPathComponent == "scan.png")
}

/// A white image with a black box at `box`, given top-left as `[x, y, width, height]`.
private func whiteWithBox(width: Int, height: Int, box: [Int]?) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    if let box {
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: box[0], y: height - box[1] - box[3], width: box[2], height: box[3]))
    }
    return ctx.makeImage()!
}

private func numbers(_ value: JSONValue?) -> [[Double]] {
    guard case let .array(items)? = value else { return [] }
    return items.map { item in
        guard case let .array(values) = item else { return [] }
        return values.compactMap(\.number)
    }
}

@Test func diffBoxesWhatChangedAndSavesANewFileBesideB() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let a = try writeImage("before.png", in: folder)
    // b is the checkerboard with one red box on it.
    let ctx = try #require(CGContext(data: nil, width: 200, height: 120, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.draw(checkerboard(), in: CGRect(x: 0, y: 0, width: 200, height: 120))
    ctx.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 40, y: 120 - 40 - 20, width: 30, height: 20))
    let b = try writeImage("after.png", in: folder, image: try #require(ctx.makeImage()))
    let (aBytes, bBytes) = (try Data(contentsOf: a), try Data(contentsOf: b))

    let result = try await ShotCommands.run(.diff(.init(a: a.path, b: b.path)))
    let output = try path(result)
    #expect(output.lastPathComponent == "after diff.png")
    #expect(numbers(result["regions"]) == [[40, 40, 30, 20]])
    #expect(result["changedPixels"] == .number(600))
    #expect(result["changed"] == .number(0.025))
    #expect(result["note"] == nil)
    #expect(result["size"] == .object(["width": .number(200), "height": .number(120)]))
    #expect(try Data(contentsOf: a) == aBytes && Data(contentsOf: b) == bBytes)

    // Outside the change, b is dimmed; inside, it shows through with a red tint.
    let image = try #require(ImageCodec.image(at: output))
    let pixels = try #require(ShotCommands.pixels(of: image, width: 200, height: 120))
    func rgb(_ x: Int, _ y: Int) -> [UInt8] { Array(pixels[(y * 200 + x) * 4 ..< (y * 200 + x) * 4 + 3]) }
    #expect(rgb(0, 0).allSatisfy { (60 ... 140).contains($0) }, "a white square dimmed: \(rgb(0, 0))")
    #expect(rgb(55, 50)[0] > 200 && rgb(55, 50)[1] < 120, "the change: \(rgb(55, 50))")

    #expect(try path(await ShotCommands.run(.diff(.init(a: a.path, b: b.path)))).lastPathComponent == "after diff (2).png")
}

@Test func imagesOfDifferentSizesAreComparedAtBsSize() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let a = try writeImage("small.png", in: folder, image: whiteWithBox(width: 100, height: 60, box: nil))
    let b = try writeImage("large.png", in: folder, image: whiteWithBox(width: 200, height: 120, box: [150, 10, 20, 30]))

    let result = try await ShotCommands.run(.diff(.init(a: a.path, b: b.path, threshold: 0)))
    #expect(numbers(result["regions"]) == [[150, 10, 20, 30]])
    #expect(result["aSize"] == .object(["width": .number(100), "height": .number(60)]))
    #expect(result["note"] == .string("a is 100×60 and b is 200×120, so a was scaled to b's size to compare them"))
    #expect(result["size"] == .object(["width": .number(200), "height": .number(120)]))
}

@Test func identicalImagesDifferNowhere() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let a = try writeImage("shot.png", in: folder)
    let result = try await ShotCommands.run(.diff(.init(a: a.path, b: a.path, threshold: 0)))
    #expect(result["changed"] == .number(0))
    #expect(numbers(result["regions"]).isEmpty)
    #expect(try path(result).lastPathComponent == "shot diff.png")
}

@Test func diffNeverOverwritesAndRefusesWhatItCantRead() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let a = try writeImage("a.png", in: folder)
    let text = folder.appendingPathComponent("notes.txt")
    try Data("hello".utf8).write(to: text)
    #expect(await failure(.diff(.init(a: a.path, b: a.path, output: a.path))) == .cantCreate("\(a.path) already exists, and shot never overwrites"))
    #expect(await failure(.diff(.init(a: a.path, b: a.path, output: folder.appendingPathComponent("d.jpg").path)))?.exitCode == 64)
    #expect(await failure(.diff(.init(a: text.path, b: a.path))) == .data("notes.txt isn't an image Shot can read"))
    #expect(await failure(.diff(.init(a: a.path, b: folder.appendingPathComponent("gone.png").path)))?.exitCode == 66)
    #expect(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)) == ["a.png", "notes.txt"])
}

/// What the command line and the MCP tools rely on: drawing needs no window and no main thread.
@Test func renderingWorksOffTheMainThreadWithTextBlurAndSpotlight() async throws {
    let image = checkerboard()
    let document = EditorDocument(base: image, annotations: [
        Annotation(kind: .text("Hello", origin: CGPoint(x: 10, y: 10), fontSize: 20), color: RGBA.presets[0], lineWidth: 4),
        Annotation(kind: .blur(CGRect(x: 100, y: 20, width: 60, height: 40)), color: RGBA.presets[0], lineWidth: 4),
        Annotation(kind: .spotlight(CGRect(x: 20, y: 60, width: 60, height: 40), style: SpotlightStyle()), color: RGBA.presets[0], lineWidth: 4),
    ])
    let flat = await Task.detached { flattenOffMain(document) }.value
    #expect(flat.onMain == false)
    let rendered = try #require(flat.image?.image)
    #expect(rendered.width == image.width && rendered.height == image.height)
    #expect(try pixel(rendered, 130, 40) != pixel(image, 130, 40) || pixel(rendered, 134, 40) != pixel(image, 134, 40))
}

private struct SendableFlat: @unchecked Sendable {
    let image: CGImage
}

private func flattenOffMain(_ document: EditorDocument) -> (onMain: Bool, image: SendableFlat?) {
    (Thread.isMainThread, AnnotationRenderer.flatten(document).map(SendableFlat.init))
}

extension MediaTests {
    @Test func gifAndTrimMakeNewFilesBesideTheVideo() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = folder.appendingPathComponent("rec.mp4")
        try await writeSyntheticVideo(to: video, seconds: 3, fps: 30, width: 640, height: 360)

        let gif = try await ShotCommands.run(.gif(.init(input: video.path, fps: 10, width: 320, start: 1, end: 2)))
        #expect(try path(gif).lastPathComponent == "rec.gif")
        #expect(abs((gif["frames"]?.number ?? 0) - 10) <= 1)
        #expect(gif["truncated"] == .bool(false))
        #expect(gif["size"]?["width"] == .number(320))
        let again = try await ShotCommands.run(.gif(.init(input: video.path, fps: 5)))
        #expect(try path(again).lastPathComponent == "rec (2).gif")

        let trimmed = try await ShotCommands.run(.trim(.init(input: video.path, start: 0.5, end: 2)))
        #expect(try path(trimmed).lastPathComponent == "rec (2).mp4")
        #expect(abs((trimmed["duration"]?.number ?? 0) - 1.5) < 0.1)
        let mov = folder.appendingPathComponent("short.mov")
        let asMov = try await ShotCommands.run(.trim(.init(input: video.path, output: mov.path, start: 0, end: 1)))
        #expect(try path(asMov) == mov)
        #expect(try await AVURLAsset(url: mov).load(.duration).seconds > 0.5)

        let info = try await ShotCommands.run(.info(path: video.path))
        #expect(info["kind"] == .string("video"))
        #expect(abs((info["duration"]?.number ?? 0) - 3) < 0.1)
        #expect(info["size"] == .object(["width": .number(640), "height": .number(360)]))
    }

    @Test func aStartPastTheEndOrAnImageIsRefused() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = folder.appendingPathComponent("rec.mp4")
        try await writeSyntheticVideo(to: video, seconds: 1, fps: 30, width: 320, height: 240)
        let image = try writeImage("shot.png", in: folder)
        #expect(await failure(.trim(.init(input: video.path, start: 5, end: 6)))?.exitCode == 64)
        #expect(await failure(.gif(.init(input: image.path))) == .data("shot.png isn't a video Shot can read"))
        #expect(await failure(.trim(.init(input: video.path, output: folder.appendingPathComponent("x.avi").path, start: 0, end: 1)))?.exitCode == 64)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)) == ["rec.mp4", "shot.png"])
    }
}

/// A video of flat gray scenes, one `levels` value a second, so each second starts a new scene.
private func writeScenes(to url: URL, levels: [UInt8], fps: Int32 = 10) async throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 180])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180,
    ])
    writer.add(input)
    writer.startWriting()
    writer.startSession(atSourceTime: .zero)
    for frame in 0 ..< Int(fps) * levels.count {
        try await waitUntilReady(input, of: writer)
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
        let pixels = try #require(buffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        memset(CVPixelBufferGetBaseAddress(pixels), Int32(levels[frame / Int(fps)]), CVPixelBufferGetDataSize(pixels))
        CVPixelBufferUnlockBaseAddress(pixels, [])
        adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
    }
    input.markAsFinished()
    await writer.finishWriting()
    #expect(writer.status == .completed)
}

extension MediaTests {
    @Test func framesFindEachSceneAndWriteThemToANewFolder() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = folder.appendingPathComponent("rec.mp4")
        try await writeScenes(to: video, levels: [30, 30, 140, 140, 230, 230])

        let times = try await KeyFrameExtractor.changeTimes(in: video, duration: 6, count: 4)
        #expect(times.count == 4)
        // The first frame, one just after each change at 2 s and 4 s, and the last.
        #expect(times[0] < 0.3)
        #expect((2 ... 2.6).contains(times[1]))
        #expect((4 ... 4.6).contains(times[2]))
        #expect(times[3] > 5.5)

        let result = try await ShotCommands.run(.frames(.init(input: video.path, count: 4, width: 160)))
        let written = try path(result)
        #expect(written.lastPathComponent == "rec frames")
        let frames = try #require(result["frames"].flatMap { if case let .array(frames) = $0 { frames } else { nil } })
        #expect(frames.count == 4)
        #expect(frames.first?["size"] == .object(["width": .number(160), "height": .number(90)]))
        let names = try FileManager.default.contentsOfDirectory(atPath: written.path).sorted()
        #expect(names.count == 4 && names[0].hasPrefix("01 0.") && names.allSatisfy { $0.hasSuffix("s.jpg") })
        // Each frame shows its scene's gray.
        var grays: [Int] = []
        for frame in frames {
            let file = URL(fileURLWithPath: try #require(frame["path"]?.string))
            let image = try #require(ImageCodec.image(at: file))
            grays.append(try grayLevel(of: image))
        }
        // Dark, middle, light, light; an encode shifts the levels a little, so only their order is exact.
        #expect(grays.count == 4 && grays[0] < 70 && (100 ... 190).contains(grays[1]) && grays[2] > 200 && abs(grays[2] - grays[3]) < 10)

        let again = try await ShotCommands.run(.frames(.init(input: video.path, every: 2)))
        #expect(try path(again).lastPathComponent == "rec frames (2)")
        #expect(again["frames"].flatMap { if case let .array(frames) = $0 { frames.count } else { nil } } == 3)
        #expect(await failure(.frames(.init(input: video.path, output: written.path)))?.exitCode == 73)
        #expect(await failure(.frames(.init(input: video.path, every: 0.05)))?.exitCode == 64)
    }

    @Test func getFramesReturnsTheirTimesAndImages() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let video = folder.appendingPathComponent("Recording.mp4")
        try await writeScenes(to: video, levels: [30, 230])
        let result = await AgentTools.live(folder: folder).call("get_frames", .object(["count": .number(2)]))
        #expect(result.isError == false)
        let images = result.content.filter { if case .image = $0 { true } else { false } }
        #expect(images.count == 2)
        #expect(result.content.compactMap { if case let .text(text) = $0 { text } else { nil } }.dropFirst().allSatisfy { $0.hasPrefix("t=") })
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["Recording.mp4"])
    }

    @Test func getFramesShowsTheFrameAtEachMarkWithItsLabel() async throws {
        let folder = try temporaryFolder()
        let store = try temporaryFolder().appendingPathComponent("recording-marks.json")
        defer {
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: store.deletingLastPathComponent())
        }
        let video = folder.appendingPathComponent("Recording.mp4")
        try await writeScenes(to: video, levels: [30, 130, 230])
        try RecordingMarks.save([RecordingMark(time: 1.5, label: "tapped Login")], for: video, in: store)
        let result = await AgentTools.live(folder: folder, marks: store).call("get_frames", .object(["count": .number(2)]))
        #expect(result.isError == false)
        let lines = result.content.compactMap { if case let .text(text) = $0 { text } else { nil } }.dropFirst()
        #expect(lines.count == 3)
        #expect(lines.filter { $0.hasSuffix(#", marked "tapped Login""#) }.count == 1)
        #expect(lines.contains { $0.hasPrefix("t=1.5s of 3.0s, marked") })
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["Recording.mp4"])
    }
}

@Test func recordingMarksAreKeptByPathAndForgottenWithTheirFile() throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = folder.appendingPathComponent("Support/recording-marks.json")
    let kept = folder.appendingPathComponent("kept.mp4")
    let gone = folder.appendingPathComponent("gone.mp4")
    try Data().write(to: kept)
    try Data().write(to: gone)
    #expect(RecordingMarks.marks(for: kept, in: store).isEmpty)
    let marks = [RecordingMark(time: 1, label: "a"), RecordingMark(time: 2, label: "b")]
    try RecordingMarks.save(marks, for: kept, in: store)
    try RecordingMarks.save([RecordingMark(time: 3, label: "c")], for: gone, in: store)
    #expect(RecordingMarks.marks(for: URL(fileURLWithPath: folder.path + "/./kept.mp4"), in: store) == marks)
    try FileManager.default.removeItem(at: gone)
    try RecordingMarks.save([], for: folder.appendingPathComponent("other.mp4"), in: store)
    let saved = try JSONDecoder().decode([String: [RecordingMark]].self, from: Data(contentsOf: store))
    #expect(saved == [kept.standardizedFileURL.path: marks])
}
