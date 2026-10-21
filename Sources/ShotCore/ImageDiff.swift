import Foundation

/// Where two images of the same size differ, for `shot diff` and the MCP `compare` tool: which pixels changed, and those
/// pixels gathered into a few boxes an agent can read. It works on RGBA bytes, so it's tested on Linux; ShotCore reads
/// the images into bytes and draws the result.
public enum ImageDiff {
    /// A changed region, in the image's pixels, top-left origin.
    public struct Region: Equatable, Sendable {
        public var x: Int
        public var y: Int
        public var width: Int
        public var height: Int

        public init(x: Int, y: Int, width: Int, height: Int) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        public var area: Int { width * height }

        /// `[x, y, width, height]`, as the marks and `redact` take a rect.
        public var rect: [Int] { [x, y, width, height] }

        /// Whether the two overlap, or come within `gap` pixels of each other.
        func near(_ other: Region, gap: Int) -> Bool {
            x - gap <= other.x + other.width && other.x - gap <= x + width
                && y - gap <= other.y + other.height && other.y - gap <= y + height
        }

        func union(_ other: Region) -> Region {
            let left = min(x, other.x), top = min(y, other.y)
            let right = max(x + width, other.x + other.width), bottom = max(y + height, other.y + other.height)
            return Region(x: left, y: top, width: right - left, height: bottom - top)
        }
    }

    /// How much a channel may differ, as a share of its range, before the pixel counts as changed: enough to ignore
    /// anti-aliasing and JPEG noise, but not a real change in colour.
    public static let defaultThreshold = 0.1
    /// Changes this close together, in pixels, are one region, so a changed line of text is one box rather than a box
    /// per letter.
    public static let defaultGap = 16
    /// The most regions a result lists, the largest ones, so a page that changed everywhere still reads in one go.
    public static let maximumRegions = 50

    /// One byte per pixel, 1 where any channel of `a` and `b` differs by more than `threshold` of its range, else 0.
    /// Both are 8-bit RGBA, `width` by `height`, with `bytesPerRow` each.
    public static func changes(_ a: [UInt8], _ b: [UInt8], width: Int, height: Int, bytesPerRow: Int, threshold: Double = defaultThreshold) -> [UInt8] {
        precondition(a.count >= bytesPerRow * height && b.count >= bytesPerRow * height && bytesPerRow >= width * 4)
        // A difference above `limit` counts; a threshold of 0 counts any difference at all.
        let limit = Int((min(max(threshold, 0), 1) * 255).rounded(.down))
        var mask = [UInt8](repeating: 0, count: width * height)
        a.withUnsafeBufferPointer { a in
            b.withUnsafeBufferPointer { b in
                mask.withUnsafeMutableBufferPointer { mask in
                    for y in 0 ..< height {
                        let row = y * bytesPerRow
                        for x in 0 ..< width {
                            let i = row + x * 4
                            var most = 0
                            for c in 0 ..< 4 {
                                most = max(most, abs(Int(a[i + c]) - Int(b[i + c])))
                            }
                            if most > limit {
                                mask[y * width + x] = 1
                            }
                        }
                    }
                }
            }
        }
        return mask
    }

    /// The changed pixels in `mask` gathered into boxes: changes about `gap` pixels apart or closer share a box, as do
    /// boxes that overlap or come that close. Each box is tight around its changed pixels. In reading order, top
    /// to bottom then left to right.
    public static func regions(in mask: [UInt8], width: Int, height: Int, gap: Int = defaultGap) -> [Region] {
        precondition(mask.count >= width * height)
        let cell = max(gap, 1)
        let columns = (width + cell - 1) / cell, rows = (height + cell - 1) / cell
        // The tight bounds of the changed pixels in each cell, or nil for a cell with none.
        var bounds = [Region?](repeating: nil, count: columns * rows)
        mask.withUnsafeBufferPointer { mask in
            for y in 0 ..< height {
                for x in 0 ..< width where mask[y * width + x] != 0 {
                    let index = (y / cell) * columns + x / cell
                    let pixel = Region(x: x, y: y, width: 1, height: 1)
                    bounds[index] = bounds[index].map { $0.union(pixel) } ?? pixel
                }
            }
        }
        // Cells that touch, diagonally too, are one region.
        var regions: [Region] = []
        var seen = [Bool](repeating: false, count: bounds.count)
        for start in bounds.indices where bounds[start] != nil && !seen[start] {
            seen[start] = true
            var stack = [start]
            var region = bounds[start]!
            while let index = stack.popLast() {
                let column = index % columns, row = index / columns
                for dy in -1 ... 1 {
                    for dx in -1 ... 1 {
                        let c = column + dx, r = row + dy
                        guard c >= 0, c < columns, r >= 0, r < rows else { continue }
                        let next = r * columns + c
                        guard !seen[next], let found = bounds[next] else { continue }
                        seen[next] = true
                        region = region.union(found)
                        stack.append(next)
                    }
                }
            }
            regions.append(region)
        }
        return merged(regions, gap: gap)
    }

    /// `regions` with any that overlap or come within `gap` of each other joined, until none do, in reading order.
    static func merged(_ regions: [Region], gap: Int) -> [Region] {
        var regions = regions
        var joined = true
        while joined {
            joined = false
            var index = 0
            while index < regions.count {
                var other = index + 1
                while other < regions.count {
                    if regions[index].near(regions[other], gap: gap) {
                        regions[index] = regions[index].union(regions.remove(at: other))
                        joined = true
                    } else {
                        other += 1
                    }
                }
                index += 1
            }
        }
        return regions.sorted { $0.y != $1.y ? $0.y < $1.y : $0.x < $1.x }
    }

    /// At most `maximumRegions` of `regions`, the largest, still in reading order.
    public static func largest(_ regions: [Region], limit: Int = maximumRegions) -> [Region] {
        guard regions.count > limit else { return regions }
        let kept = regions.enumerated().sorted { $0.element.area != $1.element.area ? $0.element.area > $1.element.area : $0.offset < $1.offset }.prefix(limit)
        return kept.sorted { $0.offset < $1.offset }.map(\.element)
    }
}
