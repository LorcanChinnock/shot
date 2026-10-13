import ShotCore
import SwiftUI

extension View {
    /// Swaps a `ScrollView`'s scroller for a brutal one along its trailing edge: an ink track and thumb, shown whenever the
    /// content overflows. Drag the thumb or click the track to page. The bar overlays the content, so leave
    /// `BrutalScrollBar.width` of room at the trailing edge. Apply it to the `ScrollView` itself, before other modifiers.
    func brutalScrollBar() -> some View {
        modifier(BrutalScrollBarModifier())
    }
}

enum BrutalScrollBar {
    static let width: CGFloat = 12
}

private struct ScrollMetrics: Equatable {
    var content: CGFloat = 0
    var viewport: CGFloat = 0
    var offset: CGFloat = 0
}

private struct BrutalScrollBarModifier: ViewModifier {
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
            }
    }
}

private struct ScrollBarTrack: View {
    private static let minThumb: CGFloat = 28

    let metrics: ScrollMetrics
    let scrollTo: (CGFloat) -> Void
    /// The thumb's offset when the current drag began.
    @State private var dragStart: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            let track = geometry.size.height
            if let thumb = ScrollThumb.layout(content: metrics.content, viewport: metrics.viewport, offset: metrics.offset, track: track, minLength: Self.minThumb) {
                ZStack(alignment: .top) {
                    Color.white
                        .contentShape(Rectangle())
                        .gesture(SpatialTapGesture().onEnded { tap in
                            guard tap.location.y < thumb.offset || tap.location.y > thumb.offset + thumb.length else {
                                return
                            }
                            scrollTo(ScrollThumb.pagedOffset(content: metrics.content, viewport: metrics.viewport, offset: metrics.offset, forward: tap.location.y > thumb.offset))
                        })
                    Color.clear.brutalSurface(Brutal.yellow, radius: Brutal.Radius.tiny, shadow: 0, border: 2)
                        .frame(height: thumb.length)
                        .offset(y: thumb.offset)
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("brutalScrollTrack")).onChanged { drag in
                            let start = dragStart ?? thumb.offset
                            dragStart = start
                            scrollTo(thumb.contentOffset(forThumbOffset: start + drag.translation.height, content: metrics.content, viewport: metrics.viewport, track: track))
                        }.onEnded { _ in
                            dragStart = nil
                        })
                }
                .coordinateSpace(.named("brutalScrollTrack"))
                .inkBorder(RoundedRectangle(cornerRadius: Brutal.Radius.tiny, style: .circular), width: 2)
                .accessibilityElement()
                .accessibilityLabel(Text("Scroll bar"))
                .accessibilityValue(Text(Double(metrics.offset / max(metrics.content - metrics.viewport, 1)), format: .percent.precision(.fractionLength(0))))
                .accessibilityAdjustableAction { direction in
                    scrollTo(ScrollThumb.pagedOffset(content: metrics.content, viewport: metrics.viewport, offset: metrics.offset, forward: direction == .increment))
                }
            }
        }
        .frame(width: BrutalScrollBar.width)
        .padding(.vertical, 2)
    }
}
