import Testing
@testable import ShotCore

struct ThumbnailCacheTests {
    private let timeline = TrimTimeline(duration: 10, minX: 0, width: 0)

    private func cache(count: Int) -> ThumbnailCache<Double> {
        var cache = ThumbnailCache<Double>()
        for time in timeline.thumbnailTimes(count: count) {
            cache.insert(time, at: time)
        }
        return cache
    }

    @Test func theSameSlotsReuseEveryFrame() {
        let times = timeline.thumbnailTimes(count: 4)
        #expect(cache(count: 4).frames(for: times, spacing: 2.5) == times)
    }

    @Test func fewerSlotsReuseFramesNearTheirMiddles() {
        // Slots at 1.25, 3.75, 6.25, 8.75 becoming 2.5 and 7.5.
        #expect(cache(count: 4).frames(for: timeline.thumbnailTimes(count: 2), spacing: 5) == [1.25, 6.25])
    }

    @Test func aFrameNeverStandsInForTwoSlots() {
        // Slots at 2.5 and 7.5 split into four, each a half slot from the old middles.
        #expect(cache(count: 2).frames(for: timeline.thumbnailTimes(count: 4), spacing: 2.5) == [nil, nil, nil, nil])
    }

    @Test func theOldestFramesAreDroppedPastTheLimit() {
        var cache = ThumbnailCache<Double>(limit: 2)
        for time in [1.0, 2.0, 3.0] {
            cache.insert(time, at: time)
        }
        #expect(cache.frames(for: [1, 2, 3], spacing: 0.1) == [nil, 2, 3])
    }
}
