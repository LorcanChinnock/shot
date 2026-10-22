import CoreGraphics
import Foundation
import Testing
@testable import ShotCore

@Test func theRepliesLabelQuotesAndMarkdownAreDropped() {
    #expect(AltText.cleaned("Alt text: \"A **Settings** window with Open at login turned off.\"\n") == "A Settings window with Open at login turned off.")
    #expect(AltText.cleaned("“The Shot editor.”") == "The Shot editor.")
    #expect(AltText.cleaned("A dialog.\n\nIt says Save failed.") == "A dialog. It says Save failed.")
    #expect(AltText.cleaned("It's Jane's \"Inbox\"") == "It's Jane's \"Inbox\"")
}

@Test func aLargeImageIsScaledToTheLongEdgeAndASmallOneIsLeftAlone() throws {
    let big = try #require(CGContext.bitmap(width: 3000, height: 1500, format: .sRGB)?.makeImage())
    let scaled = AltText.scaled(big, toLongEdge: 1536)
    #expect(scaled.width == 1536 && scaled.height == 768)
    let small = try #require(CGContext.bitmap(width: 800, height: 600, format: .sRGB)?.makeImage())
    #expect(AltText.scaled(small, toLongEdge: 1536) === small)
}

@Test func theAltTextRequestAsksForPlainShortText() {
    let request = ImageRequest.altText
    #expect(request.instructions.contains("one or two plain sentences"))
    #expect(request.maxLongEdge == 1536)
}
