import Foundation
import Testing
@testable import ShotCore

private func texts(_ result: MCPServer.ToolResult) -> [String] {
    result.content.compactMap { if case let .text(text) = $0 { text } else { nil } }
}

private func images(_ result: MCPServer.ToolResult) -> [Data] {
    result.content.compactMap { if case let .image(data, "image/jpeg") = $0 { Data(base64Encoded: data) } else { nil } }
}

/// Writes a PNG of `width`×`height` to `name` in `folder`, created `minutesAgo`.
private func writeCapture(_ name: String, in folder: URL, width: Int = 64, height: Int = 48, minutesAgo: Double) throws {
    let url = folder.appendingPathComponent(name)
    try #require(ImageCodec.data(from: solidImage(width: width, height: height), scale: 1)).write(to: url)
    try FileManager.default.setAttributes([.creationDate: Date().addingTimeInterval(-minutesAgo * 60)], ofItemAtPath: url.path)
}

@Test func liveToolsReadTheFolderAndPreferTheEditedVersion() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    try writeCapture("Shot X.png", in: folder, minutesAgo: 10)
    let record = CaptureRecord(original: "Shot X.png", kind: "image", created: Date(), size: .init(width: 64, height: 48), scale: 1, annotations: [CaptureMark(type: "counter", center: [10, 10], number: 1)])
    let marked = folder.appendingPathComponent("Shot X (2).png")
    try #require(ImageCodec.data(from: solidImage(width: 64, height: 48), scale: 1, record: record)).write(to: marked)
    try FileManager.default.setAttributes([.creationDate: Date().addingTimeInterval(-5 * 60)], ofItemAtPath: marked.path)
    try Data("notes".utf8).write(to: folder.appendingPathComponent("notes.txt"))

    let tools = AgentTools.live(folder: folder)
    #expect(Set(tools.entries().map(\.name)) == ["Shot X.png", "Shot X (2).png"])
    let result = await tools.call("latest_capture", .object([:]))
    #expect(result.isError == false)
    let preview = try #require(images(result).first)
    let image = try #require(ImageCodec.image(from: preview))
    #expect(image.width == 64 && image.height == 48)
    #expect(texts(result).first?.contains(#""name" : "Shot X (2).png""#) == true)
    #expect(texts(result).last == record.summaryLines.joined(separator: "\n"))
}

@Test func aLargeImagesPreviewSaysWhichSizeTheMarkupUses() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    try writeCapture("Shot Big.png", in: folder, width: 3136, height: 1000, minutesAgo: 1)
    let result = await AgentTools.live(folder: folder).call("latest_capture", .object([:]))
    #expect(texts(result).first == "The preview is 1568×500 pixels. The file is 3136×1000, which is what the marks' coordinates are in.")
}

@Test func anUnreadableImageSaysSoInsteadOfFailing() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    try Data("not a png".utf8).write(to: folder.appendingPathComponent("Broken.png"))
    let result = await AgentTools.live(folder: folder).call("latest_capture", .object([:]))
    #expect(result.isError == false)
    #expect(texts(result).first == "Couldn't read Broken.png as an image.")
}

extension MediaTests {
    @Test func aRecordingGivesAPosterFrameAndItsDuration() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try await writeSolidVideo(to: folder.appendingPathComponent("Recording.mp4"), color: .green, size: CGSize(width: 320, height: 180), seconds: 2)
        let result = await AgentTools.live(folder: folder).call("latest_capture", .object(["kind": .string("video")]))
        let jpeg = try #require(images(result).first)
        let poster = try #require(ImageCodec.image(from: jpeg))
        #expect(poster.width == 320 && poster.height == 180)
        #expect(texts(result).first == "A recording 2.0 seconds long, 320×180, without sound. The image is its frame at 1.0 seconds.")
        #expect(texts(result).count == 2)
    }
}

@Test func theLiveAnnotateToolWritesANewVersionBesideTheCapture() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    try writeCapture("Shot Y.png", in: folder, width: 100, height: 80, minutesAgo: 1)
    let marks: JSONValue = .array([.object(["type": .string("ellipse"), "rect": .array([10, 10, 50, 30].map(JSONValue.number)), "color": .string("blue")])])
    let result = await AgentTools.live(folder: folder).call("annotate", .object(["annotations": marks]))
    #expect(result.isError == false)
    #expect(images(result).count == 1)
    let written = folder.appendingPathComponent("Shot Y (2).png")
    #expect(FileManager.default.fileExists(atPath: written.path))
    #expect(ImageCodec.record(ofFileAt: written)?.annotations.first?.type == "ellipse")
    #expect(texts(result).last == "Saved as a new file beside Shot Y.png; the original is unchanged.")
}

@Test func theLiveZoomToolShowsAPartAtFullResolutionAndWritesNothing() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    try writeCapture("Shot Z.png", in: folder, width: 3136, height: 1000, minutesAgo: 1)
    let tools = AgentTools.live(folder: folder)

    let part = await tools.call("zoom", .object(["rect": .array([100, 50, 300, 200].map(JSONValue.number))]))
    #expect(part.isError == false)
    let image = try #require(images(part).first.flatMap(ImageCodec.image(from:)))
    #expect(image.width == 300 && image.height == 200)
    #expect(texts(part) == ["This is [100, 50, 300, 200] of Shot Z.png, which is 3136×1000 pixels, at full resolution: add 100 to x and 50 to y for the file's pixels."])

    let whole = await tools.call("zoom", .object(["rect": .array([0, 0, 3136, 1000].map(JSONValue.number))]))
    let scaled = try #require(images(whole).first.flatMap(ImageCodec.image(from:)))
    #expect(scaled.width == 1568 && scaled.height == 500)
    #expect(texts(whole).first?.contains("scaled to 1568×500 to fit: divide by 0.5,") == true)

    let off = await tools.call("zoom", .object(["rect": .array([4000, 0, 10, 10].map(JSONValue.number))]))
    #expect(off.isError)
    #expect(texts(off) == ["rect [4000, 0, 10, 10] is off Shot Z.png, which is 3136×1000 pixels."])
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["Shot Z.png"])
}
