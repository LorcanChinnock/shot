import Foundation
import Testing
@testable import ShotCore

private func live() -> AgentTools {
    AgentTools.live(
        folder: URL(fileURLWithPath: "/shots"), codec: StandInCodec(), canvasType: UnusedCanvas.self, reader: UnusedVideo(), assembler: UnusedVideo(),
        writer: UnusedVideo()
    )
}

@Test func theLiveToolsOfferEveryTool() {
    let names = live().server(version: "1.2.3").tools.map(\.name)
    #expect(names == AgentTools.definitions.map(\.name))
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
