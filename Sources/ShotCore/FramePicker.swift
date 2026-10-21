import Foundation

/// Picks the frames of a recording that show what happened in it, for an agent that can't watch video: the first, the
/// last, and the frame after each change once it has settled, so a transition shows where it ended rather than a blur
/// halfway. It works on how much each sampled frame differs from the one before, so it needs no image types.
public enum FramePicker {
    /// How different two equally sized grayscale thumbnails are, from 0 for the same to 1 for black against white.
    public static func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
        guard a.count == b.count, !a.isEmpty else {
            return a.count == b.count ? 0 : 1
        }
        var total = 0
        for index in a.indices {
            total += abs(Int(a[index]) - Int(b[index]))
        }
        return Double(total) / Double(a.count) / 255
    }

    /// The indices of at most `count` samples to show, in order. `differences[i]` is how much sample `i` differs from
    /// sample `i - 1` (the first is ignored), and `times` are their times in seconds. Changes closer together than
    /// `minSpacing` count as one, shown once it settles. With fewer changes than `count`, the gaps are filled evenly.
    public static func pick(differences: [Double], times: [Double], count: Int, minSpacing: Double = 0.5) -> [Int] {
        let samples = min(differences.count, times.count)
        guard samples > 0, count > 0 else {
            return []
        }
        guard samples > 1, count > 1 else {
            return [samples - 1]
        }
        let wanted = min(count, samples)
        // A change is a difference well above the recording's usual frame-to-frame noise, such as a cursor moving.
        let changes = Array(differences[1 ..< samples])
        let median = Self.median(changes)
        let spread = Self.median(changes.map { abs($0 - median) })
        let threshold = max(median + 6 * spread, 0.01)

        // Runs of samples above the threshold are one change, shown at the sample after the run, where it settled.
        var events: [(index: Int, size: Double)] = []
        var index = 1
        while index < samples {
            guard differences[index] > threshold else {
                index += 1
                continue
            }
            var size = 0.0
            while index < samples, differences[index] > threshold {
                size += differences[index]
                index += 1
            }
            let settled = min(index, samples - 1)
            if let last = events.last, times[settled] - times[last.index] < minSpacing {
                events[events.count - 1] = (settled, last.size + size)
            } else {
                events.append((settled, size))
            }
        }
        events.removeAll { $0.index == 0 || $0.index == samples - 1 }

        var picked = [0, samples - 1]
        let room = wanted - picked.count
        picked += events.sorted { $0.size > $1.size }.prefix(room).map(\.index)
        picked = Array(Set(picked)).sorted()
        // Too few changes: split the longest gap in time until there are enough, or no gap is left to split.
        while picked.count < wanted {
            let gaps = zip(picked, picked.dropFirst()).filter { $1 - $0 > 1 }
            guard let widest = gaps.max(by: { times[$0.1] - times[$0.0] < times[$1.1] - times[$1.0] }) else {
                break
            }
            let middle = (times[widest.0] + times[widest.1]) / 2
            let split = (widest.0 + 1 ..< widest.1).min { abs(times[$0] - middle) < abs(times[$1] - middle) } ?? widest.0 + 1
            picked.append(split)
            picked.sort()
        }
        return picked
    }

    private static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else {
            return 0
        }
        let sorted = values.sorted()
        return sorted.count % 2 == 1 ? sorted[sorted.count / 2] : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
    }
}
