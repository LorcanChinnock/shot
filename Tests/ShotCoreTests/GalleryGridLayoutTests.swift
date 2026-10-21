#if canImport(CoreGraphics)
import CoreGraphics
#endif
import Foundation
import Testing
@testable import ShotCore

@Test func gridLayoutStacksHeadersAndRows() {
    // Sections of 5 and 3 in 2 columns, rows 100 tall, headers 20, 10 apart:
    // header 0, rows 30 140 250, then header 360, rows 390 500, ending at 600.
    let layout = GalleryGridLayout(sectionSizes: [5, 3], titled: true, columns: 2, rowHeight: 100, headerHeight: 20, spacing: 10)
    #expect(layout.height == 600)
    #expect(layout.blocks(in: 0..<600).map(\.top) == [0, 30, 140, 250, 360, 390, 500])
    #expect(layout.blocks(in: 0..<600).map(\.items) == [nil, 0..<2, 2..<4, 4..<5, nil, 0..<2, 2..<3])
    #expect(layout.rowSpan(ofItem: 4) == 250..<350)
    #expect(layout.rowSpan(ofItem: 7) == 500..<600)
    #expect(layout.rowSpan(ofItem: 8) == nil)
}

@Test func gridLayoutFindsOnlyTheBlocksInRange() {
    let layout = GalleryGridLayout(sectionSizes: [5, 3], titled: true, columns: 2, rowHeight: 100, headerHeight: 20, spacing: 10)
    #expect(layout.blocks(in: 0..<25).map(\.top) == [0])
    #expect(layout.blocks(in: 135..<145).map(\.top) == [140])
    // The last row of one section, the next one's header and its first row.
    #expect(layout.blocks(in: 340..<395).map(\.section) == [0, 1, 1])
    #expect(layout.blocks(in: 340..<395).map(\.top) == [250, 360, 390])
    // The gap between two rows holds nothing.
    #expect(layout.blocks(in: 130..<140).isEmpty)
    #expect(layout.blocks(in: 600..<900).isEmpty)
}

@Test func gridLayoutWithoutTitlesHasNoHeaders() {
    let layout = GalleryGridLayout(sectionSizes: [5], titled: false, columns: 3, rowHeight: 100, headerHeight: 20, spacing: 10)
    #expect(layout.height == 210)
    #expect(layout.blocks(in: 0..<1000).map(\.items) == [0..<3, 3..<5])
    #expect(layout.rowSpan(ofItem: 0) == 0..<100)
    #expect(GalleryGridLayout(sectionSizes: [], titled: true, columns: 3, rowHeight: 100, headerHeight: 20, spacing: 10).height == 0)
}
