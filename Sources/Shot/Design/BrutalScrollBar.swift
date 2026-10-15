import ShotCore
import SwiftUI

extension View {
    /// Swaps a `ScrollView`'s scroller for a brutal one along its trailing edge: an ink thumb in a faint groove, shown
    /// whenever the content overflows. Drag the thumb or click the groove to page. The bar overlays the content, so leave
    /// `BrutalScrollBar.gutter` of room at the trailing edge, plus `inset`, which moves the bar in from that edge. Apply it
    /// to the `ScrollView` itself, before other modifiers.
    func brutalScrollBar(inset: CGFloat = 0) -> some View {
        modifier(BrutalScrollBarModifier(inset: inset))
    }
}

enum BrutalScrollBar {
    static let width: CGFloat = 10
    /// Clear space on either side of the bar: from the content's shadows, and from a window's border.
    static let clearance: CGFloat = 10
    /// Room content leaves at its trailing edge for the bar, with `clearance` past a card's shadow.
    static let gutter = Brutal.shadow + clearance + width
    /// How far a window's scroll view reaches past `Brutal.windowInset` into the margin, so the bar sits `clearance` inside
    /// the window's border without narrowing the content.
    static let windowOutset = Brutal.windowInset - Brutal.border - clearance
    /// The inset for a scroll view that runs up to a panel's ink border, which keeps the bar `Brutal.minGap` clear of it.
    static let panelInset = Brutal.border + Brutal.minGap
}

private struct ScrollMetrics: Equatable {
    var content: CGFloat = 0
    var viewport: CGFloat = 0
    var offset: CGFloat = 0
}

private struct BrutalScrollBarModifier: ViewModifier {
    let inset: CGFloat
    @State private var position = ScrollPosition()
    @State private var metrics = ScrollMetrics()

    func body(content: Content) -> some View {
        content
            .scrollIndicators(.hidden)
            .scrollPosition($position)
            .onScrollGeometryChange(for: ScrollMetrics.self) { geometry in
                ScrollMetrics(
                    content: geometry.contentSize.height,
                    viewport: geometry.visibleRect.height,
                    offset: geometry.visibleRect.minY
                )
            } action: { _, new in
                metrics = new
            }
            .overlay(alignment: .trailing) {
                ScrollBarTrack(metrics: metrics) { offset in
                    position.scrollTo(y: offset)
                }
                .padding(.trailing, inset)
            }
    }
}

private struct ScrollBarTrack: View {
    private static let minThumb: CGFloat = 28
    /// Keeps the thumb's ink off the groove's ends.
    private static let thumbInset: CGFloat = 2

    let metrics: ScrollMetrics
    let scrollTo: (CGFloat) -> Void
    /// The thumb's offset when the current drag began.
    @State private var dragStart: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            let track = geometry.size.height - Self.thumbInset * 2
            if let thumb = ScrollThumb.layout(content: metrics.content, viewport: metrics.viewport, offset: metrics.offset, track: track, minLength: Self.minThumb) {
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: Brutal.Radius.tiny, style: .circular)
                        .fill(Brutal.faint(0.08))
                        .contentShape(Rectangle())
                        .gesture(SpatialTapGesture().onEnded { tap in
                            let y = tap.location.y - Self.thumbInset
                            guard y < thumb.offset || y > thumb.offset + thumb.length else {
                                return
                            }
                            scrollTo(ScrollThumb.pagedOffset(content: metrics.content, viewport: metrics.viewport, offset: metrics.offset, forward: y > thumb.offset))
                        })
                    Color.clear.brutalSurface(Brutal.yellow, radius: Brutal.Radius.tiny, shadow: 0, border: 2)
                        .frame(height: thumb.length)
                        .offset(y: Self.thumbInset + thumb.offset)
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("brutalScrollTrack")).onChanged { drag in
                            let start = dragStart ?? thumb.offset
                            dragStart = start
                            scrollTo(thumb.contentOffset(forThumbOffset: start + drag.translation.height, content: metrics.content, viewport: metrics.viewport, track: track))
                        }.onEnded { _ in
                            dragStart = nil
                        })
                }
                .coordinateSpace(.named("brutalScrollTrack"))
                .accessibilityElement()
                .accessibilityLabel(Text("Scroll bar"))
                .accessibilityValue(Text(Double(metrics.offset / max(metrics.content - metrics.viewport, 1)), format: .percent.precision(.fractionLength(0))))
                .accessibilityAdjustableAction { direction in
                    scrollTo(ScrollThumb.pagedOffset(content: metrics.content, viewport: metrics.viewport, offset: metrics.offset, forward: direction == .increment))
                }
            }
        }
        .frame(width: BrutalScrollBar.width)
    }
}
