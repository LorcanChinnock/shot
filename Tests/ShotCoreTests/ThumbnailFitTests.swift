import CoreGraphics
import Testing
@testable import ShotCore

private let tile = CGSize(width: 160, height: 120)
/// The Quick Access card at its shortest, which a strip gets.
private let card = CGSize(width: 280, height: 158)

@Test func oneRowOfAWindowShowsWhole() {
    // The QA capture behind #1372: the Balance row with its heading, which filled to a blank middle.
    #expect(ThumbnailFit.showsWhole(CGSize(width: 494, height: 140), in: tile))
    #expect(ThumbnailFit.showsWhole(CGSize(width: 494, height: 140), in: card))
}

@Test func ordinaryCapturesFill() {
    #expect(!ThumbnailFit.showsWhole(CGSize(width: 1920, height: 1080), in: tile))
    #expect(!ThumbnailFit.showsWhole(CGSize(width: 1920, height: 1080), in: card))
    #expect(!ThumbnailFit.showsWhole(CGSize(width: 1350, height: 572), in: card))
    #expect(!ThumbnailFit.showsWhole(CGSize(width: 307, height: 307), in: tile))
}

@Test func tallCapturesFill() {
    // A scrolling capture of a chat thread keeps the full width of each line.
    #expect(!ThumbnailFit.showsWhole(CGSize(width: 812, height: 2168), in: tile))
}

@Test func theLimitIsWhereFillingShowsFiveEighthsOfTheWidth() {
    // 1.6 times the tile's 4:3 is 2.13:1.
    #expect(!ThumbnailFit.showsWhole(CGSize(width: 256, height: 120), in: tile))
    #expect(ThumbnailFit.showsWhole(CGSize(width: 257, height: 120), in: tile))
}

@Test func emptySizesFill() {
    #expect(!ThumbnailFit.showsWhole(.zero, in: tile))
    #expect(!ThumbnailFit.showsWhole(CGSize(width: 494, height: 140), in: .zero))
}
