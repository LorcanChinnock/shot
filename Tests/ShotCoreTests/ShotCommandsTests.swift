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
