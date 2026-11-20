import CoreGraphics
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

@Test func galleryTilesKeepTheirSizeWhileColumnsReflow() {
    // 190-point tiles, 10 apart: a column takes 200 points.
    #expect(Gallery.grid(available: 190, tileSize: 190, spacing: 10).columns == 1)
    #expect(Gallery.grid(available: 389, tileSize: 190, spacing: 10).columns == 1)
    #expect(Gallery.grid(available: 390, tileSize: 190, spacing: 10).columns == 2)
    #expect(Gallery.grid(available: 595, tileSize: 190, spacing: 10).cell == 190)
    // A window narrower than a tile shrinks it, and never to nothing.
    #expect(Gallery.grid(available: 150, tileSize: 190, spacing: 10).cell == 150)
    #expect(Gallery.grid(available: 0, tileSize: 190, spacing: 10).cell == 1)
}

@Test func gridLayoutFindsTheItemUnderAPoint() {
    // Header 0, rows 30 140 250 for items 0-4, header 360, rows 390 500 for items 5-7.
    let layout = GalleryGridLayout(sectionSizes: [5, 3], titled: true, columns: 2, rowHeight: 100, headerHeight: 20, spacing: 10)
    #expect(layout.item(at: 50, column: 0) == 0)
    #expect(layout.item(at: 150, column: 1) == 3)
    // Past the last tile of a short row, the last tile.
    #expect(layout.item(at: 300, column: 1) == 4)
    #expect(layout.item(at: 395, column: 1) == 6)
    // A header and the gap between rows hold no item.
    #expect(layout.item(at: 10, column: 0) == nil)
    #expect(layout.item(at: 135, column: 0) == nil)
}
