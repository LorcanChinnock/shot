import Foundation

/// Notices the captures that arrive in the capture folder after it starts, for `wait_for_capture` and `shot watch`.
/// It only compares what the folder lists from one look to the next, so it reads no file and needs no setting.
public struct CaptureWatch: Sendable {
    /// How often `watch` looks at the folder.
    public static let interval: Duration = .milliseconds(500)

    public var kind: AgentCaptures.Kind
    /// Every path the folder held at the start, and every capture reported since.
    private var seen: Set<String>
    /// The size each new file had at the last look, until it stops growing.
    private var sizes: [String: Int] = [:]

    /// Starts from `entries`, what the folder holds now, none of which counts as new.
    public init(_ entries: [AgentCaptures.Entry], kind: AgentCaptures.Kind = .any) {
        self.kind = kind
        seen = Set(entries.map(\.url.path))
    }

    /// The captures of `kind` in `entries` that weren't there before, oldest first, each reported once. A file whose
    /// size is known waits until it's the same size at two looks in a row, so a recording still being written isn't
    /// handed over half done. An image saved again from the editor as "X (2).png" is new, as `AgentCaptures.ranked`
    /// lists it in place of "X.png".
    public mutating func arrivals(in entries: [AgentCaptures.Entry]) -> [AgentCaptures.Entry] {
        var arrived: [AgentCaptures.Entry] = []
        for entry in AgentCaptures.ranked(entries, kind: kind).reversed() where !seen.contains(entry.url.path) {
            let path = entry.url.path
            if let bytes = entry.bytes {
                guard bytes > 0, sizes[path] == bytes else {
                    sizes[path] = bytes
                    continue
                }
            }
            sizes[path] = nil
            seen.insert(path)
            arrived.append(entry)
        }
        return arrived
    }

    /// Looks at `entries` every `interval` for up to `timeout` seconds, or until cancelled, handing each new capture
    /// to `each`, which returns false to stop. Without a timeout it runs until `each` stops it or the task is cancelled.
    public static func watch(
        kind: AgentCaptures.Kind = .any,
        timeout: Double?,
        interval: Duration = interval,
        entries: @Sendable () -> [AgentCaptures.Entry],
        each: (AgentCaptures.Entry) async -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = timeout.map { clock.now + .milliseconds(Int64(max($0, 0) * 1000)) }
        var watch = CaptureWatch(entries(), kind: kind)
        while !Task.isCancelled {
            if let deadline, clock.now >= deadline {
                return
            }
            let pause = deadline.map { min(interval, clock.now.duration(to: $0)) } ?? interval
            do {
                try await Task.sleep(for: pause)
            } catch {
                return
            }
            for entry in watch.arrivals(in: entries()) {
                guard await each(entry) else {
                    return
                }
            }
        }
    }

    /// The next capture of `kind` to arrive within `timeout` seconds, or nil.
    public static func next(
        kind: AgentCaptures.Kind = .any,
        timeout: Double,
        interval: Duration = interval,
        entries: @Sendable () -> [AgentCaptures.Entry]
    ) async -> AgentCaptures.Entry? {
        var found: AgentCaptures.Entry?
        await watch(kind: kind, timeout: timeout, interval: interval, entries: entries) { entry in
            found = entry
            return false
        }
        return found
    }
}
