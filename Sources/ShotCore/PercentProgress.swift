import Synchronization

/// Passes on a fraction done as a whole percentage, only when that changes, so progress reported once per frame of a
/// long export reaches the UI at most a hundred times.
public final class PercentProgress: Sendable {
    private let last = Mutex<Int?>(nil)
    private let onChange: @Sendable (Int) -> Void

    public init(_ onChange: @escaping @Sendable (Int) -> Void) {
        self.onChange = onChange
    }

    public func report(_ fraction: Double) {
        let percent = Int(fraction * 100)
        let changed = last.withLock { last in
            defer { last = percent }
            return last != percent
        }
        if changed {
            onChange(percent)
        }
    }
}
