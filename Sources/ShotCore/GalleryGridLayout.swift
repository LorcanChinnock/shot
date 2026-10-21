import CoreGraphics
import Foundation

/// Where the gallery grid puts each section header and row of tiles. Each section starts a new row and, when `titled`,
/// opens with a header; headers and rows are `spacing` apart. The gallery builds only the rows near the view and places
/// them from this, so rows and the scroll bar hold still as you scroll, which a lazy grid's estimated height doesn't.
/// It keeps one value per section, so finding the rows in view doesn't cost more as the gallery grows.
public struct GalleryGridLayout: Equatable, Sendable {
    /// A section's header, or one row of its tiles. `items` are positions in the section, and nil for a header.
    public struct Block: Equatable, Sendable {
        public let section: Int
        public let items: Range<Int>?
        public let top: CGFloat
    }

    public let height: CGFloat
    private let sectionSizes: [Int]
    private let sectionTops: [CGFloat]
    private let titled: Bool
    private let columns: Int
    private let rowHeight: CGFloat
    private let headerHeight: CGFloat
    private let spacing: CGFloat

    public init(sectionSizes: [Int], titled: Bool, columns: Int, rowHeight: CGFloat, headerHeight: CGFloat, spacing: CGFloat) {
        self.sectionSizes = sectionSizes
        self.titled = titled
        self.columns = max(1, columns)
        self.rowHeight = rowHeight
        self.headerHeight = headerHeight
        self.spacing = spacing
        var tops: [CGFloat] = []
        var y: CGFloat = 0
        for size in sectionSizes {
            tops.append(y)
            y += Self.sectionHeight(rows: (size + self.columns - 1) / self.columns, titled: titled, rowHeight: rowHeight, headerHeight: headerHeight, spacing: spacing) + spacing
        }
        sectionTops = tops
        height = sectionSizes.isEmpty ? 0 : y - spacing
    }

    /// The headers and rows that overlap `range`, top to bottom.
    public func blocks(in range: Range<CGFloat>) -> [Block] {
        let pitch = rowHeight + spacing
        guard pitch > 0 else {
            return []
        }
        var blocks: [Block] = []
        for (section, top) in sectionTops.enumerated() {
            guard top < range.upperBound else {
                break
            }
            let size = sectionSizes[section]
            let rows = rowCount(size)
            guard top + Self.sectionHeight(rows: rows, titled: titled, rowHeight: rowHeight, headerHeight: headerHeight, spacing: spacing) > range.lowerBound else {
                continue
            }
            if titled, top + headerHeight > range.lowerBound {
                blocks.append(Block(section: section, items: nil, top: top))
            }
            let rowsTop = top + headerRoom
            // Row r spans rowsTop + r * pitch ..< that + rowHeight.
            let first = max(0, Int(((range.lowerBound - rowsTop - rowHeight) / pitch).rounded(.down)) + 1)
            let last = min(rows - 1, Int(((range.upperBound - rowsTop) / pitch).rounded(.up)) - 1)
            if first <= last {
                for row in first...last {
                    blocks.append(Block(section: section, items: row * columns..<min((row + 1) * columns, size), top: rowsTop + CGFloat(row) * pitch))
                }
            }
        }
        return blocks
    }

    /// The span of the row holding the item at `index` among all the sections' items, or nil when there's no such item.
    public func rowSpan(ofItem index: Int) -> Range<CGFloat>? {
        var start = 0
        for (section, size) in sectionSizes.enumerated() {
            if index >= start, index < start + size {
                let top = sectionTops[section] + headerRoom + CGFloat((index - start) / columns) * (rowHeight + spacing)
                return top..<top + rowHeight
            }
            start += size
        }
        return nil
    }

    private var headerRoom: CGFloat {
        titled ? headerHeight + spacing : 0
    }

    private func rowCount(_ size: Int) -> Int {
        (size + columns - 1) / columns
    }

    private static func sectionHeight(rows: Int, titled: Bool, rowHeight: CGFloat, headerHeight: CGFloat, spacing: CGFloat) -> CGFloat {
        let blocks = rows + (titled ? 1 : 0)
        return CGFloat(rows) * rowHeight + (titled ? headerHeight : 0) + CGFloat(max(0, blocks - 1)) * spacing
    }
}
