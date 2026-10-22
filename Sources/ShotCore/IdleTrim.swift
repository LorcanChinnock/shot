import Foundation

/// **Trim Idle Time**: where the action in a recording starts and ends, from how much the picture changes and where
/// the sound is loud enough to be speech. Most recordings open with a few seconds of reaching for the mouse and end with
/// a few reaching for Stop. No AI: it's frame comparison, the samples `KeyFrameExtractor` takes for agents.
public enum IdleTrim {
    /// How much a sample must differ from the one before to count as a change, from 0 to 1. A cursor moving over a
    /// still screen stays under it at 64×36, which is right: that's the idle time being cut.
    static let changeThreshold = 0.0075
    /// Kept either side of the first and last change, so the trim doesn't clip the start of a click.
    static let padding = 0.4
    /// A peak this loud, from 0 to 1, is sound; a run of them at least `speechLength` long, with gaps no longer than
    /// `speechGap`, is speech, which is never cut.
    static let speechLevel: Float = 0.06
    static let speechLength = 0.25
    static let speechGap = 0.3
    /// An end moves only when that saves at least this much, so a trim that would barely change isn't offered.
    static let shortestSaving = 0.3

    /// The range to keep, or `nil` when nothing changes and nothing's said, so there's no action to keep. The full
    /// range when there's no idle time. `differences[i]` is how much sample `i`, at `times[i]`, differs from the one
    /// before (the first is ignored), as `KeyFrameExtractor.differences` gives them; `audio` is the waveform's peaks,
    /// `Waveform.peaksPerSecond` a second, or empty for a recording without sound.
    public static func range(differences: [Double], times: [Double], audio: [WaveformPeak] = [], duration: Double) -> TrimRange? {
        let count = min(differences.count, times.count)
        let changes = (1 ..< max(1, count)).filter { differences[$0] > changeThreshold }
        var spans: [ClosedRange<Double>] = []
        if let first = changes.first, let last = changes.last {
            // A change happens between the sample before it and this one.
            spans.append(times[first - 1] ... times[last])
        }
        if let speech = speech(in: audio) {
            spans.append(speech)
        }
        guard let start = spans.map(\.lowerBound).min(), let end = spans.map(\.upperBound).max() else {
            return nil
        }
        let from = max(0, start - padding), to = min(duration, end + padding)
        return TrimRange(start: from >= shortestSaving ? from : 0, end: duration - to >= shortestSaving ? to : duration, duration: duration)
    }

    /// `found` kept within `current`, so the handles only ever move in and never bring back what the user trimmed off;
    /// `nil` when that leaves nothing to trim.
    public static func tightening(_ current: TrimRange, to found: TrimRange) -> TrimRange? {
        let start = max(current.start, found.start), end = min(current.end, found.end)
        guard end - start >= TrimRange.minimumLength, start > current.start || end < current.end else {
            return nil
        }
        return TrimRange(start: start, end: end, duration: current.end)
    }

    /// From the start of the first stretch of speech to the end of the last, in seconds; `nil` when there's none.
    static func speech(in peaks: [WaveformPeak]) -> ClosedRange<Double>? {
        let step = 1 / Double(Waveform.peaksPerSecond)
        var runs: [ClosedRange<Double>] = []
        for (index, peak) in peaks.enumerated() where max(-peak.min, peak.max) >= speechLevel {
            let time = Double(index) * step
            if let last = runs.last, time - last.upperBound <= speechGap {
                runs[runs.count - 1] = last.lowerBound ... time + step
            } else {
                runs.append(time ... time + step)
            }
        }
        let speech = runs.filter { $0.upperBound - $0.lowerBound >= speechLength }
        guard let first = speech.first, let last = speech.last else {
            return nil
        }
        return first.lowerBound ... last.upperBound
    }
}
