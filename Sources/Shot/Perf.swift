import Darwin
import Foundation
import os

/// Signposts around the paths with budgets in `docs/performance.md`. `scripts/perf.sh` reads them from the log, and
/// Instruments shows them; they cost almost nothing when nobody reads them.
enum Perf {
    static let signposter = OSSignposter(subsystem: Bundle.main.bundleIdentifier ?? "Shot", category: "perf")

    /// Milliseconds since the kernel started this process, so launch time includes what runs before `main`.
    static func millisecondsSinceLaunch() -> Int? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else {
            return nil
        }
        let start = info.kp_proc.p_un.__p_starttime
        let started = Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000
        return Int((Date().timeIntervalSince1970 - started) * 1000)
    }
}
