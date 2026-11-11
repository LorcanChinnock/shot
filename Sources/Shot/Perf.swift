import AppKit
import Darwin
import Foundation
import os
import QuartzCore

/// Signposts around the paths with budgets in `docs/performance.md`. `scripts/perf.sh` reads them from the log, and
/// Instruments shows them; they cost almost nothing when nobody reads them.
enum Perf {
    static let signposter = OSSignposter(logger: .shot("perf"))

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

    /// Begins a `name` interval, or returns nil when nothing records signposts.
    static func begin(_ name: StaticString) -> OSSignpostIntervalState? {
        guard signposter.isEnabled else {
            return nil
        }
        return signposter.beginInterval(name, id: signposter.makeSignpostID())
    }

    /// Ends `interval` when Core Animation commits this run loop pass's frame, which carries the layout and drawing of
    /// what changed in it. `what` names what opened, such as `settings`.
    @MainActor
    static func endAtCommit(_ name: StaticString, _ interval: OSSignpostIntervalState?, _ what: String) {
        guard let interval else {
            return
        }
        CATransaction.setCompletionBlock {
            signposter.endInterval(name, interval, "\(what, privacy: .public)")
        }
    }

    /// Times a window ("Window open") from `interval`, or from now, until the frame that first shows it. Call it in the run
    /// loop pass that orders the window in.
    @MainActor
    static func measureWindowOpen(_ what: String, since interval: OSSignpostIntervalState? = nil) {
        endAtCommit("Window open", interval ?? begin("Window open"), what)
    }

    /// Marks the menu bar menu as shown ("Menu shown") when its tracking loop first runs, which is after macOS has built and
    /// drawn it. A click on the menu bar icon never reaches the app's event monitors, so `scripts/perf.sh` times the menu
    /// from its own click to this event.
    @MainActor
    static func watchMenuOpening() {
        guard signposter.isEnabled else {
            return
        }
        NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { notification in
            // The menu bar's own menus are tracked as the main menu, so anything else is a menu Shot opened.
            let opened = (notification.object as? NSMenu).map(ObjectIdentifier.init)
            MainActor.assumeIsolated {
                guard let opened, opened != NSApp.mainMenu.map(ObjectIdentifier.init) else {
                    return
                }
                RunLoop.main.perform(inModes: [.eventTracking]) {
                    signposter.emitEvent("Menu shown")
                }
            }
        }
    }
}
