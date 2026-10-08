/// Frames already fetched from a video, by the time each was asked for, so a strip that changes how many frames it shows
/// reuses those still near the middle of a slot instead of fetching them again.
public struct ThumbnailCache<Frame> {
    private let limit: Int
    /// Oldest first; past `limit` the oldest are dropped.
    private var frames: [(time: Double, frame: Frame)] = []

    public init(limit: Int = 600) {
        self.limit = limit
    }

    public mutating func insert(_ frame: Frame, at time: Double) {
        frames.removeAll { $0.time == time }
        frames.append((time, frame))
        if frames.count > limit {
            frames.removeFirst(frames.count - limit)
        }
    }

    /// For each of `times`, the middles of slots `spacing` apart, a frame fetched within a quarter of a slot of it.
    /// Less than half a slot, so one frame never fills two slots and leaves the finer frames unfetched.
    public func frames(for times: [Double], spacing: Double) -> [Frame?] {
        times.map { time in
            guard let nearest = frames.min(by: { abs($0.time - time) < abs($1.time - time) }), abs(nearest.time - time) <= spacing / 4 else {
                return nil
            }
            return nearest.frame
        }
    }
}
