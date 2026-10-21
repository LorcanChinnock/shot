import AppKit
import Observation

/// The system scroller, which follows System Settings › Appearance › Show scroll bars. An overlay scroller floats over the
/// content, so a view leaves `overlayRoom` clear at its trailing edge; a legacy ("Always") one takes its width from the
/// scroll view itself.
@MainActor
@Observable
final class SystemScroller {
    static let shared = SystemScroller()

    /// The scroller's width, in either style.
    let width = NSScroller.scrollerWidth(for: .regular, scrollerStyle: .overlay)
    private(set) var overlays = NSScroller.preferredScrollerStyle == .overlay
    @ObservationIgnored private var observer: NSObjectProtocol?

    /// Room content leaves at its trailing edge so the scroller doesn't cover it.
    var overlayRoom: CGFloat {
        overlays ? width : 0
    }

    private init() {
        observer = NotificationCenter.default.addObserver(forName: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.overlays = NSScroller.preferredScrollerStyle == .overlay }
        }
    }
}
