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
    /// Draws the scroller without its track, so a legacy ("Always") scroller's bar sits on the glass like an overlay one, and
    /// shows an overlay scroller while the pointer is over its strip. Apply it to the `ScrollView`'s content.
    func tracklessScroller() -> some View {
        background(TracklessScrollerProbe())
    }
}

/// Finds the `NSScrollView` behind a SwiftUI `ScrollView` and, while scrollers are legacy, swaps its vertical scroller for a
/// `TracklessScroller`. An overlay scroll view keeps SwiftUI's own scroller, because a swapped-in one falls out of step with
/// the scroll view's fade: it stays hidden while you scroll, then won't fade once shown.
private struct TracklessScrollerProbe: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        ProbeView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ProbeView: NSView {
        private var systemScroller: NSScroller?
        /// An overlay scroller hides until you scroll, so it's shown while the pointer is over its strip, where you'd grab it.
        private var hoverArea: (view: NSView, area: NSTrackingArea)?

        override init(frame: NSRect) {
            super.init(frame: frame)
            NotificationCenter.default.addObserver(self, selector: #selector(matchScrollerStyle),
                                                   name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            matchScrollerStyle()
            trackScrollerHover()
        }

        private func trackScrollerHover() {
            if let hoverArea {
                hoverArea.view.removeTrackingArea(hoverArea.area)
                self.hoverArea = nil
            }
            guard window != nil, let scrollView = enclosingScrollView else {
                return
            }
            let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInActiveApp, .inVisibleRect], owner: self)
            scrollView.addTrackingArea(area)
            hoverArea = (scrollView, area)
        }

        override func mouseMoved(with event: NSEvent) {
            guard NSScroller.preferredScrollerStyle == .overlay, let scrollView = enclosingScrollView,
                  let scroller = scrollView.verticalScroller else {
                return
            }
            let point = scrollView.convert(event.locationInWindow, from: nil)
            let strip = scrollView.bounds.divided(atDistance: SystemScroller.shared.width, from: .maxXEdge).slice
            if strip.contains(point), !scroller.isHidden, scroller.knobProportion < 1 {
                scrollView.flashScrollers()
            }
        }

        @objc private func matchScrollerStyle() {
            guard let scrollView = enclosingScrollView else {
                return
            }
            if NSScroller.preferredScrollerStyle == .legacy {
                guard !(scrollView.verticalScroller is TracklessScroller) else {
                    return
                }
                systemScroller = scrollView.verticalScroller
                scrollView.verticalScroller = TracklessScroller()
            } else if let systemScroller, scrollView.verticalScroller is TracklessScroller {
                scrollView.verticalScroller = systemScroller
            }
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
