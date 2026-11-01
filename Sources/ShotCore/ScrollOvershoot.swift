import Foundation

/// Finds the rubber-band bounce at the end of a scroll: the content is pulled past its end, which shows the background
/// beyond it, and springs back. The frames of the pull line up like any others, so the background lands in the image
/// as a few more rows. A bounce is the image's edge being pushed out and the area then coming back and settling short
/// of it; what lies beyond where it settles is the bounce if it's a small, flat stretch. Nothing is taken out while
/// capturing, since the person may scroll on and make those rows content; the ones that are still the image's
/// outermost rows when it's done are cut.
struct ScrollOvershoot {
    /// Edges in this order: top, bottom, left, right.
    private struct Run {
        /// How far the image reaches on this edge now.
        var reach: Int
        /// The last frame that pushed it out.
        var lastPush: Int
        var returning = false
        var stillFrames = 0
        var lastView: Int
    }

    private var pending: [Run?] = Array(repeating: nil, count: 4)
    private var trims: [[(base: Int, reach: Int)]] = Array(repeating: [], count: 4)

    /// A bounce settles within about a second of its peak: this many frames at most after the last push.
    private static let settling = 36
    /// Frames the area must hold still to have settled, and how far it can drift in one and still count as still.
    private static let stillNeeded = 3
    /// In points: 1.5, which is 3 pixels at 2x.
    private static let drift = 1.5
    /// How much of the area a bounce can pull past the end.
    private static let share = 4

    typealias Extremes = (minX: Int, maxX: Int, minY: Int, maxY: Int)

    /// How far the image reaches past the origin on `edge`, in pixels.
    private static func reach(_ extremes: Extremes, edge: Int, width: Int, height: Int) -> Int {
        switch edge {
        case 0: -extremes.minY
        case 1: extremes.maxY + height
        case 2: -extremes.minX
        default: extremes.maxX + width
        }
    }

    /// How far the area itself reaches on `edge`.
    private static func view(_ position: (x: Int, y: Int), edge: Int, width: Int, height: Int) -> Int {
        switch edge {
        case 0: -position.y
        case 1: position.y + height
        case 2: -position.x
        default: position.x + width
        }
    }

    /// The world rectangle that rows `base..<reach` past the origin on `edge` take up.
    static func region(_ edge: Int, base: Int, reach: Int) -> ScrollCanvas.Bounds {
        let huge = 1 << 30
        switch edge {
        case 0: return ScrollCanvas.Bounds(x0: -huge, y0: -reach, x1: huge, y1: -base)
        case 1: return ScrollCanvas.Bounds(x0: -huge, y0: base, x1: huge, y1: reach)
        case 2: return ScrollCanvas.Bounds(x0: -reach, y0: -huge, x1: -base, y1: huge)
        default: return ScrollCanvas.Bounds(x0: base, y0: -huge, x1: reach, y1: huge)
        }
    }

    /// Takes one frame: the image's extremes before and after it, and where the area is now.
    /// Whether a bounce settled with this frame, the frame the area rested on.
    @discardableResult
    mutating func update(frame: Int, before: Extremes, after: Extremes, position: (x: Int, y: Int), width: Int, height: Int, scale: Int) -> Bool {
        var settled = false
        let drift = Int((Self.drift * Double(scale)).rounded(.down))
        for edge in 0..<4 {
            let was = Self.reach(before, edge: edge, width: width, height: height)
            let now = Self.reach(after, edge: edge, width: width, height: height)
            let view = Self.view(position, edge: edge, width: width, height: height)
            if now > was {
                pending[edge] = Run(reach: now, lastPush: frame, lastView: view)
                continue
            }
            guard var run = pending[edge] else {
                continue
            }
            if frame - run.lastPush > Self.settling {
                pending[edge] = nil
                continue
            }
            run.stillFrames = abs(view - run.lastView) <= drift ? run.stillFrames + 1 : 0
            run.lastView = view
            if view < run.reach - drift {
                run.returning = true
            }
            if run.returning, run.stillFrames >= Self.stillNeeded {
                let limit = (edge < 2 ? height : width) / Self.share
                if run.reach - view > 0, run.reach - view <= limit {
                    trims[edge].append((view, run.reach))
                    settled = true
                }
                pending[edge] = nil
            } else {
                pending[edge] = run
            }
        }
        return settled
    }

    /// Settles the bounces still under way when the capture ends, as the person pressing Return does while one is.
    mutating func finish(width: Int, height: Int) {
        for edge in 0..<4 {
            guard let run = pending[edge], run.returning else {
                continue
            }
            let limit = (edge < 2 ? height : width) / Self.share
            if run.reach - run.lastView > 0, run.reach - run.lastView <= limit {
                trims[edge].append((run.lastView, run.reach))
            }
            pending[edge] = nil
        }
    }

    /// What of the image to keep: `seen` without the bounced rows that are still its outermost and have nothing in
    /// them, as `isBlank` says of the image as it would be without cutting.
    func kept(of seen: ScrollCanvas.Bounds, isBlank: (_ edge: Int, _ base: Int, _ reach: Int) -> Bool) -> ScrollCanvas.Bounds {
        var kept = seen
        func settle(_ edge: Int, _ start: Int) -> Int {
            var current = start
            while let trim = trims[edge].first(where: { $0.reach == current && isBlank(edge, $0.base, $0.reach) }) {
                current = trim.base
            }
            return current
        }
        kept.y0 = -settle(0, -seen.y0)
        kept.y1 = settle(1, seen.y1)
        kept.x0 = -settle(2, -seen.x0)
        kept.x1 = settle(3, seen.x1)
        return kept
    }
}
