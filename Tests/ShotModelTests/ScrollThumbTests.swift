import Foundation
import Testing
@testable import ShotModel

@Test func thumbIsAbsentWhenTheContentFits() {
    #expect(ScrollThumb.layout(content: 300, viewport: 300, offset: 0, track: 300, minLength: 24) == nil)
    #expect(ScrollThumb.layout(content: 200, viewport: 300, offset: 0, track: 300, minLength: 24) == nil)
    #expect(ScrollThumb.layout(content: 600, viewport: 0, offset: 0, track: 300, minLength: 24) == nil)
}

@Test func thumbLengthIsTheVisibleShareOfTheTrack() {
    let thumb = ScrollThumb.layout(content: 600, viewport: 300, offset: 0, track: 300, minLength: 24)
    #expect(thumb == ScrollThumb(length: 150, offset: 0))
}

@Test func thumbTravelsToTheEndOfTheTrackAtTheEndOfTheContent() {
    #expect(ScrollThumb.layout(content: 600, viewport: 300, offset: 150, track: 300, minLength: 24)?.offset == 75)
    #expect(ScrollThumb.layout(content: 600, viewport: 300, offset: 300, track: 300, minLength: 24)?.offset == 150)
    // Rubber-banding past either end keeps the thumb on the track.
    #expect(ScrollThumb.layout(content: 600, viewport: 300, offset: 340, track: 300, minLength: 24)?.offset == 150)
    #expect(ScrollThumb.layout(content: 600, viewport: 300, offset: -40, track: 300, minLength: 24)?.offset == 0)
}

@Test func thumbNeverShrinksBelowTheMinimum() {
    let thumb = ScrollThumb.layout(content: 30000, viewport: 300, offset: 0, track: 300, minLength: 24)
    #expect(thumb?.length == 24)
}

@Test func draggingTheThumbMapsBackToAContentOffset() throws {
    let thumb = try #require(ScrollThumb.layout(content: 600, viewport: 300, offset: 0, track: 300, minLength: 24))
    #expect(thumb.contentOffset(forThumbOffset: 75, content: 600, viewport: 300, track: 300) == 150)
    #expect(thumb.contentOffset(forThumbOffset: 150, content: 600, viewport: 300, track: 300) == 300)
    #expect(thumb.contentOffset(forThumbOffset: 900, content: 600, viewport: 300, track: 300) == 300)
    #expect(thumb.contentOffset(forThumbOffset: -9, content: 600, viewport: 300, track: 300) == 0)
}

@Test func pagingMovesAlmostAViewportAndStopsAtTheEnds() {
    #expect(ScrollThumb.pagedOffset(content: 1000, viewport: 100, offset: 0, forward: true) == 90)
    #expect(ScrollThumb.pagedOffset(content: 1000, viewport: 100, offset: 50, forward: false) == 0)
    #expect(ScrollThumb.pagedOffset(content: 1000, viewport: 100, offset: 850, forward: true) == 900)
}
