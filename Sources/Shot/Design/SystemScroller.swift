import AppKit
import SwiftUI

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

extension View {
    /// Draws the scroller without its track, so a legacy ("Always") scroller's bar sits on the glass like an overlay one.
    /// Apply it to the `ScrollView`'s content.
    func tracklessScroller() -> some View {
        background(TracklessScrollerProbe())
    }
}

/// Finds the `NSScrollView` behind a SwiftUI `ScrollView` and swaps its vertical scroller for a `TracklessScroller`.
private struct TracklessScrollerProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ProbeView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ProbeView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let scrollView = enclosingScrollView, !(scrollView.verticalScroller is TracklessScroller) else {
                return
            }
            // A new scroller starts out legacy; the scroll view updates it from here when the setting changes.
            let scroller = TracklessScroller()
            scroller.scrollerStyle = scrollView.scrollerStyle
            scrollView.verticalScroller = scroller
        }
    }
}

private final class TracklessScroller: NSScroller {
    /// AppKit falls back to legacy scrollers for a subclass that draws, unless it says it can overlay.
    override class var isCompatibleWithOverlayScrollers: Bool {
        true
    }

    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
}
