import ShotCore
import SwiftUI

/// A card's buttons side by side in the board's proportions, such as Cancel and Move to Trash at equal widths. When a long
/// translation or a larger text size leaves a name wider than its share, they go one above another at full width, the last
/// (the main action) on top, as a macOS alert stacks its buttons (`ButtonRowFit`).
///
/// Give each button's label `.frame(maxWidth: .infinity)` so it fills the width it's given.
struct ButtonRow: Layout {
    var shares: [CGFloat]
    var gap: CGFloat = 8

    private func widths(_ width: CGFloat, _ subviews: Subviews) -> [CGFloat]? {
        let widths = ButtonRowFit.widths(width: width, gap: gap, shares: shares)
        let natural = subviews.map { $0.sizeThatFits(.unspecified).width }
        return ButtonRowFit.fits(natural: natural, widths: widths) ? widths : nil
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.reduce(gap * CGFloat(max(0, subviews.count - 1))) { $0 + $1.sizeThatFits(.unspecified).width }
        if let widths = widths(width, subviews) {
            let height = zip(subviews, widths).map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }.max() ?? 0
            return CGSize(width: width, height: height)
        }
        let heights = subviews.map { $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height }
        return CGSize(width: width, height: heights.reduce(0, +) + gap * CGFloat(max(0, subviews.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        if let widths = widths(bounds.width, subviews) {
            var x = bounds.minX
            for (subview, width) in zip(subviews, widths) {
                subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(width: width, height: bounds.height))
                x += width + gap
            }
            return
        }
        var y = bounds.minY
        for subview in subviews.reversed() {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            subview.place(at: CGPoint(x: bounds.minX, y: y), proposal: ProposedViewSize(width: bounds.width, height: size.height))
            y += size.height + gap
        }
    }
}
