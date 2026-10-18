import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

/// Opaque stripes of four colours, 8 pixels wide, so a crop, scale or shift shows in any pixel.
private func stripes(width: Int = 200, height: Int = 120, alpha: Bool = false) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let colors: [(CGFloat, CGFloat, CGFloat)] = [(1, 0, 0), (0, 1, 0), (0, 0, 1), (1, 1, 0)]
    for x in stride(from: 0, to: width, by: 8) {
        let c = colors[(x / 8) % colors.count]
        ctx.setFillColor(CGColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1))
        ctx.fill(CGRect(x: x, y: 0, width: 8, height: height))
    }
    if alpha {
        ctx.clear(CGRect(x: 0, y: 0, width: 10, height: 10))
    }
    return ctx.makeImage()!
}

private func writeImage(_ name: String, in folder: URL, image: CGImage = stripes(), scale: CGFloat = 1, windowShadow: Bool = false) throws -> URL {
    let url = folder.appendingPathComponent(name)
    try #require(ImageCodec.data(from: image, scale: scale, format: ImageFormat(fileExtension: url.pathExtension), windowShadow: windowShadow)).write(to: url)
    return url
}

private func edit(_ input: URL, _ edit: ImageEdit, output: String? = nil, projects: ProjectStore? = nil) async throws(ShotCommandError) -> JSONValue {
    try await ShotCommands.run(.edit(ShotCommand.EditOptions(input: input.path, output: output, spec: .edit(edit))), projects: projects)
}

private func path(_ result: JSONValue) throws -> URL {
    URL(fileURLWithPath: try #require(result["path"]?.string))
}

private func failure(_ input: URL, _ spec: ImageEdit, output: String? = nil) async -> ShotCommandError? {
    do {
        _ = try await edit(input, spec, output: output)
        return nil
    } catch {
        return error
    }
}

/// Every pixel of `image`, drawn into one sRGB bitmap so two images compare however they were decoded.
private func rgba(_ image: CGImage) throws -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let ctx = try #require(CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return bytes
}

/// The version at `url` as the editor reopens it from `store`: its original with the layers on.
private func reopen(_ url: URL, in store: ProjectStore) throws -> EditorDocument {
    let saved = try #require(VersionWriter.layers(of: url, in: store))
    var document = EditorDocument(base: try #require(ImageCodec.image(at: saved.original)))
    document.restore(saved.layers)
    return document
}

@Test func everyStyleAndBorderTheSpecNamesIsTheEditors() {
    #expect(ImageEdit.shadows.allSatisfy { ShadowPreset(rawValue: $0) != nil })
    #expect(ImageEdit.shadows.count == ShadowPreset.allCases.count)
    #expect(ImageEdit.borders.allSatisfy { Border.Kind(rawValue: $0) != nil })
}

@Test func anEditReopensWithEveryLayerLiveAndDrawsTheSame() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ProjectStore(folder: folder.appendingPathComponent("Projects"))
    let input = try writeImage("shot.png", in: folder)
    let other = try writeImage("other.png", in: folder, image: stripes(width: 40, height: 30))
    let spec = ImageEdit(
        pad: [20, 30, 20, 30], background: "white",
        style: ImageEdit.Style(shadow: "soft", border: ImageEdit.Border(type: "solid", width: 4, color: "black"), corners: 8),
        marks: [CaptureMark(type: "rectangle", rect: [20, 20, 60, 40], color: "red")],
        place: [ImageEdit.Placement(path: other.path, at: [150, 80])]
    )

    let result = try await edit(input, spec, projects: store)
    let output = try path(result)
    #expect(output.lastPathComponent == "shot (2).png")
    let entry = try #require(store.entry(for: output))
    #expect(entry.origin.via == .cli)
    #expect(entry.origin.action == "edit")

    // Reopened as the editor does, the layers draw exactly what was saved.
    let reopened = try reopen(output, in: store)
    let saved = try #require(ImageCodec.image(at: output))
    let redrawn = try #require(AnnotationRenderer.flatten(reopened))
    #expect(redrawn.width == saved.width && redrawn.height == saved.height)
    #expect(try rgba(redrawn) == rgba(saved))

    // And they're the editor's own: the shadow preset, the border, the corners, the background, a mark and a placed image.
    #expect(reopened.captureStyle.shadow == ShadowPreset.soft.shadow(scale: 1))
    #expect(reopened.captureStyle.border == Border(kind: .solid, lineWidth: 4, color: RGBA.presets[5]))
    #expect(reopened.captureCornerRadius == 8)
    #expect(reopened.background == RGBA(1, 1, 1))
    #expect(reopened.contentRect.contains(CGRect(x: -30, y: -20, width: 260, height: 160)))
    #expect(reopened.annotations.map(\.kind).first == .shape(.rectangle, rect: CGRect(x: 20, y: 20, width: 60, height: 40)))
    guard case let .image(_, rect) = try #require(reopened.annotations.last).kind else {
        Issue.record("the placed image isn't the last layer")
        return
    }
    #expect(rect == CGRect(x: 150, y: 80, width: 40, height: 30))

    // The result lists each layer by id and type, as the record does, so a later edit can remove one.
    let record = try #require(ImageCodec.record(ofFileAt: output))
    #expect(result["layers"] == .array(record.annotations.map { .object(["id": .string($0.id ?? ""), "type": .string($0.type)]) }))
    #expect(record.annotations.map(\.type) == ["rectangle", "image"])
    #expect(record.editable == false)
}

@Test func removeDeletesLayersFromAnEarlierEditByTheirIDs() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ProjectStore(folder: folder.appendingPathComponent("Projects"))
    let input = try writeImage("shot.png", in: folder)
    let first = try await edit(input, ImageEdit(marks: [
        CaptureMark(type: "arrow", from: [10, 10], to: [80, 60]), CaptureMark(type: "counter", center: [150, 60], number: 1),
    ]), projects: store)
    guard case let .array(layers)? = first["layers"], let arrow = layers.first?["id"]?.string else {
        Issue.record("the first edit listed no layers")
        return
    }

    let second = try await edit(try path(first), ImageEdit(marks: [CaptureMark(type: "rectangle", rect: [5, 5, 10, 10])], remove: [arrow.lowercased()]), projects: store)
    let reopened = try reopen(try path(second), in: store)
    #expect(reopened.annotations.map(\.kind) == [.counter(1, center: CGPoint(x: 150, y: 60)), .shape(.rectangle, rect: CGRect(x: 5, y: 5, width: 10, height: 10))])
    #expect(try reopen(try path(first), in: store).annotations.count == 2)

    // An id the version doesn't have names the entry; the input, a flat file, has none.
    let message = "remove[0]: shot.png has no layer \(arrow); its record lists each layer's id"
    #expect(await failure(input, ImageEdit(remove: [arrow])) == .data(message))
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["Projects", "shot (2).png", "shot (3).png", "shot.png"])
}

@Test func annotateAndCropAreEditsWithOnlyTheirOwnField() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let input = try writeImage("shot.png", in: folder)
    let marks = [CaptureMark(type: "arrow", from: [10, 10], to: [100, 100]), CaptureMark(type: "text", rect: [20, 60, 0, 0], text: "here")]

    let annotated = try path(try await ShotCommands.run(.annotate(.init(input: input.path, marks: .marks(marks)))))
    let edited = try path(try await edit(input, ImageEdit(marks: marks)))
    #expect(try rgba(#require(ImageCodec.image(at: annotated))) == rgba(#require(ImageCodec.image(at: edited))))
    var a = try #require(ImageCodec.record(ofFileAt: annotated)), b = try #require(ImageCodec.record(ofFileAt: edited))
    // Each mark gets a new id and the record its own time; the rest is the same.
    for index in a.annotations.indices {
        a.annotations[index].id = nil
        b.annotations[index].id = nil
    }
    b.created = a.created
    #expect(a == b)

    let cropped = try path(try await ShotCommands.run(.crop(.init(input: input.path, rect: [4, 8, 40, 20]))))
    let editCropped = try path(try await edit(input, ImageEdit(crop: [4, 8, 40, 20])))
    #expect(try rgba(#require(ImageCodec.image(at: cropped))) == rgba(#require(ImageCodec.image(at: editCropped))))
    #expect(ImageCodec.record(ofFileAt: editCropped)?.crop == [4, 8, 40, 20])
}

@Test func padThenCropCanKeepPartOfThePadding() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let input = try writeImage("shot.png", in: folder)

    let output = try path(try await edit(input, ImageEdit(crop: [-20, -20, 40, 40], pad: [20, 20, 20, 20], background: "#0000FF")))
    let image = try #require(ImageCodec.image(at: output))
    #expect(image.width == 40 && image.height == 40)
    #expect(try pixelBytes(image, 2, 2) == [0, 0, 255, 255])
    #expect(try pixelBytes(image, 22, 22) == [255, 0, 0, 255])
    #expect(ImageCodec.record(ofFileAt: output)?.crop == [-20, -20, 40, 40])

    #expect(await failure(input, ImageEdit(crop: [300, 0, 10, 10], pad: [20, 20, 20, 20])) == .data("crop (300,0,10,10) is off the 240×160 canvas"))
}

@Test func scaleTo1xHalvesARetinaImageWithItsMarksAndKeepsThemFlat() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = ProjectStore(folder: folder.appendingPathComponent("Projects"))
    let input = try writeImage("shot.png", in: folder, scale: 2)

    let output = try path(try await edit(input, ImageEdit(marks: [CaptureMark(type: "rectangle", rect: [20, 20, 40, 40])], scale: "1x"), projects: store))
    let image = try #require(ImageCodec.image(at: output))
    #expect(image.width == 100 && image.height == 60)
    #expect(ImageCodec.scale(ofFileAt: output) == 1)
    let record = try #require(ImageCodec.record(ofFileAt: output))
    #expect(record.scale == 1)
    #expect(record.annotations.first?.rect == [10, 10, 20, 20])
    #expect(record.editable == false)
    // Its pixels are no longer its layers', so it keeps only who made it.
    #expect(store.entry(for: output)?.origin.action == "edit")
    #expect(VersionWriter.layers(of: output, in: store) == nil)

    // A 1× image is already one pixel per point.
    let flat = try writeImage("flat.png", in: folder)
    let same = try #require(ImageCodec.image(at: try path(try await edit(flat, ImageEdit(scale: "1x")))))
    #expect(same.width == 200 && same.height == 120)
}

@Test func formatPicksTheExtensionAndMustAgreeWithTheOutput() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let input = try writeImage("shot.png", in: folder)

    let jpeg = try path(try await edit(input, ImageEdit(pad: [10, 10, 10, 10], format: .jpeg)))
    #expect(jpeg.pathExtension == "jpg")
    let image = try #require(ImageCodec.image(at: jpeg))
    // JPEG has no transparency, so the padding is white.
    #expect(try pixelBytes(image, 1, 1).prefix(3).allSatisfy { $0 > 250 })

    let png = folder.appendingPathComponent("out.png").path
    #expect(await failure(input, ImageEdit(format: .jpeg), output: png) == .usage(nil, "-o \(png) isn't a JPEG, the format the edit asks for"))
    #expect(await failure(input, ImageEdit(background: "none", format: .jpeg)) == .data("background none needs a PNG: a JPEG has no transparency"))
}

@Test func styleTheImageCantHaveIsRefused() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let opaque = try writeImage("shot.png", in: folder)
    let window = try writeImage("window.png", in: folder, image: stripes(alpha: true), windowShadow: true)

    #expect(await failure(opaque, ImageEdit(style: ImageEdit.Style(border: ImageEdit.Border(type: "outline")))) == .data("style.border: shot.png has no see-through pixels to outline; use solid or hairline"))
    #expect(await failure(window, ImageEdit(style: ImageEdit.Style(shadow: "soft"))) == .data("style: window.png is a window captured with the macOS shadow, which takes no shadow, border or corners of its own"))
    // Taking style off a window is fine, since it has none.
    _ = try await edit(window, ImageEdit(style: ImageEdit.Style(shadow: "none"), marks: [CaptureMark(type: "counter", center: [50, 50])]))

    let missing = folder.appendingPathComponent("gone.png").path
    #expect(await failure(opaque, ImageEdit(place: [ImageEdit.Placement(path: missing)])) == .noInput("place[0]: \(missing) doesn't exist"))
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["shot.png", "window (2).png", "window.png"])
}

@Test func theEditCanComeAsJSONFromAFileOrTheCommandLine() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let input = try writeImage("shot.png", in: folder)
    let file = folder.appendingPathComponent("edit.json")
    try Data(#"{"crop": [0, 0, 50, 50]}"#.utf8).write(to: file)

    let fromFile = try await ShotCommands.run(.edit(.init(input: input.path, spec: .file(file.path))))
    #expect(fromFile["size"] == .object(["width": .number(50), "height": .number(50)]))
    let inline = try await ShotCommands.run(.edit(.init(input: input.path, spec: .json(#"{"pad": 5}"#))))
    #expect(inline["size"] == .object(["width": .number(210), "height": .number(130)]))
    do {
        _ = try await ShotCommands.run(.edit(.init(input: input.path, spec: .json(#"{"pad": "lots"}"#))))
        Issue.record("a bad edit was made")
    } catch {
        #expect(error.exitCode == 65)
        #expect(error.message.hasPrefix("pad must be"))
    }
}
