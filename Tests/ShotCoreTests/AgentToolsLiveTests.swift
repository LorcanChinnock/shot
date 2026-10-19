import Foundation
import Testing
@testable import ShotCore

private func live() -> AgentTools {
    AgentTools.live(
        folder: URL(fileURLWithPath: "/shots"), codec: StandInCodec(), canvasType: UnusedCanvas.self, reader: UnusedVideo(), assembler: UnusedVideo(),
        writer: UnusedVideo()
    )
}

@Test func findTextIsOfferedOnlyWhereTextCanBeRead() {
    let names = live().server(version: "1.2.3").tools.map(\.name)
    #if canImport(CoreGraphics) && canImport(Vision)
    #expect(names == AgentTools.definitions.map(\.name))
    #else
    #expect(names == AgentTools.definitions.map(\.name).filter { $0 != "find_text" })
    #endif
}

@Test func theToolsSearchTheTextIndexTheyreGiven() {
    var index = TextIndex()
    index.set("Invoice total", for: TextIndex.File(path: "/shots/Shot.png", bytes: 100, modified: .distantPast))
    let read = index
    let tools = AgentTools.live(
        folder: URL(fileURLWithPath: "/shots"), textIndex: { read }, codec: StandInCodec(), canvasType: UnusedCanvas.self, reader: UnusedVideo(),
        assembler: UnusedVideo(), writer: UnusedVideo()
    )
    #expect(tools.textIndex() == read)
    #expect(live().textIndex() == TextIndex())
}

#if !(canImport(CoreGraphics) && canImport(Vision))
@Test func readingTextSaysItNeedsAMac() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("Shot.png")
    try Data().write(to: file)
    let codec = StandInCodec(image: BitmapImage(try #require(Bitmap(width: 1, height: 1, pixels: Data(count: 4)))))
    await #expect(throws: ShotCommandError.unavailable("reading the text in an image needs a Mac")) {
        try await ShotCommands.run(.text(path: file.path), codec: codec, canvasType: UnusedCanvas.self, reader: UnusedVideo(), assembler: UnusedVideo(), writer: UnusedVideo())
    }
    let redact = ShotCommand.RedactOptions(input: file.path, detect: [.email])
    await #expect(throws: ShotCommandError.unavailable("reading the text in an image needs a Mac")) {
        try await ShotCommands.run(.redact(redact), codec: codec, canvasType: UnusedCanvas.self, reader: UnusedVideo(), assembler: UnusedVideo(), writer: UnusedVideo())
    }
}
#endif
