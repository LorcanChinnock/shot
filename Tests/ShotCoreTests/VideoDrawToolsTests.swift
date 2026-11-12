import Testing
@testable import ShotCore

@Test func videoDrawToolsListEveryDrawingToolThenAddImageThenCrop() {
    #expect(VideoDrawTools.drawing == [
        .tool(.select), .tool(.arrow), .tool(.line), .tool(.shape), .tool(.pen), .tool(.text), .tool(.note),
        .tool(.highlight), .tool(.spotlight), .tool(.redact), .tool(.counter), .addImage,
    ])
    #expect(VideoDrawTools.afterDivider == [.cropVideo])
    #expect(VideoDrawTools.all.count == 13)
}

@Test func videoDrawToolsMatchTheImageEditorsGroup() {
    let tools = VideoDrawTools.all.compactMap { button -> EditorTool? in
        if case let .tool(tool) = button { tool } else { nil }
    }
    #expect(tools == EditorToolbarLayout.drawingTools)
    // Crop is a button of its own, since the video editor's crop isn't a drawing tool, and the hand has none.
    #expect(!tools.contains(.crop))
    #expect(!tools.contains(.hand))
}

@Test func videoDrawToolsShowOnlyCropsKey() {
    #expect(VideoDrawTools.key(for: .cropVideo) == "C")
    for button in VideoDrawTools.drawing {
        #expect(VideoDrawTools.key(for: button) == nil)
    }
}

@Test func videoDrawToolsSelectCropWhileCropping() {
    #expect(VideoDrawTools.selected(tool: nil, cropping: true) == .cropVideo)
    #expect(VideoDrawTools.selected(tool: .arrow, cropping: true) == .cropVideo)
    #expect(VideoDrawTools.selected(tool: .arrow, cropping: false) == .tool(.arrow))
    #expect(VideoDrawTools.selected(tool: .hand, cropping: false) == nil)
    #expect(VideoDrawTools.selected(tool: nil, cropping: false) == nil)
}
