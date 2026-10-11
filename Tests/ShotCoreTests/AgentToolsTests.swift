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
