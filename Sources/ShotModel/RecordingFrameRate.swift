/// The frame rates a recording can use, and the one it actually records at on a given display.
public enum RecordingFrameRate {
    /// The rates Settings can offer; 120 only when a display refreshes that fast.
    public static let all = [30, 60, 120]
    public static let `default` = 60
    /// Above this the recording is HEVC, since H.264's levels stop short of high-resolution screens at 120 fps.
    public static let highestH264 = 60

    /// The rates worth offering when the fastest display refreshes at `maximumDisplayRate` frames per second.
    public static func offered(maximumDisplayRate: Int) -> [Int] {
        all.filter { $0 <= max(maximumDisplayRate, `default`) }
    }

    /// The rates the picker shows: those `offered`, plus `current` when it's one of `all`, so a 120 chosen on a faster display stays selectable.
    public static func selectable(maximumDisplayRate: Int, current: Int) -> [Int] {
        let rates = offered(maximumDisplayRate: maximumDisplayRate)
        guard all.contains(current), !rates.contains(current) else { return rates }
        return rates + [current]
    }

    /// The rate to record at on a display refreshing at `displayRate`: the setting, unless the display can't offer it.
    /// A setting that isn't one of `all` falls back to the default.
    public static func effective(setting: Int, displayRate: Int) -> Int {
        let chosen = all.contains(setting) ? setting : `default`
        return min(chosen, offered(maximumDisplayRate: displayRate).last ?? `default`)
    }

    /// Whether a recording at `fps` is HEVC rather than H.264.
    public static func usesHEVC(fps: Int) -> Bool {
        fps > highestH264
    }
}
